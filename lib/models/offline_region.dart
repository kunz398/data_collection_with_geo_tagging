import 'dart:convert';

import 'package:maplibre_gl/maplibre_gl.dart';

enum OfflineRegionStatus { pending, downloading, ready, failed }

extension OfflineRegionStatusParsing on OfflineRegionStatus {
  String get name => switch (this) {
        OfflineRegionStatus.pending => 'pending',
        OfflineRegionStatus.downloading => 'downloading',
        OfflineRegionStatus.ready => 'ready',
        OfflineRegionStatus.failed => 'failed',
      };

  static OfflineRegionStatus fromName(String name) {
    return OfflineRegionStatus.values.firstWhere(
      (element) => element.name == name,
      orElse: () => OfflineRegionStatus.pending,
    );
  }
}

class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.name,
    required this.styleUrl,
    required this.minZoom,
    required this.maxZoom,
    required this.bounds,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.tileCount = 0,
    this.sizeBytes = 0,
    this.lastError,
  });

  final String id;
  final String name;
  final String styleUrl;
  final double minZoom;
  final double maxZoom;
  final LatLngBounds bounds;
  final OfflineRegionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int tileCount;
  final int sizeBytes;
  final String? lastError;

  OfflineRegion copyWith({
    OfflineRegionStatus? status,
    DateTime? updatedAt,
    int? tileCount,
    int? sizeBytes,
    String? lastError,
  }) {
    return OfflineRegion(
      id: id,
      name: name,
      styleUrl: styleUrl,
      minZoom: minZoom,
      maxZoom: maxZoom,
      bounds: bounds,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tileCount: tileCount ?? this.tileCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastError: lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'style_url': styleUrl,
      'min_zoom': minZoom,
      'max_zoom': maxZoom,
      'north': bounds.northeast.latitude,
      'south': bounds.southwest.latitude,
      'east': bounds.northeast.longitude,
      'west': bounds.southwest.longitude,
      'status': status.name,
      'tile_count': tileCount,
      'size_bytes': sizeBytes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_error': lastError,
    };
  }

  factory OfflineRegion.fromMap(Map<String, dynamic> map) {
    return OfflineRegion(
      id: map['id'] as String,
      name: map['name'] as String,
      styleUrl: map['style_url'] as String,
      minZoom: (map['min_zoom'] as num).toDouble(),
      maxZoom: (map['max_zoom'] as num).toDouble(),
      bounds: LatLngBounds(
        southwest: LatLng((map['south'] as num).toDouble(), (map['west'] as num).toDouble()),
        northeast: LatLng((map['north'] as num).toDouble(), (map['east'] as num).toDouble()),
      ),
      status: OfflineRegionStatusParsing.fromName(map['status'] as String),
      tileCount: (map['tile_count'] as num).toInt(),
      sizeBytes: (map['size_bytes'] as num).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastError: map['last_error'] as String?,
    );
  }

  Map<String, dynamic> toMetadata() {
    return {
      'id': id,
      'name': name,
      'bounds': {
        'south': bounds.southwest.latitude,
        'west': bounds.southwest.longitude,
        'north': bounds.northeast.latitude,
        'east': bounds.northeast.longitude,
      },
      'minZoom': minZoom,
      'maxZoom': maxZoom,
    };
  }

  String get metadataJson => jsonEncode(toMetadata());
}
