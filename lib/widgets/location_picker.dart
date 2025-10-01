import 'package:flutter/material.dart';
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

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _selectedMethod = 'current';
    });

    try {
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
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

  void _setManualCoordinates() {
    showDialog(
      context: context,
      builder: (context) {
        final latController = TextEditingController();
        final lngController = TextEditingController();
        
        return AlertDialog(
          title: const Text('Enter Coordinates'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latController,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'e.g., -21.1789',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: lngController,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'e.g., -175.1982',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final lat = double.tryParse(latController.text);
                final lng = double.tryParse(lngController.text);
                
                if (lat != null && lng != null) {
                  widget.onLocationSelected(
                    lat,
                    lng,
                    'Manual coordinates: $lat, $lng',
                    'pin',
                  );
                  setState(() {
                    _selectedMethod = 'pin';
                    _addressController.text = 'Manual coordinates: $lat, $lng';
                  });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coordinates set successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter valid numbers'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
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
                onPressed: _isLoadingLocation ? null : _setManualCoordinates,
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

        // Placeholder for map (will add MapLibre later)
        Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade100,
          ),
          child: Stack(
            children: [
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'Map will be displayed here',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Text(
                      '(MapLibre integration pending)',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
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
}