import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/location_suggestion.dart';
import '../services/location_service.dart';

class LocationPicker extends StatefulWidget {
  final Function(double latitude, double longitude, String address, String method)
      onLocationSelected;
  final double? selectedLatitude;
  final double? selectedLongitude;
  final String? selectedAddress;

  const LocationPicker({
    super.key,
    required this.onLocationSelected,
    this.selectedLatitude,
    this.selectedLongitude,
    this.selectedAddress,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final TextEditingController _addressController = TextEditingController();
  MapLibreMapController? _mapController;
  MapLibreMapController? _embeddedMapController;
  BuildContext? _scaffoldContext;
  double? _currentLatitude;
  double? _currentLongitude;
  String? _currentAddress;
  Uint8List? _markerImageBytes;
  final Set<int> _controllersWithMarkerImage = {};
  bool _isLoadingLocation = false;
  String _selectedMethod = 'none';
  bool _isSatelliteMode = false;
  bool _showPinInstructions = false;
  bool _skipNextMarkerRefresh = false;
  final FocusNode _addressFocusNode = FocusNode();
  List<LocationSuggestion> _addressSuggestions = [];
  Timer? _addressDebounce;
  Timer? _addressBlurTimer;
  bool _isAddressFieldFocused = false;
  String? _pendingSuggestionQuery;
  
  // Track symbols to avoid clearing issues
  final Map<int, Symbol> _controllerSymbols = {};

  @override
  void initState() {
    super.initState();
    _currentLatitude = widget.selectedLatitude;
    _currentLongitude = widget.selectedLongitude;
    _currentAddress = widget.selectedAddress;

    if (_currentAddress != null) {
      _addressController.text = _currentAddress!;
    }

    _addressFocusNode.addListener(() {
      if (_addressFocusNode.hasFocus) {
        _addressBlurTimer?.cancel();
        setState(() {
          _isAddressFieldFocused = true;
        });
      } else {
        _addressBlurTimer?.cancel();
        _addressBlurTimer = Timer(const Duration(milliseconds: 150), () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isAddressFieldFocused = false;
            _addressSuggestions = [];
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _addressBlurTimer?.cancel();
    _addressFocusNode.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _showSnackBar(
    SnackBar snackBar, {
    BuildContext? contextOverride,
  }) {
    final messengerContext = contextOverride ?? _scaffoldContext ?? context;
    ScaffoldMessenger.of(messengerContext).showSnackBar(snackBar);
  }

  Future<Uint8List> _createMarkerImageBytes() async {
    const double size = 80;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.location_on.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: Icons.location_on.fontFamily,
        package: Icons.location_on.fontPackage,
        color: Colors.red,
      ),
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      textPainter.width.ceil(),
      textPainter.height.ceil(),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _getMarkerImageBytes() async {
    if (_markerImageBytes != null) {
      return _markerImageBytes!;
    }
    _markerImageBytes = await _createMarkerImageBytes();
    return _markerImageBytes!;
  }

  Future<void> _ensureMarkerImage(MapLibreMapController controller) async {
    final controllerId = controller.hashCode;
    if (_controllersWithMarkerImage.contains(controllerId)) {
      return;
    }

    final bytes = await _getMarkerImageBytes();
    try {
      await controller.addImage('custom-marker', bytes);
      _controllersWithMarkerImage.add(controllerId);
    } catch (_) {
      // The image may already exist for this controller instance.
    }
  }

  Future<void> _clearAnnotations(MapLibreMapController controller) async {
    final controllerId = controller.hashCode;
    final existingSymbol = _controllerSymbols[controllerId];
    
    if (existingSymbol != null) {
      try {
        await controller.removeSymbol(existingSymbol);
      } catch (e) {
        // Ignore errors when removing symbols
        print('Error removing symbol: $e');
      }
      _controllerSymbols.remove(controllerId);
    }
  }

  Future<void> _setMarker(
    double latitude,
    double longitude, {
    MapLibreMapController? controller,
    bool animate = false,
    double zoom = 16,
  }) async {
    final target = controller ?? _mapController;
    if (target == null) {
      return;
    }

    await _ensureMarkerImage(target);
    await _clearAnnotations(target);

    if (animate) {
      await target.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(latitude, longitude),
          zoom,
        ),
      );
    }

    try {
      final symbol = await target.addSymbol(
        SymbolOptions(
          geometry: LatLng(latitude, longitude),
          iconImage: 'custom-marker',
          iconSize: animate ? 1.5 : 1.2,
          iconAnchor: 'bottom',
        ),
      );
      
      // Track the symbol for this controller
      _controllerSymbols[target.hashCode] = symbol;
    } catch (e) {
      print('Error adding symbol: $e');
    }
  }

  Future<void> _updateMarkersOnControllers({
    MapLibreMapController? primary,
    bool animatePrimary = false,
  }) async {
    final lat = _currentLatitude;
    final lng = _currentLongitude;
    if (lat == null || lng == null) {
      return;
    }

    final controllers = <MapLibreMapController>{
      if (_embeddedMapController != null) _embeddedMapController!,
      if (_mapController != null) _mapController!,
    };

    for (final controller in controllers) {
      final animate = animatePrimary && identical(controller, primary);
      await _setMarker(
        lat,
        lng,
        controller: controller,
        animate: animate,
      );
    }
  }

  void _handleStyleLoaded(MapLibreMapController? controller) {
    final target = controller ?? _mapController;
    if (target == null) {
      return;
    }

    _controllersWithMarkerImage.remove(target.hashCode);
    _controllerSymbols.remove(target.hashCode);

    () async {
      await _ensureMarkerImage(target);
      await _updateMarkersOnControllers(primary: target, animatePrimary: false);
    }();
  }

  void _onEmbeddedStyleLoaded() => _handleStyleLoaded(_embeddedMapController);

  void _onFullScreenStyleLoaded() => _handleStyleLoaded(_mapController);

  @override
  void didUpdateWidget(covariant LocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lat = widget.selectedLatitude;
    final lng = widget.selectedLongitude;

    final previousLat = oldWidget.selectedLatitude;
    final previousLng = oldWidget.selectedLongitude;

    final selectionChanged = lat != previousLat || lng != previousLng;
    if (!selectionChanged) {
      return;
    }

    if (lat == null || lng == null) {
      _currentLatitude = null;
      _currentLongitude = null;
      _currentAddress = null;
      _addressController.clear();

      final controllers = <MapLibreMapController>{
        if (_embeddedMapController != null) _embeddedMapController!,
        if (_mapController != null) _mapController!,
      };

      for (final controller in controllers) {
        _clearAnnotations(controller);
      }
      return;
    }

    _currentLatitude = lat;
    _currentLongitude = lng;
    _currentAddress = widget.selectedAddress;

    if (_currentAddress != null) {
      _addressController.text = _currentAddress!;
    }

    if (_skipNextMarkerRefresh) {
      final controllers = <MapLibreMapController>{
        if (_embeddedMapController != null) _embeddedMapController!,
        if (_mapController != null) _mapController!,
      };

      for (final controller in controllers) {
        () async {
          await _clearAnnotations(controller);
        }();
      }

      _skipNextMarkerRefresh = false;
      return;
    }

    _updateMarkersOnControllers(primary: _mapController, animatePrimary: true);
  }

  void _onEmbeddedMapCreated(MapLibreMapController controller) {
    _embeddedMapController = controller;
    _mapController ??= controller;
    _controllersWithMarkerImage.remove(controller.hashCode);
    _controllerSymbols.remove(controller.hashCode);

    () async {
      await _ensureMarkerImage(controller);
      if (_currentLatitude != null && _currentLongitude != null) {
        await _setMarker(
          _currentLatitude!,
          _currentLongitude!,
          controller: controller,
          animate: true,
        );
      }
    }();
  }

  void _onFullScreenMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _controllersWithMarkerImage.remove(controller.hashCode);
    _controllerSymbols.remove(controller.hashCode);

    () async {
      await _ensureMarkerImage(controller);
      if (_currentLatitude != null && _currentLongitude != null) {
        await _setMarker(
          _currentLatitude!,
          _currentLongitude!,
          controller: controller,
          animate: true,
        );
      }
    }();
  }

  Future<void> _onMapClick(math.Point<double> point, LatLng coordinates) async {
    // Only allow pin dropping when pin mode is selected
    if (_selectedMethod != 'pin') {
      return;
    }
    
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      _currentLatitude = coordinates.latitude;
      _currentLongitude = coordinates.longitude;

      final placemarks = await LocationService.getAddressFromLocation(
        coordinates.latitude,
        coordinates.longitude,
      );

      var address = 'Unknown location';
      if (placemarks.isNotEmpty) {
        address = LocationService.formatAddress(placemarks.first);
      }

      _currentAddress = address;
      _addressController.text = address;

      await _updateMarkersOnControllers(
        primary: _mapController,
        animatePrimary: true,
      );

      widget.onLocationSelected(
        coordinates.latitude,
        coordinates.longitude,
        address,
        'pin',
      );

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Pin dropped at: $address')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('Error getting location details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _showPinInstructions = false;
        });
      }
    }
  }

  void _setSelectedMethod(String method, {bool showPinHint = false}) {
    _selectedMethod = method;
    _showPinInstructions = method == 'pin' && showPinHint;
  }

  void _onAddressChanged(String value) {
    _addressDebounce?.cancel();

    final query = value.trim();
    if (query.length < 3) {
      _pendingSuggestionQuery = null;
      if (_addressSuggestions.isNotEmpty) {
        setState(() {
          _addressSuggestions = [];
        });
      }
      return;
    }

    _addressDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchAddressSuggestions(query);
    });
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    _pendingSuggestionQuery = query;
    final suggestions = await LocationService.searchAddressSuggestions(query);

    if (!mounted || _pendingSuggestionQuery != query) {
      return;
    }

    setState(() {
      _addressSuggestions = suggestions;
    });
  }

  void _clearAddressSuggestions({bool dismissKeyboard = false}) {
    _pendingSuggestionQuery = null;
    _addressDebounce?.cancel();

    if (dismissKeyboard) {
      _addressFocusNode.unfocus();
    }

    if (_addressSuggestions.isNotEmpty) {
      setState(() {
        _addressSuggestions = [];
      });
    }
  }

  Future<void> _onSuggestionSelected(LocationSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    _addressDebounce?.cancel();
    _pendingSuggestionQuery = null;

    final addressText = suggestion.displayName;

    setState(() {
      _isLoadingLocation = true;
      _setSelectedMethod('address');
      _addressSuggestions = [];
    });

    _addressController.value = TextEditingValue(
      text: addressText,
      selection: TextSelection.collapsed(offset: addressText.length),
    );

    try {
      _currentLatitude = suggestion.latitude;
      _currentLongitude = suggestion.longitude;
      _currentAddress = addressText;

      await _updateMarkersOnControllers(
        primary: _mapController,
        animatePrimary: true,
      );

      widget.onLocationSelected(
        suggestion.latitude,
        suggestion.longitude,
        addressText,
        'address',
      );

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.place, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Moved to: ${suggestion.primaryText}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('Error selecting address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation({VoidCallback? onStateUpdated}) async {
    setState(() {
      _isLoadingLocation = true;
      _setSelectedMethod('current');
    });
    onStateUpdated?.call();

    try {
      final position = await LocationService.getCurrentLocation();
      if (position == null) {
        if (mounted) {
          setState(() {
            _setSelectedMethod('none');
          });
          onStateUpdated?.call();
          _showSnackBar(
            const SnackBar(
              content: Text('Could not get current location'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      _currentLatitude = position.latitude;
      _currentLongitude = position.longitude;

      final placemarks = await LocationService.getAddressFromLocation(
        position.latitude,
        position.longitude,
      );

      var address = 'Current location';
      if (placemarks.isNotEmpty) {
        address = LocationService.formatAddress(placemarks.first);
      }

      _currentAddress = address;
      _addressController.text = address;

      // Move camera to current location without dropping a pin
      if (_mapController != null) {
        await _mapController!.moveCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            16.0,
          ),
        );
      }
      if (_embeddedMapController != null) {
        await _embeddedMapController!.moveCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            16.0,
          ),
        );
      }

      final controllers = <MapLibreMapController>{
        if (_embeddedMapController != null) _embeddedMapController!,
        if (_mapController != null) _mapController!,
      };

      for (final controller in controllers) {
        await _clearAnnotations(controller);
      }

      _skipNextMarkerRefresh = true;

      widget.onLocationSelected(
        position.latitude,
        position.longitude,
        address,
        'current',
      );

      if (mounted) {
        setState(() {
          _setSelectedMethod('none');
        });
        onStateUpdated?.call();
        _showSnackBar(
          const SnackBar(
            content: Text('Current location obtained'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _setSelectedMethod('none');
        });
        onStateUpdated?.call();
        _showSnackBar(
          SnackBar(
            content: Text('Error getting current location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
        onStateUpdated?.call();
      }
    }
  }

  Future<void> _searchAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _showSnackBar(
        const SnackBar(
          content: Text('Please enter an address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _clearAddressSuggestions(dismissKeyboard: true);

    setState(() {
      _isLoadingLocation = true;
      _setSelectedMethod('address');
    });

    try {
      final locations = await LocationService.getLocationFromAddress(address);
      if (locations.isEmpty) {
        if (mounted) {
          _showSnackBar(
            const SnackBar(
              content: Text('Address not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final location = locations.first;
      _currentLatitude = location.latitude;
      _currentLongitude = location.longitude;
      _currentAddress = address;

      await _updateMarkersOnControllers(
        primary: _mapController,
        animatePrimary: true,
      );

      widget.onLocationSelected(
        location.latitude,
        location.longitude,
        address,
        'address',
      );

      if (mounted) {
        _showSnackBar(
          const SnackBar(
            content: Text('Address found and location set'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text('Error searching address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _openFullScreen() async {
    final previousController = _embeddedMapController;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) {
          return Scaffold(
            body: Builder(
              builder: (scaffoldContext) {
                _scaffoldContext = scaffoldContext;
                return _buildFullScreenMap(scaffoldContext);
              },
            ),
          );
        },
      ),
    );

    _mapController = previousController;
    _scaffoldContext = context;
  }

  void _toggleMapStyle() {
    setState(() {
      _isSatelliteMode = !_isSatelliteMode;
      _controllersWithMarkerImage.clear();
    });
    
    // Force rebuild of current map to apply style change
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildFullScreenMap(BuildContext fullScreenContext) {
    return StatefulBuilder(
      builder: (context, setFullScreenState) {
        return Stack(
          children: [
            MapLibreMap(
              key: ValueKey('fullscreen-${_isSatelliteMode ? 'satellite' : 'standard'}'),
              onMapCreated: _onFullScreenMapCreated,
              onStyleLoadedCallback: _onFullScreenStyleLoaded,
              onMapClick: (point, coordinates) => _onMapClick(point, coordinates),
              initialCameraPosition: const CameraPosition(
                target: LatLng(-21.1789, -175.1982),
                zoom: 10.0,
              ),
              styleString: _getMapStyle(),
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              compassEnabled: true,
              tiltGesturesEnabled: true,
              rotateGesturesEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              doubleClickZoomEnabled: true,
            ),
        // Right side button column
        Positioned(
          top: MediaQuery.of(fullScreenContext).padding.top + 16,
          right: 16,
          child: Column(
            children: [
              // Exit button
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(fullScreenContext).pop(),
                  iconSize: 24,
                ),
              ),
              const SizedBox(height: 12),
              // Pin button
              Container(
                decoration: BoxDecoration(
                  color: _selectedMethod == 'pin'
                      ? Colors.orange.shade600
                      : Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: IconButton(
                  icon: const Icon(Icons.place, color: Colors.white),
                  onPressed: () {
                    final togglingOn = _selectedMethod != 'pin';
                    setState(() {
                      _setSelectedMethod(
                        togglingOn ? 'pin' : 'none',
                        showPinHint: togglingOn,
                      );
                    });
                    setFullScreenState(() {}); // Update full screen UI
                    if (togglingOn) {
                      _showSnackBar(
                        const SnackBar(
                          content: Text('Tap on the map to pin a location'),
                          duration: Duration(seconds: 2),
                        ),
                        contextOverride: fullScreenContext,
                      );
                    }
                  },
                  iconSize: 24,
                ),
              ),
              const SizedBox(height: 12),
              // Current location button
              Container(
                decoration: BoxDecoration(
                  color: _selectedMethod == 'current'
                      ? Colors.green.shade600
                      : Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.white),
                  onPressed: _isLoadingLocation
                      ? null
                      : () => _getCurrentLocation(
                            onStateUpdated: () => setFullScreenState(() {}),
                          ),
                  iconSize: 24,
                ),
              ),
              const SizedBox(height: 12),
              // Satellite toggle
              Container(
                decoration: BoxDecoration(
                  color: _isSatelliteMode
                      ? Colors.blue.shade600
                      : Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: IconButton(
                  icon: Icon(
                    _isSatelliteMode ? Icons.map : Icons.satellite,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSatelliteMode = !_isSatelliteMode;
                      _controllersWithMarkerImage.clear();
                    });
                    setFullScreenState(() {}); // Update full screen UI
                  },
                  iconSize: 24,
                ),
              ),
            ],
          ),
        ),
        if (_selectedMethod == 'pin' && _showPinInstructions)
          Positioned(
            top: MediaQuery.of(fullScreenContext).padding.top + 80,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade600,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.touch_app, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap anywhere on the map to pin location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _showPinInstructions = false;
                      });
                      setFullScreenState(() {});
                    },
                    tooltip: 'Hide pin instructions',
                  ),
                ],
              ),
            ),
          ),
        if (_isLoadingLocation)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    },
  );
}

  Widget _buildNormalView() {
    _scaffoldContext = context;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _openFullScreen,
            icon: const Icon(Icons.fullscreen),
            label: const Text('Full Screen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    focusNode: _addressFocusNode,
                    onChanged: _onAddressChanged,
                    onSubmitted: (_) => _searchAddress(),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Enter address',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 123 Main St, City, Country',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoadingLocation ? null : _searchAddress,
                  icon: const Icon(Icons.search),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (_addressSuggestions.isNotEmpty &&
                (_isAddressFieldFocused || _addressFocusNode.hasFocus))
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade300),
                ),
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _addressSuggestions.length,
                  separatorBuilder: (_, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    final suggestion = _addressSuggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined,
                          color: Colors.redAccent),
                      title: Text(
                        suggestion.primaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: suggestion.secondaryText == null
                          ? null
                          : Text(
                              suggestion.secondaryText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => _onSuggestionSelected(suggestion),
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  MapLibreMap(
                    key: ValueKey('embedded-${_isSatelliteMode ? 'satellite' : 'standard'}'),
                    onMapCreated: _onEmbeddedMapCreated,
                    onStyleLoadedCallback: _onEmbeddedStyleLoaded,
                    onMapClick: (point, coordinates) => _onMapClick(point, coordinates),
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(-21.1789, -175.1982),
                      zoom: 10.0,
                    ),
                    styleString: _getMapStyle(),
                    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                    compassEnabled: true,
                    tiltGesturesEnabled: true,
                    rotateGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    doubleClickZoomEnabled: true,
                  ),
                  // Right side button column
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Column(
                      children: [
                        // Pin button
                        Container(
                          decoration: BoxDecoration(
                            color: _selectedMethod == 'pin'
                                ? Colors.orange.shade600
                                : Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.place, color: Colors.white),
                            onPressed: () {
                              final togglingOn = _selectedMethod != 'pin';
                              setState(() {
                                _setSelectedMethod(
                                  togglingOn ? 'pin' : 'none',
                                  showPinHint: togglingOn,
                                );
                              });
                              if (togglingOn) {
                                _showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Tap on the map to pin a location'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            iconSize: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Current location button
                        Container(
                          decoration: BoxDecoration(
                            color: _selectedMethod == 'current'
                                ? Colors.green.shade600
                                : Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.my_location, color: Colors.white),
                            onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                            iconSize: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Satellite toggle
                        Container(
                          decoration: BoxDecoration(
                            color: _isSatelliteMode
                                ? Colors.blue.shade600
                                : Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: Icon(
                              _isSatelliteMode ? Icons.map : Icons.satellite,
                              color: Colors.white,
                            ),
                            onPressed: _toggleMapStyle,
                            iconSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoadingLocation)
                    Container(
                      color: Colors.black.withValues(alpha: 0.15),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.selectedLatitude != null &&
            widget.selectedLongitude != null)
          Container(
            margin: const EdgeInsets.only(top: 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Location Selected',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Coordinates: ${widget.selectedLatitude!.toStringAsFixed(6)}, '
                  '${widget.selectedLongitude!.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (widget.selectedAddress != null)
                  Text(
                    'Address: ${widget.selectedAddress}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildNormalView();
  }

  String _getMapStyle({bool? satelliteOverride}) {
    final useSatellite = satelliteOverride ?? _isSatelliteMode;
    if (useSatellite) {
      return '''
{
  "version": 8,
  "sources": {
    "satellite": {
      "type": "raster",
      "tiles": ["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],
      "tileSize": 256,
      "attribution": "Esri, Maxar, Earthstar Geographics",
      "maxzoom": 19
    },
    "overlay": {
      "type": "raster",
      "tiles": ["https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}"],
      "tileSize": 256,
      "attribution": "Esri",
      "maxzoom": 19
    }
  },
  "layers": [
    {
      "id": "satellite",
      "type": "raster",
      "source": "satellite"
    },
    {
      "id": "overlay",
      "type": "raster",
      "source": "overlay"
    }
  ]
}
''';
    }

    return '''
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "&copy; OpenStreetMap Contributors",
      "maxzoom": 19
    }
  },
  "layers": [
    {
      "id": "osm",
      "type": "raster",
      "source": "osm"
    }
  ]
}
''';
  }
}