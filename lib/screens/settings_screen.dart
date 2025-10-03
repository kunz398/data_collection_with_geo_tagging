import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/offline_region.dart' as local;
import '../services/location_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_map_service.dart';
import '../widgets/connectivity_indicator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.themeModeNotifier});

  final ValueNotifier<ThemeMode> themeModeNotifier;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  double _centerLatitude = -21.1789;
  double _centerLongitude = -175.1982;
  double _radiusKm = 5;
  bool _isDownloading = false;
  double _progress = 0;
  StreamSubscription<double>? _progressSub;
  String? _activeDownloadRegionId;
  final Map<String, double> _regionProgress = {};
  final Map<String, StreamSubscription<double>> _regionProgressSubs = {};
  List<local.OfflineRegion> _regions = [];
  OfflineDownloadException? _lastError;
  MapLibreMapController? _embeddedMapController;
  MapLibreMapController? _fullscreenMapController;
  final Set<int> _controllersReady = {};
  final Set<int> _controllersWithMarkerImage = {};
  final Map<int, Symbol> _controllerSymbols = {};
  final Map<int, Fill> _controllerFills = {};
  Uint8List? _markerImageBytes;
  bool _isLoadingLocation = false;
  StateSetter? _fullScreenStateSetter;
  late final ValueNotifier<ConnectivityStatus> _connectivityNotifier;
  late final VoidCallback _connectivityListener;
  String? _offlineStyleOverride;
  String? _offlineRegionId;
  bool _isApplyingOfflineStyle = false;

  @override
  void initState() {
    super.initState();
    _connectivityNotifier = ConnectivityService.instance.statusNotifier;
    _connectivityListener = _handleConnectivityChanged;
    _connectivityNotifier.addListener(_connectivityListener);
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      scheduleMicrotask(() => _maybeApplyOfflineStyle(force: true));
    }
    _fetchRegions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _progressSub?.cancel();
    for (final sub in _regionProgressSubs.values) {
      sub.cancel();
    }
    _regionProgressSubs.clear();
    _regionProgress.clear();
    _connectivityNotifier.removeListener(_connectivityListener);
    _fullScreenStateSetter = null;
    super.dispose();
  }

  Future<void> _fetchRegions() async {
    final regions = await OfflineMapService.instance.fetchRegions();
    if (!mounted) return;
    setState(() {
      _regions = regions;
    });
    _syncDownloadProgressListeners(regions);
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      unawaited(_maybeApplyOfflineStyle(force: true));
    }
  }

  void _syncDownloadProgressListeners(List<local.OfflineRegion> regions) {
    if (!mounted) {
      return;
    }

    final downloadingRegions = regions
        .where((region) => region.status == local.OfflineRegionStatus.downloading)
        .toList();
    final downloadingIds = downloadingRegions.map((region) => region.id).toSet();

    final idsToRemove = _regionProgressSubs.keys
        .where((id) => !downloadingIds.contains(id))
        .toList();

    if (idsToRemove.isNotEmpty) {
      setState(() {
        for (final id in idsToRemove) {
          _regionProgressSubs.remove(id)?.cancel();
          _regionProgress.remove(id);
          if (_activeDownloadRegionId == id) {
            _activeDownloadRegionId = null;
            _progress = 0;
          }
        }
      });
    }

    for (final region in downloadingRegions) {
      if (!_regionProgress.containsKey(region.id)) {
        setState(() {
          _regionProgress[region.id] = 0;
        });
      }

      if (_regionProgressSubs.containsKey(region.id)) {
        continue;
      }

      final stream = OfflineMapService.instance.watchProgress(region.id);
      _regionProgressSubs[region.id] = stream.listen((progress) {
        if (!mounted) return;
        final clamped = progress.clamp(0.0, 1.0);
        setState(() {
          _regionProgress[region.id] = clamped;
          if (_activeDownloadRegionId == null ||
              _activeDownloadRegionId == region.id) {
            _activeDownloadRegionId = region.id;
            _progress = clamped;
            _isDownloading = true;
          }
        });
      }, onError: (_) {
        if (!mounted) return;
        setState(() {
          _regionProgress.remove(region.id);
          _regionProgressSubs.remove(region.id)?.cancel();
          if (_activeDownloadRegionId == region.id) {
            _activeDownloadRegionId = null;
            _progress = 0;
            _isDownloading = _regionProgressSubs.isNotEmpty;
          }
        });
      }, onDone: () {
        if (!mounted) return;
        setState(() {
          _regionProgress.remove(region.id);
          _regionProgressSubs.remove(region.id);
          if (_activeDownloadRegionId == region.id) {
            _activeDownloadRegionId = null;
            _progress = 0;
            _isDownloading = _regionProgressSubs.isNotEmpty;
          }
        });
      });
    }

    final bool hasDownloading = downloadingRegions.isNotEmpty;
    final String? targetActiveId = hasDownloading
        ? (_activeDownloadRegionId != null &&
                downloadingIds.contains(_activeDownloadRegionId!)
            ? _activeDownloadRegionId
            : downloadingRegions.first.id)
        : null;

    if (_activeDownloadRegionId != targetActiveId ||
        _isDownloading != hasDownloading) {
      setState(() {
        _activeDownloadRegionId = targetActiveId;
        _isDownloading = hasDownloading;
        _progress = targetActiveId != null ? (_regionProgress[targetActiveId] ?? 0) : 0;
      });
    }
  }

  LatLngBounds _calculateBounds() {
    final latDelta = _radiusKm / 111.0;
    final latRadians = _centerLatitude * (math.pi / 180);
    final lonDelta = _radiusKm /
        (111.320 * (math.cos(latRadians).abs().clamp(0.01, 1.0)));

    final south = _centerLatitude - latDelta;
    final north = _centerLatitude + latDelta;
    final west = _centerLongitude - lonDelta;
    final east = _centerLongitude + lonDelta;

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _startDownload() async {
    if (_isDownloading) {
      return;
    }

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final bounds = _calculateBounds();

    String? downloadId;

    try {
      setState(() {
        _isDownloading = true;
        _progress = 0;
        _lastError = null;
        _activeDownloadRegionId = null;
      });

      final handle = await OfflineMapService.instance.queueDownload(
        bounds: bounds,
        customName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );

      final regionId = handle.regionId;
      downloadId = regionId;

      setState(() {
        _activeDownloadRegionId = regionId;
        _regionProgress[regionId] = 0;
      });

      unawaited(_fetchRegions());

      _progressSub?.cancel();
      _progressSub = handle.progressStream.listen((progress) {
        if (!mounted) return;
        final clamped = progress.clamp(0.0, 1.0);
        setState(() {
          _progress = clamped;
          _regionProgress[regionId] = clamped;
        });
      }, onError: (error) {
        if (!mounted) return;
        setState(() {
          _lastError = error is OfflineDownloadException
              ? error
              : OfflineDownloadException(error.toString());
          _isDownloading = false;
          _regionProgress.remove(regionId);
          _activeDownloadRegionId = null;
        });
      });

      final result = await handle.completion;
      if (!mounted) return;
      _nameController.clear();
      setState(() {
        _isDownloading = false;
        _progress = 1;
        _regionProgress.remove(regionId);
        _activeDownloadRegionId = null;
      });
      await _fetchRegions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offline region "${result.name}" ready.')),
        );
      }
    } on OfflineDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _lastError = e;
        if (downloadId != null) {
          _regionProgress.remove(downloadId);
        }
        _activeDownloadRegionId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _lastError = OfflineDownloadException(e.toString());
        if (downloadId != null) {
          _regionProgress.remove(downloadId);
        }
        _activeDownloadRegionId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _deleteRegion(local.OfflineRegion region) async {
    await OfflineMapService.instance.deleteRegion(region);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed offline region "${region.name}".')),
    );
    await _fetchRegions();
  }

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    final status = _connectivityNotifier.value;
    if (status == ConnectivityStatus.offline) {
      unawaited(_maybeApplyOfflineStyle(force: true));
    } else if (_offlineStyleOverride != null) {
      setState(() {
        _offlineStyleOverride = null;
        _offlineRegionId = null;
      });
      _controllersWithMarkerImage.clear();
      _controllerSymbols.clear();
      _controllerFills.clear();
      _notifyCircleChanged();
    }
  }

  Future<void> _maybeApplyOfflineStyle({LatLng? focus, bool force = false}) async {
    if (!mounted) {
      return;
    }
    if (_connectivityNotifier.value != ConnectivityStatus.offline && !force) {
      return;
    }
    if (_isApplyingOfflineStyle && !force) {
      return;
    }

  final target = focus ?? LatLng(_centerLatitude, _centerLongitude);

    _isApplyingOfflineStyle = true;
    try {
      var region = await OfflineMapService.instance.findRegionCovering(target);
      String? styleJson;
      String? regionId;
      if (region == null) {
        // Fallback: pick nearest ready region and recentre so tiles are visible
        region = await OfflineMapService.instance.findNearestReadyRegion(target);
      }

      if (region != null) {
        styleJson = await OfflineMapService.instance.resolveOfflineStyle(region);
        regionId = region.id;
      }
      styleJson ??= _buildOfflinePlaceholderStyle();

      if (!mounted) {
        return;
      }

      if (!force &&
          styleJson == _offlineStyleOverride &&
          regionId == _offlineRegionId) {
        return;
      }

      setState(() {
        _offlineStyleOverride = styleJson;
        _offlineRegionId = regionId;
      });
      _controllersWithMarkerImage.clear();
      _controllerSymbols.clear();
      _controllerFills.clear();

      // If we selected a nearest region (or any region), recenter camera inside it so tiles show.
      if (region != null) {
        final centerLat =
            (region.bounds.southwest.latitude + region.bounds.northeast.latitude) / 2.0;
        final centerLng =
            (region.bounds.southwest.longitude + region.bounds.northeast.longitude) / 2.0;
        final center = LatLng(centerLat, centerLng);
        setState(() {
          _centerLatitude = center.latitude;
          _centerLongitude = center.longitude;
        });
        await _refreshControllers(animate: true);
      }
    } finally {
      _isApplyingOfflineStyle = false;
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
      "paint": {
        "background-color": "#1F2937"
      }
    }
  ]
}
''';
  }

  Widget _buildRegionMapCard(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            MapLibreMap(
              key: ValueKey(
                'offline-region-map-${_centerLatitude.toStringAsFixed(4)}-${_centerLongitude.toStringAsFixed(4)}-${_radiusKm.toStringAsFixed(2)}-${_offlineRegionId ?? (_offlineStyleOverride != null ? 'offline' : 'online')}',
              ),
              onMapCreated: (controller) => _onMapCreated(controller, embedded: true),
              onStyleLoadedCallback: _onEmbeddedStyleLoaded,
              onMapClick: (position, coordinates) => _updateCenter(coordinates),
              initialCameraPosition: CameraPosition(
                target: LatLng(_centerLatitude, _centerLongitude),
                zoom: _estimateZoom(),
              ),
              styleString: _getMapStyle(),
              compassEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: false,
              doubleClickZoomEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  _buildMapActionButton(
                    icon: Icons.my_location,
                    tooltip: 'Use current location',
                    onPressed: _isLoadingLocation ? null : _useCurrentLocation,
                  ),
                  const SizedBox(height: 12),
                  _buildMapActionButton(
                    icon: Icons.fullscreen,
                    tooltip: 'Open full-screen map',
                    onPressed: _openFullScreenMap,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tap anywhere on the map to move the center.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinateSummary(ColorScheme colorScheme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildInfoChip(
          icon: Icons.place_outlined,
          label: 'Center',
          value:
              '${_centerLatitude.toStringAsFixed(4)}, ${_centerLongitude.toStringAsFixed(4)}',
          colorScheme: colorScheme,
        ),
        _buildInfoChip(
          icon: Icons.hdr_strong,
          label: 'Radius',
          value: '${_radiusKm.toStringAsFixed(1)} km',
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    final background = colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusControls(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Radius: ${_radiusKm.toStringAsFixed(1)} km'),
        Slider(
          value: _radiusKm,
          min: 1,
          max: 25,
          divisions: 24,
          label: '${_radiusKm.toStringAsFixed(1)} km',
          onChanged: (value) {
            setState(() {
              _radiusKm = value;
            });
            _fullScreenStateSetter?.call(() {});
            _notifyCircleChanged();
          },
        ),
      ],
    );
  }

  Widget _buildMapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: onPressed == null ? 0.25 : 0.65),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(9),
        ),
      ),
    );
  }

  void _notifyCircleChanged({bool animate = false}) {
    unawaited(_refreshControllers(animate: animate));
  }

  void _onMapCreated(MapLibreMapController controller, {required bool embedded}) {
    if (embedded) {
      if (_embeddedMapController != null) {
        final oldId = _embeddedMapController!.hashCode;
        _controllersReady.remove(oldId);
        _controllersWithMarkerImage.remove(oldId);
        _controllerSymbols.remove(oldId);
        _controllerFills.remove(oldId);
      }
      _embeddedMapController = controller;
    } else {
      if (_fullscreenMapController != null) {
        final oldId = _fullscreenMapController!.hashCode;
        _controllersReady.remove(oldId);
        _controllersWithMarkerImage.remove(oldId);
        _controllerSymbols.remove(oldId);
        _controllerFills.remove(oldId);
      }
      _fullscreenMapController = controller;
    }
  }

  void _onEmbeddedStyleLoaded() => _handleStyleLoaded(_embeddedMapController);

  void _onFullScreenStyleLoaded() => _handleStyleLoaded(_fullscreenMapController);

  void _handleStyleLoaded(MapLibreMapController? controller) {
    if (controller == null) return;
    final id = controller.hashCode;
    _controllersReady.add(id);
    _controllersWithMarkerImage.remove(id);
    _controllerSymbols.remove(id);
    _controllerFills.remove(id);
    _notifyCircleChanged(animate: true);
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      unawaited(_maybeApplyOfflineStyle());
    }
  }

  void _updateCenter(LatLng coordinates, {bool animate = true}) {
    setState(() {
      _centerLatitude = coordinates.latitude.clamp(-85.0, 85.0);
      _centerLongitude = coordinates.longitude.clamp(-180.0, 180.0);
    });
    _fullScreenStateSetter?.call(() {});
    _notifyCircleChanged(animate: animate);
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      unawaited(_maybeApplyOfflineStyle(focus: coordinates, force: true));
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;

      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not determine current location.')),
        );
        return;
      }

      _updateCenter(
        LatLng(position.latitude, position.longitude),
        animate: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _refreshControllers({bool animate = false}) async {
    final controllers = <MapLibreMapController>{
      if (_embeddedMapController != null) _embeddedMapController!,
      if (_fullscreenMapController != null) _fullscreenMapController!,
    };

    for (final controller in controllers) {
      await _updateControllerOverlays(controller, animateCamera: animate);
    }
  }

  Future<void> _updateControllerOverlays(
    MapLibreMapController controller, {
    bool animateCamera = false,
  }) async {
    final id = controller.hashCode;
    if (!_controllersReady.contains(id)) {
      return;
    }

    await _ensureMarkerImage(controller);

    final center = LatLng(_centerLatitude, _centerLongitude);

    final existingSymbol = _controllerSymbols[id];
    if (existingSymbol != null) {
      await controller.updateSymbol(
        existingSymbol,
        SymbolOptions(geometry: center),
      );
    } else {
      final symbol = await controller.addSymbol(
        SymbolOptions(
          geometry: center,
          iconImage: 'offline-region-center',
          iconSize: 0.9,
          iconAnchor: 'bottom',
        ),
      );
      _controllerSymbols[id] = symbol;
    }

    final polygon = _generateCirclePolygon(center, _radiusKm, 90);
    final existingFill = _controllerFills[id];
    if (existingFill != null) {
      await controller.updateFill(
        existingFill,
        FillOptions(
          geometry: [polygon],
        ),
      );
    } else {
      final fill = await controller.addFill(
        FillOptions(
          geometry: [polygon],
          fillColor: '#3A7BD5',
          fillOpacity: 0.18,
          fillOutlineColor: '#3A7BD5',
        ),
      );
      _controllerFills[id] = fill;
    }

    if (animateCamera) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: center, zoom: _estimateZoom()),
        ),
      );
    }
  }

  Future<void> _ensureMarkerImage(MapLibreMapController controller) async {
    final id = controller.hashCode;
    if (_controllersWithMarkerImage.contains(id)) {
      return;
    }

    final bytes = await _getMarkerImageBytes();
    try {
      await controller.addImage('offline-region-center', bytes);
    } catch (_) {
      // Image may already exist on this controller instance.
    }
    _controllersWithMarkerImage.add(id);
  }

  Future<Uint8List> _getMarkerImageBytes() async {
    if (_markerImageBytes != null) {
      return _markerImageBytes!;
    }
    _markerImageBytes = await _createMarkerImageBytes();
    return _markerImageBytes!;
  }

  Future<Uint8List> _createMarkerImageBytes() async {
    const double size = 96;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.place.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: Icons.place.fontFamily,
        package: Icons.place.fontPackage,
        color: const Color(0xFF3A7BD5),
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

  List<LatLng> _generateCirclePolygon(LatLng center, double radiusKm, int segments) {
    const earthRadiusKm = 6371.0;
    final lat = center.latitude * (math.pi / 180);
    final lon = center.longitude * (math.pi / 180);
    final angularDistance = radiusKm / earthRadiusKm;

    final points = <LatLng>[];
    for (var i = 0; i <= segments; i++) {
      final bearing = 2 * math.pi * (i / segments);

      final sinLat = math.sin(lat);
      final cosLat = math.cos(lat);
      final sinAngular = math.sin(angularDistance);
      final cosAngular = math.cos(angularDistance);

      final pointLat = math.asin(
        sinLat * cosAngular + cosLat * sinAngular * math.cos(bearing),
      );

      final pointLon = lon + math.atan2(
        math.sin(bearing) * sinAngular * cosLat,
        cosAngular - sinLat * math.sin(pointLat),
      );

      final normalizedLon = (pointLon + math.pi) % (2 * math.pi) - math.pi;

      points.add(
        LatLng(pointLat * (180 / math.pi), normalizedLon * (180 / math.pi)),
      );
    }
    return points;
  }

  double _estimateZoom() {
    final zoom = 14 - math.log(_radiusKm) / math.ln2;
    return zoom.clamp(6, 16);
  }

  String _getMapStyle() {
    if (_connectivityNotifier.value == ConnectivityStatus.offline) {
      return _offlineStyleOverride ?? _buildOfflinePlaceholderStyle();
    }

    return '''
{
  "version": 8,
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors",
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

  Future<void> _openFullScreenMap() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              _fullScreenStateSetter = setModalState;
              return Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  children: [
                    MapLibreMap(
                      key: ValueKey(
                        'offline-region-full-${_centerLatitude.toStringAsFixed(4)}-${_centerLongitude.toStringAsFixed(4)}-${_radiusKm.toStringAsFixed(2)}-${_offlineRegionId ?? (_offlineStyleOverride != null ? 'offline' : 'online')}',
                      ),
                      onMapCreated: (controller) => _onMapCreated(controller, embedded: false),
                      onStyleLoadedCallback: _onFullScreenStyleLoaded,
                      onMapClick: (position, coordinates) => _updateCenter(coordinates),
                      styleString: _getMapStyle(),
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_centerLatitude, _centerLongitude),
                        zoom: _estimateZoom(),
                      ),
                      compassEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      zoomGesturesEnabled: true,
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                        iconSize: 28,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.7),
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      right: 16,
                      child: Column(
                        children: [
                          _buildMapActionButton(
                            icon: Icons.my_location,
                            tooltip: 'Use current location',
                            onPressed: _isLoadingLocation ? null : _useCurrentLocation,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 32,
                      child: Card(
                        color: Colors.black.withValues(alpha: 0.6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Radius: ${_radiusKm.toStringAsFixed(1)} km',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              Slider(
                                value: _radiusKm,
                                min: 1,
                                max: 25,
                                divisions: 24,
                                label: '${_radiusKm.toStringAsFixed(1)} km',
                                onChanged: (value) {
                                  setState(() {
                                    _radiusKm = value;
                                  });
                                  setModalState(() {});
                                  _notifyCircleChanged();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );

    if (_fullscreenMapController != null) {
      final id = _fullscreenMapController!.hashCode;
      _controllersReady.remove(id);
      _controllersWithMarkerImage.remove(id);
      _controllerSymbols.remove(id);
      _controllerFills.remove(id);
    }

    _fullScreenStateSetter = null;
    _fullscreenMapController = null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const ConnectivityIndicator(),
            ],
          ),
          const SizedBox(height: 24),
          _buildThemeCard(context, colorScheme),
          const SizedBox(height: 24),
          _buildOfflineSection(colorScheme),
        ],
      ),
    );
  }

  Widget _buildThemeCard(BuildContext context, ColorScheme colorScheme) {
    return Card.filled(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ],
                    selected: <ThemeMode>{widget.themeModeNotifier.value},
                    onSelectionChanged: (selection) {
                      widget.themeModeNotifier.value = selection.first;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineSection(ColorScheme colorScheme) {
    return Card.filled(
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline maps',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Select an area to download raster tiles for offline use.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            _buildRegionMapCard(colorScheme),
            const SizedBox(height: 12),
            _buildCoordinateSummary(colorScheme),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Region name (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRadiusControls(colorScheme),
                  if (_lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lastError!.message,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isDownloading ? null : _startDownload,
                    icon: const Icon(Icons.download),
                    label: Text(
                      _isDownloading
                          ? 'Downloading ${(100 * _progress).clamp(0, 100).toStringAsFixed(0)}%'
                          : 'Download for offline use',
                    ),
                  ),
                  if (_isDownloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress.clamp(0, 1)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Saved regions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (_regions.isEmpty)
              Text(
                'No offline regions yet. Download an area to use the map without an internet connection.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              )
            else
              Column(
                children: _regions.map((region) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(region.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Zoom ${region.minZoom.toStringAsFixed(0)} - ${region.maxZoom.toStringAsFixed(0)}'),
                          Text(
                            'Tiles: ${region.tileCount} | ${(region.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                          ),
                          Builder(
                            builder: (context) {
                              String statusLabel = region.status.name;
                              final progressValue = _regionProgress[region.id] ??
                                  (region.id == _activeDownloadRegionId ? _progress : null);
                              if (region.status == local.OfflineRegionStatus.downloading &&
                                  progressValue != null) {
                                final percent = (progressValue.clamp(0.0, 1.0) * 100)
                                    .clamp(0, 100)
                                    .toStringAsFixed(0);
                                statusLabel = '${region.status.name} – $percent%';
                              }
                              return Text('Status: $statusLabel');
                            },
                          ),
                          if (region.lastError != null)
                            Text(
                              region.lastError!,
                              style: TextStyle(color: colorScheme.error),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteRegion(region),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
