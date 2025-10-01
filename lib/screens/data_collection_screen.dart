import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:intl/intl.dart';
import '../models/data_record.dart';
import '../services/database_service.dart';
import '../widgets/location_picker_maplibre_new.dart';

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key});

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isLoading = false;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedAddress;
  String _locationMethod = '';

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      if (_selectedLatitude == null || _selectedLongitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a location'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final formData = _formKey.currentState!.value;
        
        final record = DataRecord(
          name: formData['name'],
          dateOfBirth: formData['date_of_birth'],
          gender: formData['gender'],
          phoneNumber: formData['phone_number'],
          email: formData['email'],
          address: _selectedAddress ?? '',
          latitude: _selectedLatitude!,
          longitude: _selectedLongitude!,
          locationMethod: _locationMethod,
          notes: formData['notes'] ?? '',
          createdAt: DateTime.now(),
        );

        await DatabaseService.instance.insertRecord(record);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Record saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _formKey.currentState!.reset();
          setState(() {
            _selectedLatitude = null;
            _selectedLongitude = null;
            _selectedAddress = null;
            _locationMethod = '';
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving record: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onLocationSelected(double latitude, double longitude, String address, String method) {
    setState(() {
      _selectedLatitude = latitude;
      _selectedLongitude = longitude;
      _selectedAddress = address;
      _locationMethod = method;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Collection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: FormBuilder(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Personal Information Section
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
                      FormBuilderTextField(
                        name: 'name',
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          border: OutlineInputBorder(),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.minLength(2),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      FormBuilderDateTimePicker(
                        name: 'date_of_birth',
                        inputType: InputType.date,
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth *',
                          border: OutlineInputBorder(),
                        ),
                        format: DateFormat('yyyy-MM-dd'),
                        validator: FormBuilderValidators.required(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      ),
                      const SizedBox(height: 16),
                      FormBuilderDropdown<String>(
                        name: 'gender',
                        decoration: const InputDecoration(
                          labelText: 'Gender *',
                          border: OutlineInputBorder(),
                        ),
                        validator: FormBuilderValidators.required(),
                        items: ['Male', 'Female']
                            .map((gender) => DropdownMenuItem(
                                  value: gender,
                                  child: Text(gender),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      FormBuilderTextField(
                        name: 'phone_number',
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          border: OutlineInputBorder(),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.minLength(7),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      FormBuilderTextField(
                        name: 'email',
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          border: OutlineInputBorder(),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.email(),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Location Section
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
                      LocationPicker(
                        onLocationSelected: _onLocationSelected,
                        selectedLatitude: _selectedLatitude,
                        selectedLongitude: _selectedLongitude,
                        selectedAddress: _selectedAddress,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Additional Notes Section
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
                      FormBuilderTextField(
                        name: 'notes',
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Submit Button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text(
                        'Save Record',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}