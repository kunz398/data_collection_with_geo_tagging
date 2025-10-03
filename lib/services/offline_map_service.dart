import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/offline_region.dart' as local;
import 'connectivity_service.dart';
import 'database_service.dart';
import 'foreground_service_manager.dart';

const int _kMaxTileBudget = 2000;
const int _kMaxRetryAttempts = 30;

const Duration _kTileRequestTimeout = Duration(seconds: 12);
const Duration _kInitialRetryDelay = Duration(seconds: 2);
const Duration _kMaxRetryDelay = Duration(seconds: 30);

enum OfflineMapVariant { standard, satellite }

const _DownloadLayerConfig _standardLayerConfig = _DownloadLayerConfig(
  directoryName: 'standard',
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  fileExtension: 'png',
);

const _DownloadLayerConfig _satelliteImageryConfig = _DownloadLayerConfig(
  directoryName: 'satellite',
  urlTemplate:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  fileExtension: 'jpg',
);

const _DownloadLayerConfig _satelliteOverlayConfig = _DownloadLayerConfig(
  directoryName: 'overlay',
  urlTemplate:
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
  fileExtension: 'png',
);

class OfflineMapService {
  OfflineMapService._();

  static final OfflineMapService instance = OfflineMapService._();

  final _database = DatabaseService.instance;
  Directory? _offlineRoot;
  final _progressControllers = <String, StreamController<double>>{};
  final _activeIsolates = <String, _IsolateLifecycle>{};

  Future<Directory> _ensureRoot() async {
    if (_offlineRoot != null) {
      return _offlineRoot!;
    }
    final dir = await getApplicationSupportDirectory();
    final offlineRoot = Directory(p.join(dir.path, 'offline_maps'));
    if (!await offlineRoot.exists()) {
      await offlineRoot.create(recursive: true);
    }
    _offlineRoot = offlineRoot;
    return offlineRoot;
  }

  Future<List<local.OfflineRegion>> fetchRegions() async {
    final raw = await _database.getOfflineRegionsRaw();
    return raw.map(local.OfflineRegion.fromMap).toList();
  }

  Stream<double> watchProgress(String regionId) {
    return _progressControllers.putIfAbsent(
      regionId,
      () => StreamController<double>.broadcast(),
    ).stream;
  }

  Future<void> deleteRegion(local.OfflineRegion region) async {
    _cancelActiveIsolate(region.id);
    final root = await _ensureRoot();
    final regionDir = Directory(p.join(root.path, region.id));
    if (await regionDir.exists()) {
      await regionDir.delete(recursive: true);
    }
    await _database.deleteOfflineRegion(region.id);
  }

  Future<OfflineDownloadHandle> queueDownload({
    required LatLngBounds bounds,
    double? minZoom,
    double? maxZoom,
    String? customName,
    String styleUrl = 'https://tile.openstreetmap.org',
  }) async {
    final range = _determineZoomRange(
      bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );

    final connectivity = ConnectivityService.instance.statusNotifier.value;
    if (connectivity == ConnectivityStatus.offline) {
      throw const OfflineDownloadException('No internet connection available.');
    }

    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final name = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : 'Region ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final region = local.OfflineRegion(
      id: id,
      name: name,
      styleUrl: styleUrl,
    minZoom: range.minZoom,
    maxZoom: range.maxZoom,
      bounds: bounds,
  status: local.OfflineRegionStatus.downloading,
      tileCount: 0,
      sizeBytes: 0,
      createdAt: now,
      updatedAt: now,
    );

    await _database.upsertOfflineRegion(region.toMap());

    final normalizedStyleUrl = styleUrl.endsWith('/') ? styleUrl.substring(0, styleUrl.length - 1) : styleUrl;
    final standardTemplate = '$normalizedStyleUrl/{z}/{x}/{y}.png';

    final layers = <_DownloadLayerConfig>[
      _standardLayerConfig.copyWith(urlTemplate: standardTemplate),
      _satelliteImageryConfig,
      _satelliteOverlayConfig,
    ];

    final controller = _progressControllers.putIfAbsent(
      region.id,
      () => StreamController<double>.broadcast(),
    );
    controller.add(0);

    final completer = Completer<local.OfflineRegion>();

    // Ensure a foreground service notification shows progress while app is backgrounded.
    // Start with 0%.
    unawaited(ForegroundServiceManager.instance.startOrUpdate(
      title: 'Downloading offline map…',
      text: '${region.name} – 0%',
    ));

    _startDownloadIsolate(
      region,
      controller,
      completer,
      layers,
    );

    return OfflineDownloadHandle(
      initialRegion: region,
      progressStream: controller.stream,
      completion: completer.future,
    );
  }

  Future<void> _startDownloadIsolate(
    local.OfflineRegion region,
    StreamController<double> controller,
    Completer<local.OfflineRegion> completer,
    List<_DownloadLayerConfig> layers,
  ) async {
    final root = await _ensureRoot();

    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    final params = _DownloadIsolateParams(
      sendPort: receivePort.sendPort,
      regionId: region.id,
      rootPath: root.path,
      minZoom: region.minZoom,
      maxZoom: region.maxZoom,
      south: region.bounds.southwest.latitude,
      west: region.bounds.southwest.longitude,
      north: region.bounds.northeast.latitude,
      east: region.bounds.northeast.longitude,
      layers: layers,
    );

    final isolate = await Isolate.spawn<_DownloadIsolateParams>(
      _offlineDownloadEntry,
      params,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    late final StreamSubscription<dynamic> receiveSub;
    late final StreamSubscription<dynamic> errorSub;
    late final StreamSubscription<dynamic> exitSub;

    Future<void> cleanup() async {
      final lifecycle = _activeIsolates.remove(region.id);
      if (lifecycle != null) {
        lifecycle.dispose();
        return;
      }

      await receiveSub.cancel();
      await errorSub.cancel();
      await exitSub.cancel();
      receivePort.close();
      errorPort.close();
      exitPort.close();
      isolate.kill(priority: Isolate.immediate);
    }

  bool handledCompletion = false;
  double lastProgress = 0;
  bool waitingForNetwork = false;

    Future<void> handleFailure(Object error, [StackTrace? stackTrace]) async {
      if (handledCompletion) {
        return;
      }
      handledCompletion = true;
      final exception = error is OfflineDownloadException
          ? error
          : OfflineDownloadException(error.toString());
      final failedRegion = region.copyWith(
        status: local.OfflineRegionStatus.failed,
        updatedAt: DateTime.now(),
        lastError: exception.message,
      );
      await _database.upsertOfflineRegion(failedRegion.toMap());
      controller.addError(exception, stackTrace);
      if (!completer.isCompleted) {
        completer.completeError(exception, stackTrace);
      }
      await cleanup();
    }

  receiveSub = receivePort.listen((dynamic message) async {
      if (message is! Map<Object?, Object?>) {
        return;
      }

      final type = message['type'] as String?;
      switch (type) {
        case 'progress':
          final progress = (message['value'] as num).toDouble().clamp(0.0, 1.0);
          lastProgress = progress;
          controller.add(progress);
          final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
          unawaited(ForegroundServiceManager.instance.startOrUpdate(
            title: 'Downloading offline map…',
            text: '${region.name} – $pct%',
          ));
          if (waitingForNetwork) {
            waitingForNetwork = false;
            await _database.updateOfflineRegionStatus(
              region.id,
              {
                'last_error': null,
                'updated_at': DateTime.now().toIso8601String(),
              },
            );
          }
          break;
        case 'network-wait':
          final delayMs = (message['delayMs'] as num?)?.toInt() ?? 0;
          final reason = message['reason'] as String? ?? 'Network issue';
          final delaySeconds = (delayMs / 1000).clamp(1, 600).ceil();
          waitingForNetwork = true;
          await _database.updateOfflineRegionStatus(
            region.id,
            {
              'last_error': '$reason – retrying in ${delaySeconds}s',
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
          if (lastProgress > 0) {
            controller.add(lastProgress);
          }
          final pct = (lastProgress * 100).clamp(0, 100).toStringAsFixed(0);
          unawaited(ForegroundServiceManager.instance.startOrUpdate(
            title: 'Waiting for network…',
            text: '${region.name} – $pct%',
          ));
          break;
        case 'complete':
          if (handledCompletion) {
            break;
          }
          handledCompletion = true;
          final tileCount = (message['tileCount'] as num).toInt();
          final totalBytes = (message['totalBytes'] as num).toInt();
          final readyRegion = region.copyWith(
            status: local.OfflineRegionStatus.ready,
            tileCount: tileCount,
            sizeBytes: totalBytes,
            updatedAt: DateTime.now(),
            lastError: null,
          );
          await _database.upsertOfflineRegion(readyRegion.toMap());
          controller.add(1);
          unawaited(ForegroundServiceManager.instance.stopIfRunning());
          if (!completer.isCompleted) {
            completer.complete(readyRegion);
          }
          await cleanup();
          break;
        case 'error':
          final messageText = message['message'] as String? ?? 'Download failed';
          unawaited(ForegroundServiceManager.instance.stopIfRunning());
          await handleFailure(OfflineDownloadException(messageText));
          break;
      }
    });

  errorSub = errorPort.listen((dynamic errorData) async {
      Object error;
      StackTrace? stackTrace;
      if (errorData is List && errorData.length >= 2) {
        error = errorData[0] ?? 'Unknown isolate error';
        final stackString = errorData[1]?.toString();
        if (stackString != null) {
          stackTrace = StackTrace.fromString(stackString);
        }
      } else {
        error = errorData ?? 'Unknown isolate error';
      }
      unawaited(ForegroundServiceManager.instance.stopIfRunning());
      await handleFailure(error, stackTrace);
    });

  exitSub = exitPort.listen((_) async {
      if (!handledCompletion) {
        unawaited(ForegroundServiceManager.instance.stopIfRunning());
        await handleFailure(const OfflineDownloadException('Download stopped unexpectedly.'));
      }
    });

    final lifecycle = _IsolateLifecycle(
      isolate: isolate,
      receivePort: receivePort,
      errorPort: errorPort,
      exitPort: exitPort,
      receiveSub: receiveSub,
      errorSub: errorSub,
      exitSub: exitSub,
    );

    _activeIsolates[region.id] = lifecycle;
  }

  _ZoomRange _determineZoomRange(
    LatLngBounds bounds, {
    double? minZoom,
    double? maxZoom,
  }) {
    if (minZoom != null && maxZoom != null) {
      if (maxZoom < minZoom) {
        throw ArgumentError('maxZoom must be greater than or equal to minZoom');
      }
      final tiles = _calculateTileCountForBounds(
        bounds,
        minZoom.floor(),
        maxZoom.ceil(),
      );
      if (tiles > _kMaxTileBudget) {
        throw const OfflineDownloadException(
          'Selected region is too large. Please reduce the radius and try again.',
        );
      }
      return _ZoomRange(minZoom: minZoom, maxZoom: maxZoom, estimatedTiles: tiles);
    }

    var candidateMax = ((maxZoom ?? 17).clamp(6, 19)).toDouble();
    var candidateMin = ((minZoom ?? (candidateMax - 5)).clamp(0, candidateMax)).toDouble();

    while (candidateMax >= 5) {
      final minInt = candidateMin.floor();
      final maxInt = candidateMax.ceil();
      final tiles = _calculateTileCountForBounds(bounds, minInt, maxInt);
      if (tiles <= _kMaxTileBudget) {
        final boosted = _boostZoomRange(bounds, candidateMin, candidateMax, tiles);
        return boosted;
      }

      candidateMax = ((candidateMax - 1).clamp(5, 19)).toDouble();
      candidateMin = max(0, candidateMax - 5).toDouble();
    }

    throw const OfflineDownloadException(
      'Selected region is too large. Try a smaller radius.',
    );
  }

  _ZoomRange _boostZoomRange(
    LatLngBounds bounds,
    double baseMin,
    double baseMax,
    int currentTiles,
  ) {
    var boostedMin = baseMin;
    var boostedMax = baseMax;
    var boostedTiles = currentTiles;

    while (boostedMax < 19) {
      final nextMax = min(boostedMax + 1, 19.0);
      final nextMin = max(boostedMin, nextMax - 5.0);
      final nextTiles = _calculateTileCountForBounds(
        bounds,
        nextMin.floor(),
        nextMax.ceil(),
      );

      if (nextTiles > _kMaxTileBudget) {
        break;
      }

      boostedMax = nextMax;
      boostedMin = nextMin;
      boostedTiles = nextTiles;
    }

    return _ZoomRange(
      minZoom: boostedMin,
      maxZoom: boostedMax,
      estimatedTiles: boostedTiles,
    );
  }

  Future<String?> resolveOfflineStyle(
    local.OfflineRegion region, {
    OfflineMapVariant variant = OfflineMapVariant.standard,
  }) async {
    final root = await _ensureRoot();
    final regionDirPath = p.join(root.path, region.id);

    String? styleRelativePath;

    final manifestFile = File(p.join(regionDirPath, 'styles_manifest.json'));
    if (await manifestFile.exists()) {
      try {
        final manifestJson = jsonDecode(await manifestFile.readAsString());
        if (manifestJson is Map<String, dynamic>) {
          final variants = manifestJson['variants'];
          if (variants is Map) {
            final selectedEntry = variants[variant.name];
            final selectedPath = _extractStylePathFromManifestEntry(selectedEntry);
            if (selectedPath != null) {
              styleRelativePath = selectedPath;
            }

            if (styleRelativePath == null) {
              final defaultVariant = manifestJson['defaultVariant'];
              if (defaultVariant is String) {
                final fallbackEntry = variants[defaultVariant];
                styleRelativePath = _extractStylePathFromManifestEntry(fallbackEntry);
              }
            }
          }
        }
      } catch (_) {
        // Ignore manifest parsing errors and fallback to default style detection.
      }
    }

    styleRelativePath ??= variant == OfflineMapVariant.satellite
        ? 'style_satellite.json'
        : 'style.json';

    final primaryFile = File(p.join(regionDirPath, styleRelativePath));
    if (await primaryFile.exists()) {
      return primaryFile.readAsString();
    }

    final fallbackFile = File(p.join(regionDirPath, 'style.json'));
    if (await fallbackFile.exists()) {
      return fallbackFile.readAsString();
    }

    // As a fallback, generate the style JSON dynamically from current tiles on disk.
    final tilesRootPath = p.join(regionDirPath, 'tiles');
    if (variant == OfflineMapVariant.satellite) {
      return _buildOfflineSatelliteStyle(tilesRootPath, region.minZoom, region.maxZoom);
    }
    return _buildOfflineStandardStyle(tilesRootPath, region.minZoom, region.maxZoom);
  }

  Future<local.OfflineRegion?> findRegionCovering(LatLng target, {double? zoom}) async {
    final regions = await fetchRegions();
    for (final region in regions) {
      if (region.status != local.OfflineRegionStatus.ready) {
        continue;
      }
      if (zoom != null && (zoom < region.minZoom || zoom > region.maxZoom)) {
        continue;
      }
      if (_boundsContains(region.bounds, target)) {
        return region;
      }
    }
    return null;
  }

  Future<local.OfflineRegion?> findNearestReadyRegion(LatLng from) async {
    final regions = await fetchRegions();
    local.OfflineRegion? best;
    double bestDist = double.infinity;
    for (final region in regions) {
      if (region.status != local.OfflineRegionStatus.ready) continue;
      final centerLat = (region.bounds.southwest.latitude + region.bounds.northeast.latitude) / 2.0;
      final centerLng = (region.bounds.southwest.longitude + region.bounds.northeast.longitude) / 2.0;
      final dLat = centerLat - from.latitude;
      final dLng = centerLng - from.longitude;
      final dist2 = dLat * dLat + dLng * dLng;
      if (dist2 < bestDist) {
        bestDist = dist2;
        best = region;
      }
    }
    return best;
  }

  void dispose() {
    for (final lifecycle in _activeIsolates.values) {
      lifecycle.dispose();
    }
    _activeIsolates.clear();
    for (final controller in _progressControllers.values) {
      controller.close();
    }
  }

  void _cancelActiveIsolate(String regionId) {
    final lifecycle = _activeIsolates.remove(regionId);
    lifecycle?.dispose();
  }
}

bool _boundsContains(LatLngBounds bounds, LatLng target) {
  final withinLat = target.latitude >= bounds.southwest.latitude &&
      target.latitude <= bounds.northeast.latitude;
  final withinLng = target.longitude >= bounds.southwest.longitude &&
      target.longitude <= bounds.northeast.longitude;
  return withinLat && withinLng;
}

class OfflineDownloadException implements Exception {
  const OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _TileRange {
  const _TileRange({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
}

class _ZoomRange {
  const _ZoomRange({
    required this.minZoom,
    required this.maxZoom,
    required this.estimatedTiles,
  });

  final double minZoom;
  final double maxZoom;
  final int estimatedTiles;
}

class OfflineDownloadHandle {
  const OfflineDownloadHandle({
    required this.initialRegion,
    required this.progressStream,
    required this.completion,
  });

  final local.OfflineRegion initialRegion;
  final Stream<double> progressStream;
  final Future<local.OfflineRegion> completion;

  String get regionId => initialRegion.id;
}

class _DownloadLayerConfig {
  const _DownloadLayerConfig({
    required this.directoryName,
    required this.urlTemplate,
    required this.fileExtension,
  });

  final String directoryName;
  final String urlTemplate;
  final String fileExtension;

  _DownloadLayerConfig copyWith({
    String? directoryName,
    String? urlTemplate,
    String? fileExtension,
  }) {
    return _DownloadLayerConfig(
      directoryName: directoryName ?? this.directoryName,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      fileExtension: fileExtension ?? this.fileExtension,
    );
  }
}

class _IsolateLifecycle {
  _IsolateLifecycle({
    required this.isolate,
    required this.receivePort,
    required this.errorPort,
    required this.exitPort,
    required this.receiveSub,
    required this.errorSub,
    required this.exitSub,
  });

  final Isolate isolate;
  final ReceivePort receivePort;
  final ReceivePort errorPort;
  final ReceivePort exitPort;
  final StreamSubscription<dynamic> receiveSub;
  final StreamSubscription<dynamic> errorSub;
  final StreamSubscription<dynamic> exitSub;

  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    receiveSub.cancel();
    errorSub.cancel();
    exitSub.cancel();
    receivePort.close();
    errorPort.close();
    exitPort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

class _DownloadIsolateParams {
  _DownloadIsolateParams({
    required this.sendPort,
    required this.regionId,
    required this.rootPath,
    required this.minZoom,
    required this.maxZoom,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.layers,
  });

  final SendPort sendPort;
  final String regionId;
  final String rootPath;
  final double minZoom;
  final double maxZoom;
  final double south;
  final double west;
  final double north;
  final double east;
  final List<_DownloadLayerConfig> layers;

  LatLngBounds get bounds => LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      );
}

Future<void> _offlineDownloadEntry(_DownloadIsolateParams params) async {
  final sendPort = params.sendPort;

  try {
    final bounds = params.bounds;
    final minZoomInt = params.minZoom.floor();
    final maxZoomInt = params.maxZoom.ceil();
    final totalTiles = _calculateTileCountForBounds(bounds, minZoomInt, maxZoomInt);

    if (totalTiles > _kMaxTileBudget) {
      sendPort.send({
        'type': 'error',
        'message': 'Selected region is too large. Please reduce the radius and try again.',
      });
      return;
    }

    final layers = params.layers;
    if (layers.isEmpty) {
      sendPort.send({
        'type': 'error',
        'message': 'No tile layers configured for offline download.',
      });
      return;
    }

    final safeTotalTiles = max(totalTiles, 1);
    final totalTileEntries = safeTotalTiles * layers.length;

    final regionDir = Directory(p.join(params.rootPath, params.regionId));
    if (!await regionDir.exists()) {
      await regionDir.create(recursive: true);
    }
    final tileDir = Directory(p.join(regionDir.path, 'tiles'));
    if (!await tileDir.exists()) {
      await tileDir.create(recursive: true);
    }

    int downloadedTiles = 0;
    int totalBytes = 0;

    final client = http.Client();
    try {
      for (final layer in layers) {
        final layerDir = Directory(p.join(tileDir.path, layer.directoryName));
        if (!await layerDir.exists()) {
          await layerDir.create(recursive: true);
        }

        for (var zoom = minZoomInt; zoom <= maxZoomInt; zoom++) {
          final range = _computeTileRange(bounds, zoom);
          for (var x = range.minX; x <= range.maxX; x++) {
            for (var y = range.minY; y <= range.maxY; y++) {
              final tilePath = p.join(
                layerDir.path,
                '$zoom',
                '$x',
                '$y.${layer.fileExtension}',
              );
              final tileFile = File(tilePath);
              if (await tileFile.exists()) {
                downloadedTiles++;
                totalBytes += await tileFile.length();
                sendPort.send({
                  'type': 'progress',
                  'value': downloadedTiles / totalTileEntries,
                });
                continue;
              }

              final url = _buildTileUrl(layer.urlTemplate, zoom, x, y);
              Uint8List tileBytes;
              try {
                tileBytes = await _downloadTileWithRetry(url, client, sendPort);
              } on OfflineDownloadException catch (e) {
                sendPort.send({
                  'type': 'error',
                  'message': e.message,
                });
                return;
              } catch (error) {
                sendPort.send({
                  'type': 'error',
                  'message': 'Failed to download tile ($zoom/$x/$y): $error',
                });
                return;
              }

              await tileFile.create(recursive: true);
              await tileFile.writeAsBytes(tileBytes);
              downloadedTiles++;
              totalBytes += tileBytes.length;
              sendPort.send({
                'type': 'progress',
                'value': downloadedTiles / totalTileEntries,
              });
            }
          }
        }
      }
    } finally {
      client.close();
    }

    await _writeOfflineStyles(
      regionDir.path,
      params.minZoom,
      params.maxZoom,
    );

    sendPort.send({
      'type': 'complete',
      'tileCount': downloadedTiles,
      'totalBytes': totalBytes,
    });
  } catch (error) {
    sendPort.send({
      'type': 'error',
      'message': error.toString(),
    });
  }
}

String _buildTileUrl(String template, int zoom, int x, int y) {
  final tmsY = (1 << zoom) - 1 - y;
  return template
      .replaceAll('{z}', '$zoom')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{-y}', '$tmsY');
}

Future<Uint8List> _downloadTileWithRetry(
  String url,
  http.Client client,
  SendPort progressPort,
) async {
  Object? lastError;
  Duration currentDelay = _kInitialRetryDelay;

  for (var attempt = 1; attempt <= _kMaxRetryAttempts; attempt++) {
    try {
      final response = await client
          .get(Uri.parse(url))
          .timeout(_kTileRequestTimeout);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      final status = response.statusCode;
      final message = 'HTTP $status while fetching tile $url';
      lastError = OfflineDownloadException(message);

      final shouldRetry = status == 408 ||
          status == 425 ||
          status == 429 ||
          status == 500 ||
          status == 502 ||
          status == 503 ||
          status == 504;

      if (shouldRetry && attempt < _kMaxRetryAttempts) {
        await _delayForRetry(progressPort, attempt, currentDelay, message, url);
        currentDelay = _nextDelay(currentDelay);
        continue;
      }

      throw lastError;
    } on TimeoutException catch (e) {
      lastError = e;
      await _delayForRetry(
        progressPort,
        attempt,
        currentDelay,
        'Request timed out',
        url,
      );
      currentDelay = _nextDelay(currentDelay);
      continue;
    } on SocketException catch (e) {
      lastError = e;
      await _delayForRetry(
        progressPort,
        attempt,
        currentDelay,
        'Network unreachable',
        url,
      );
      currentDelay = _nextDelay(currentDelay);
      continue;
    } on http.ClientException catch (e) {
      lastError = e;
      await _delayForRetry(
        progressPort,
        attempt,
        currentDelay,
        'Network error',
        url,
      );
      currentDelay = _nextDelay(currentDelay);
      continue;
    }
  }

  if (lastError is OfflineDownloadException) {
    throw lastError;
  }

  throw OfflineDownloadException(
    'Network error fetching tile $url: $lastError',
  );
}

Future<void> _delayForRetry(
  SendPort progressPort,
  int attempt,
  Duration delay,
  String reason,
  String url,
) async {
  progressPort.send({
    'type': 'network-wait',
    'attempt': attempt,
    'delayMs': delay.inMilliseconds,
    'reason': reason,
    'url': url,
  });
  await Future.delayed(delay);
}

Duration _nextDelay(Duration current) {
  final doubled = Duration(milliseconds: current.inMilliseconds * 2);
  if (doubled > _kMaxRetryDelay) {
    return _kMaxRetryDelay;
  }
  return doubled;
}

Future<void> _writeOfflineStyles(
  String regionDirPath,
  double minZoom,
  double maxZoom,
) async {
  final tilesRootPath = p.join(regionDirPath, 'tiles');
  final standardStylePath = p.join(regionDirPath, 'style.json');
  final satelliteStylePath = p.join(regionDirPath, 'style_satellite.json');
  final manifestPath = p.join(regionDirPath, 'styles_manifest.json');

  final standardStyle = _buildOfflineStandardStyle(tilesRootPath, minZoom, maxZoom);
  final satelliteStyle = _buildOfflineSatelliteStyle(tilesRootPath, minZoom, maxZoom);

  await File(standardStylePath).writeAsString(standardStyle, flush: true);
  await File(satelliteStylePath).writeAsString(satelliteStyle, flush: true);

  final manifest = {
    'defaultVariant': OfflineMapVariant.standard.name,
    'variants': {
      OfflineMapVariant.standard.name: {
        'label': 'Standard',
        'style': 'style.json',
      },
      OfflineMapVariant.satellite.name: {
        'label': 'Satellite',
        'style': 'style_satellite.json',
      },
    },
  };

  await File(manifestPath).writeAsString(jsonEncode(manifest), flush: true);
}

String _buildOfflineStandardStyle(String tilesRootPath, double minZoom, double maxZoom) {
  final standardTilesPath =
      p.join(tilesRootPath, _standardLayerConfig.directoryName).replaceAll('\\', '/');
  // Build a proper file URL base (file:///...), then append tile template.
  final baseUri = Uri.file(standardTilesPath, windows: false).toString();
  final template = '$baseUri/{z}/{x}/{y}.${_standardLayerConfig.fileExtension}';

  final style = {
    'version': 8,
    'name': 'Offline Standard',
    'sources': {
      'offline-standard': {
        'type': 'raster',
        'tiles': [template],
        'tileSize': 256,
        'minzoom': 0,
        'maxzoom': 22,
        'scheme': 'xyz',
        'attribution': '© OpenStreetMap contributors',
      },
    },
    'layers': [
      {
        'id': 'offline-standard',
        'type': 'raster',
        'source': 'offline-standard',
      },
    ],
  };

  return jsonEncode(style);
}

String _buildOfflineSatelliteStyle(String tilesRootPath, double minZoom, double maxZoom) {
  final imageryPath =
    p.join(tilesRootPath, _satelliteImageryConfig.directoryName).replaceAll('\\', '/');
  final overlayPath =
    p.join(tilesRootPath, _satelliteOverlayConfig.directoryName).replaceAll('\\', '/');

  final imageryBase = Uri.file(imageryPath, windows: false).toString();
  final overlayBase = Uri.file(overlayPath, windows: false).toString();
  final imageryTemplate =
    '$imageryBase/{z}/{x}/{y}.${_satelliteImageryConfig.fileExtension}';
  final overlayTemplate =
    '$overlayBase/{z}/{x}/{y}.${_satelliteOverlayConfig.fileExtension}';

  final style = {
    'version': 8,
    'name': 'Offline Satellite',
    'sources': {
      'offline-satellite': {
        'type': 'raster',
        'tiles': [imageryTemplate],
        'tileSize': 256,
        'minzoom': 0,
        'maxzoom': 22,
        'scheme': 'xyz',
        'attribution': 'Esri — World Imagery',
      },
      'offline-satellite-overlay': {
        'type': 'raster',
        'tiles': [overlayTemplate],
        'tileSize': 256,
        'minzoom': 0,
        'maxzoom': 22,
        'scheme': 'xyz',
        'attribution': 'Esri — World Boundaries and Places',
      },
    },
    'layers': [
      {
        'id': 'offline-satellite',
        'type': 'raster',
        'source': 'offline-satellite',
      },
      {
        'id': 'offline-satellite-overlay',
        'type': 'raster',
        'source': 'offline-satellite-overlay',
        'paint': {
          'raster-opacity': 1.0,
        },
      },
    ],
  };

  return jsonEncode(style);
}

String? _extractStylePathFromManifestEntry(Object? entry) {
  if (entry is String && entry.isNotEmpty) {
    return entry;
  }
  if (entry is Map && entry['style'] is String) {
    final stylePath = entry['style'] as String;
    if (stylePath.isNotEmpty) {
      return stylePath;
    }
  }
  return null;
}

int _calculateTileCountForBounds(LatLngBounds bounds, int minZoom, int maxZoom) {
  int total = 0;
  for (var zoom = minZoom; zoom <= maxZoom; zoom++) {
    final range = _computeTileRange(bounds, zoom);
    total += (range.maxX - range.minX + 1) * (range.maxY - range.minY + 1);
  }
  return total;
}

_TileRange _computeTileRange(LatLngBounds bounds, int zoom) {
  final sw = bounds.southwest;
  final ne = bounds.northeast;

  final minX = _lonToTileX(sw.longitude, zoom);
  final maxX = _lonToTileX(ne.longitude, zoom);
  final minY = _latToTileY(ne.latitude, zoom);
  final maxY = _latToTileY(sw.latitude, zoom);

  return _TileRange(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

int _lonToTileX(double lon, int zoom) {
  final scale = 1 << zoom;
  return ((lon + 180.0) / 360.0 * scale).floor();
}

int _latToTileY(double lat, int zoom) {
  final scale = 1 << zoom;
  final latRad = lat * pi / 180.0;
  return ((1 - log(tan(latRad) + 1 / cos(latRad)) / pi) / 2 * scale).floor();
}

