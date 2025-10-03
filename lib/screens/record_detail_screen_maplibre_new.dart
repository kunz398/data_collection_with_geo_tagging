import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/data_record.dart';
import '../services/connectivity_service.dart';
import '../services/offline_map_service.dart';

class RecordDetailScreenMapLibre extends StatefulWidget {
  final DataRecord record;

  const RecordDetailScreenMapLibre({super.key, required this.record});

  @override
  State<RecordDetailScreenMapLibre> createState() => _RecordDetailScreenMapLibreState();
}

class _RecordDetailScreenMapLibreState extends State<RecordDetailScreenMapLibre> {
  MapLibreMapController? mapController;
  Symbol? _markerSymbol;
  Uint8List? _markerImageBytes;
  Color? _markerColor;
  bool _isSatelliteMode = false;
  final ValueNotifier<ConnectivityStatus> _connectivityNotifier =
      ConnectivityService.instance.statusNotifier;
  late final VoidCallback _connectivityListener;
  String? _offlineStyleOverride;
  String? _offlineRegionId;
  String? _offlineRegionName;
  bool _isApplyingOfflineStyle = false;

  @override
  void initState() {
    super.initState();
    _connectivityListener = () {
      final status = _connectivityNotifier.value;
      if (status == ConnectivityStatus.offline) {
        _maybeUpdateOfflineStyle();
      } else {
        setState(() {
          _offlineStyleOverride = null;
          _offlineRegionId = null;
          _offlineRegionName = null;
          _markerSymbol = null;
          _markerImageBytes = null;
        });
      }
    };
    _connectivityNotifier.addListener(_connectivityListener);

    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeUpdateOfflineStyle();
      });
    }
  }

  @override
  void dispose() {
    _connectivityNotifier.removeListener(_connectivityListener);
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    _addMarker();
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      _maybeUpdateOfflineStyle();
    }
  }

  Future<Uint8List> _createMarkerImageBytes(Color color) async {
  const double size = 96;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.location_on.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: Icons.location_on.fontFamily,
        package: Icons.location_on.fontPackage,
        color: color,
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

  Future<Uint8List> _getMarkerImageBytes(Color color) async {
    if (_markerImageBytes != null && _markerColor == color) {
      return _markerImageBytes!;
    }
    _markerImageBytes = await _createMarkerImageBytes(color);
    _markerColor = color;
    return _markerImageBytes!;
  }

  Future<void> _ensureMarkerImage(MapLibreMapController controller) async {
    final color = Theme.of(context).colorScheme.primary;
    final bytes = await _getMarkerImageBytes(color);
    try {
      await controller.addImage('detail-marker', bytes);
    } catch (_) {
      // Image may already exist for this controller/style.
    }
  }

  Future<void> _addMarker() async {
    final controller = mapController;
    if (controller == null) {
      return;
    }

    await _ensureMarkerImage(controller);

    if (_markerSymbol != null) {
      try {
        await controller.removeSymbol(_markerSymbol!);
      } catch (_) {
        // Ignore if removal fails (e.g., symbol already cleared)
      }
      _markerSymbol = null;
    }

    try {
      _markerSymbol = await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(widget.record.latitude, widget.record.longitude),
          iconImage: 'detail-marker',
          iconSize: 1.2,
          iconAnchor: 'bottom',
        ),
      );
    } catch (_) {
      // Swallow symbol errors to avoid crashing detail view.
    }
  }

  void _onStyleLoaded() {
    _markerSymbol = null;
    _addMarker();
  }

  Future<void> _maybeUpdateOfflineStyle({bool? satelliteOverride}) async {
    if (!mounted) {
      return;
    }
    if (_connectivityNotifier.value != ConnectivityStatus.offline) {
      return;
    }
    if (_isApplyingOfflineStyle) {
      return;
    }

    final target = LatLng(widget.record.latitude, widget.record.longitude);
    var region = await OfflineMapService.instance.findRegionCovering(target);
    String? styleJson;
    String? regionId;
    if (region == null) {
      region = await OfflineMapService.instance.findNearestReadyRegion(target);
    }
    if (region != null) {
      final useSatellite = satelliteOverride ?? _isSatelliteMode;
      styleJson = await OfflineMapService.instance.resolveOfflineStyle(
        region,
        variant: useSatellite
            ? OfflineMapVariant.satellite
            : OfflineMapVariant.standard,
      );
      regionId = region.id;
    }
    styleJson ??= _buildOfflinePlaceholderStyle();

    if (_offlineStyleOverride == styleJson && _offlineRegionId == regionId) {
      return;
    }

    _isApplyingOfflineStyle = true;
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _offlineStyleOverride = styleJson;
        _offlineRegionId = regionId;
        _offlineRegionName = region?.name;
        _markerSymbol = null;
        _markerImageBytes = null;
      });

      // Recenter the camera into the region if we had to fall back.
      if (region != null) {
        final centerLat =
            (region.bounds.southwest.latitude + region.bounds.northeast.latitude) / 2.0;
        final centerLng =
            (region.bounds.southwest.longitude + region.bounds.northeast.longitude) / 2.0;
        await mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(centerLat, centerLng), zoom: 12.0),
          ),
        );
      }
    } finally {
      _isApplyingOfflineStyle = false;
    }
  }

  void _toggleMapStyle() {
    setState(() {
      _isSatelliteMode = !_isSatelliteMode;
    });
    // If offline, re-resolve offline style with the chosen variant
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      _maybeUpdateOfflineStyle(satelliteOverride: _isSatelliteMode);
    }
  }

  String _buildOfflinePlaceholderStyle() {
    return '''
{
  "version": 8,
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "#1F2937"}
    }
  ]
}
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Personal Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal Information',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Name', widget.record.name),
                    _buildInfoRow('Date of Birth', 
                        DateFormat('MMMM dd, yyyy').format(widget.record.dateOfBirth)),
                    _buildInfoRow('Gender', widget.record.gender),
                    _buildInfoRow('Phone Number', widget.record.phoneNumber),
                    _buildInfoRow('Email', widget.record.email),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Location Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location Information',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
          _buildInfoRow('Address', widget.record.address.isNotEmpty
            ? widget.record.address
            : '—'),
          _buildCoordinateRow(),
                    const SizedBox(height: 16),
                    
                    // Map View
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            MapLibreMap(
                              key: ValueKey(
                                'detail-${_isSatelliteMode ? 'satellite' : 'standard'}-${_offlineRegionId ?? (_offlineStyleOverride != null ? 'offline' : 'online')}',
                              ),
                              onMapCreated: _onMapCreated,
                              onStyleLoadedCallback: _onStyleLoaded,
                              initialCameraPosition: CameraPosition(
                                target: LatLng(widget.record.latitude, widget.record.longitude),
                                zoom: 15.0,
                              ),
                              styleString: _getMapStyle(),
                            ),
                            // Offline region chip (top-left) when offline style active
                            if (_offlineRegionId != null && _offlineRegionName != null)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.offline_pin, size: 16, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Offline region: ${_offlineRegionName!}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Satellite toggle (top-right)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
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
                                  tooltip: _isSatelliteMode ? 'Switch to standard' : 'Switch to satellite',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Additional Information Card
            if (widget.record.notes.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Additional Notes',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.record.notes,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Metadata Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record Information',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Record ID', widget.record.id.toString()),
                    _buildInfoRow('Created At', 
                        DateFormat('MMMM dd, yyyy HH:mm:ss').format(widget.record.createdAt)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateRow() {
    final coords =
        '${widget.record.latitude.toStringAsFixed(6)}, ${widget.record.longitude.toStringAsFixed(6)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 120,
            child: Text(
              'Coordinates:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    coords,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMapStyle() {
    if (_connectivityNotifier.value == ConnectivityStatus.offline &&
        _offlineStyleOverride != null) {
      return _offlineStyleOverride!;
    }
    // Online styles: satellite or standard
    if (_isSatelliteMode) {
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
    { "id": "satellite", "type": "raster", "source": "satellite" },
    { "id": "overlay", "type": "raster", "source": "overlay" }
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