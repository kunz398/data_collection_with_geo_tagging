import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:math' as math;
import '../services/location_service.dart';

class LocationPicker extends StatefulWidget {
  final Function(double latitude, double longitude, String address, String method) onLocationSelected;
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
  bool _isLoadingLocation = false;
  String _selectedMethod = 'none';

  @override
  void initState() {
    super.initState();
    if (widget.selectedAddress != null) {
      _addressController.text = widget.selectedAddress!;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    if (widget.selectedLatitude != null && widget.selectedLongitude != null) {
      _addMarker(widget.selectedLatitude!, widget.selectedLongitude!);
    }
  }

  void _onMapClick(math.Point<double> point, LatLng coordinates) async {
    setState(() {
      _isLoadingLocation = true;
      _selectedMethod = 'pin';
    });

    try {
      // Clear existing symbols
      if (_mapController != null) {
        await _mapController!.clearSymbols();
      }

      // Add new marker
      _addMarker(coordinates.latitude, coordinates.longitude);

      // Get address from coordinates
      final placemarks = await LocationService.getAddressFromLocation(
        coordinates.latitude,
        coordinates.longitude,
      );

      String address = 'Unknown location';
      if (placemarks.isNotEmpty) {
        address = LocationService.formatAddress(placemarks.first);
      }

      _addressController.text = address;

      widget.onLocationSelected(
        coordinates.latitude,
        coordinates.longitude,
        address,
        'pin',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location details: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _addMarker(double latitude, double longitude) {
    if (_mapController != null) {
      _mapController!.addSymbol(
        SymbolOptions(
          geometry: LatLng(latitude, longitude),
          iconImage: 'marker-15',
          iconSize: 2.0,
        ),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _selectedMethod = 'current';
    });

    try {
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        // Clear existing symbols
        if (_mapController != null) {
          await _mapController!.clearSymbols();
          await _mapController!.moveCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              15.0,
            ),
          );
        }

        // Add marker
        _addMarker(position.latitude, position.longitude);

        // Get address
        final placemarks = await LocationService.getAddressFromLocation(
          position.latitude,
          position.longitude,
        );

        String address = 'Current location';
        if (placemarks.isNotEmpty) {
          address = LocationService.formatAddress(placemarks.first);
        }

        _addressController.text = address;

        widget.onLocationSelected(
          position.latitude,
          position.longitude,
          address,
          'current',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Current location obtained'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get current location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting current location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _searchAddress() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoadingLocation = true;
      _selectedMethod = 'address';
    });

    try {
      final locations = await LocationService.getLocationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;

        // Clear existing symbols
        if (_mapController != null) {
          await _mapController!.clearSymbols();
          await _mapController!.moveCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(location.latitude, location.longitude),
              15.0,
            ),
          );
        }

        // Add marker
        _addMarker(location.latitude, location.longitude);

        widget.onLocationSelected(
          location.latitude,
          location.longitude,
          address,
          'address',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address found and location set'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location selection buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Current'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedMethod == 'current' 
                      ? Theme.of(context).colorScheme.primary 
                      : null,
                  foregroundColor: _selectedMethod == 'current' 
                      ? Colors.white 
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMethod = 'pin';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tap on the map to pin a location'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.place),
                label: const Text('Pin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedMethod == 'pin' 
                      ? Theme.of(context).colorScheme.primary 
                      : null,
                  foregroundColor: _selectedMethod == 'pin' 
                      ? Colors.white 
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Address search
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Enter address',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., 123 Main St, City, Country',
                ),
                onSubmitted: (_) => _searchAddress(),
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
        const SizedBox(height: 16),

        // Map
        Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                MapLibreMap(
                  onMapCreated: _onMapCreated,
                  onMapClick: _onMapClick,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(-21.1789, -175.1982), // Tonga coordinates
                    zoom: 10.0,
                  ),
                  styleString: _getMapStyle(),
                ),
                if (_isLoadingLocation)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Selected location info
        if (widget.selectedLatitude != null && widget.selectedLongitude != null)
          Container(
            margin: const EdgeInsets.only(top: 16),
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
                  'Coordinates: ${widget.selectedLatitude!.toStringAsFixed(6)}, ${widget.selectedLongitude!.toStringAsFixed(6)}',
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

  String _getMapStyle() {
    // Using OpenStreetMap style for MapLibre
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