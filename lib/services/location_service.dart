import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../models/location_suggestion.dart';

class LocationService {
  static Future<bool> checkLocationPermission() async {
    final permission = await Permission.location.status;
    
    if (permission.isDenied) {
      final result = await Permission.location.request();
      return result.isGranted;
    }
    
    return permission.isGranted;
  }

  static Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        throw Exception('Location permission denied');
      }

      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        throw Exception('Location services are disabled');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return position;
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  static Future<List<Location>> getLocationFromAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      return locations;
    } catch (e) {
      print('Error geocoding address: $e');
      return [];
    }
  }

  static Future<List<LocationSuggestion>> searchAddressSuggestions(
    String query,
  ) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [];
    }

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': trimmedQuery,
          'format': 'json',
          'addressdetails': '1',
          'limit': '6',
        },
      );

      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'spc_bes_1/1.0 (Nominatim API usage)',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        return [];
      }

      final dynamic decoded = json.decode(response.body);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(LocationSuggestion.fromJson)
          .where((suggestion) => suggestion.displayName.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      print('Error fetching suggestions: $e');
      return [];
    }
  }

  static Future<List<Placemark>> getAddressFromLocation(
      double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      return placemarks;
    } catch (e) {
      print('Error reverse geocoding: $e');
      return [];
    }
  }

  static String formatAddress(Placemark placemark) {
    final components = [
      placemark.street,
      placemark.locality,
      placemark.administrativeArea,
      placemark.country,
    ].where((component) => component != null && component.isNotEmpty);
    
    return components.join(', ');
  }
}