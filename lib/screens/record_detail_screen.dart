import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/data_record.dart';

class RecordDetailScreen extends StatefulWidget {
  final DataRecord record;

  const RecordDetailScreen({super.key, required this.record});

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
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
                    _buildInfoRow('Address', widget.record.address),
                    _buildInfoRow('Coordinates', 
                        '${widget.record.latitude.toStringAsFixed(6)}, ${widget.record.longitude.toStringAsFixed(6)}'),
                    _buildInfoRow('Location Method', _getLocationMethodText()),
                    const SizedBox(height: 16),
                    
                    // Map Placeholder
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.grey.shade100,
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'Location Map',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '(MapLibre integration pending)',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
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

  String _getLocationMethodText() {
    switch (widget.record.locationMethod) {
      case 'current':
        return 'Current Location';
      case 'pin':
        return 'Pin on Map';
      case 'address':
        return 'Address Search';
      default:
        return widget.record.locationMethod;
    }
  }
}