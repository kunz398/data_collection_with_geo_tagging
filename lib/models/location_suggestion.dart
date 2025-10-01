class LocationSuggestion {
  final String displayName;
  final String primaryText;
  final String? secondaryText;
  final double latitude;
  final double longitude;

  LocationSuggestion({
    required this.displayName,
    required this.primaryText,
    required this.latitude,
    required this.longitude,
    this.secondaryText,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    final displayName = (json['display_name'] as String?)?.trim() ?? '';
    final parts = displayName
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final primary = parts.isNotEmpty ? parts.first : displayName;
    final secondary = parts.length > 1 ? parts.sublist(1).join(', ') : null;

    final lat = double.tryParse(json['lat']?.toString() ?? '') ?? 0;
    final lon = double.tryParse(json['lon']?.toString() ?? '') ?? 0;

    return LocationSuggestion(
      displayName: displayName,
      primaryText: primary,
      secondaryText: secondary,
      latitude: lat,
      longitude: lon,
    );
  }
}
