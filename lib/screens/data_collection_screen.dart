import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:intl/intl.dart';
import '../models/data_record.dart';
import '../services/database_service.dart';
import '../widgets/location_picker_maplibre_new.dart';

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key, required this.themeModeNotifier});

  final ValueNotifier<ThemeMode> themeModeNotifier;

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

  void _toggleTheme() {
    final currentMode = widget.themeModeNotifier.value;
    widget.themeModeNotifier.value =
        currentMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
  final cardColor = Theme.of(context).cardTheme.color ??
    Theme.of(context).colorScheme.surface;
    final colorScheme = Theme.of(context).colorScheme;

    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      content.add(children[i]);
      if (i != children.length - 1) {
        content.add(const SizedBox(height: 18));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.7) ??
                    colorScheme.onSurfaceVariant,
                                ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...content,
        ],
      ),
    );
  }

  Widget _buildLocationSummary(ColorScheme colorScheme) {
    final hasLocation =
        _selectedLatitude != null && _selectedLongitude != null;

    if (!hasLocation) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tap on the map or use search to select a precise location.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = colorScheme.primaryContainer.withValues(
      alpha: isDark ? 0.65 : 0.4,
    );
    final onBackground = colorScheme.onPrimaryContainer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place, color: onBackground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedAddress ?? 'Location selected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onBackground,
                      ),
                ),
              ),
              Chip(
                backgroundColor: onBackground.withValues(alpha: 0.16),
                side: BorderSide(color: onBackground.withValues(alpha: 0.3)),
                label: Text(
                  _locationMethod.isNotEmpty
                      ? _locationMethod.toUpperCase()
                      : 'PINNED',
                  style: TextStyle(
                    color: onBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.my_location, size: 18, color: onBackground),
              const SizedBox(width: 8),
              Text(
                '${_selectedLatitude!.toStringAsFixed(5)}, ${_selectedLongitude!.toStringAsFixed(5)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: onBackground.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Data Collection'),
        actions: [
          IconButton(
            tooltip: 'Toggle ${isDark ? 'light' : 'dark'} mode',
            icon: Icon(
              isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: _toggleTheme,
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.95),
                colorScheme.secondary.withValues(alpha: 0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B1220), Color(0xFF111827)]
                : const [Color(0xFFF5F7FB), Color(0xFFE8EEFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: FormBuilder(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionCard(
                    icon: Icons.person_outline,
                    title: 'Personal Information',
                    subtitle: 'Tell us who you are collecting information about.',
                    children: [
                      FormBuilderTextField(
                        name: 'name',
                        decoration: const InputDecoration(
                          labelText: 'Full Name *',
                          hintText: 'e.g. Jane Doe',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.minLength(2),
                        ]),
                      ),
                      FormBuilderDateTimePicker(
                        name: 'date_of_birth',
                        inputType: InputType.date,
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth *',
                          prefixIcon: Icon(Icons.cake_outlined),
                        ),
                        format: DateFormat('yyyy-MM-dd'),
                        validator: FormBuilderValidators.required(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      ),
                      FormBuilderDropdown<String>(
                        name: 'gender',
                        decoration: const InputDecoration(
                          labelText: 'Gender *',
                          prefixIcon: Icon(Icons.people_outline),
                        ),
                        validator: FormBuilderValidators.required(),
                        items: const ['Male', 'Female']
                            .map(
                              (gender) => DropdownMenuItem(
                                value: gender,
                                child: Text(gender),
                              ),
                            )
                            .toList(),
                      ),
                      FormBuilderTextField(
                        name: 'phone_number',
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          hintText: '+676 1234567',
                          prefixIcon: Icon(Icons.call_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.minLength(7),
                        ]),
                      ),
                      FormBuilderTextField(
                        name: 'email',
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.email(),
                        ]),
                      ),
                    ],
                  ),
                  _buildSectionCard(
                    icon: Icons.explore_outlined,
                    title: 'Location Information',
                    subtitle: 'Search, drop a pin, or use your current location.',
                    children: [
                      LocationPicker(
                        onLocationSelected: _onLocationSelected,
                        selectedLatitude: _selectedLatitude,
                        selectedLongitude: _selectedLongitude,
                        selectedAddress: _selectedAddress,
                      ),
                      _buildLocationSummary(colorScheme),
                    ],
                  ),
                  _buildSectionCard(
                    icon: Icons.edit_note_outlined,
                    title: 'Additional Notes',
                    subtitle: 'Capture context, observations, or follow-up items.',
                    children: [
                      FormBuilderTextField(
                        name: 'notes',
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          hintText: 'Add any contextual details...',
                          prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isLoading
                          ? Row(
                              key: const ValueKey('loading'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Saving...'),
                              ],
                            )
                          : Row(
                              key: const ValueKey('save'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.cloud_upload_outlined),
                                SizedBox(width: 12),
                                Text('Save Record'),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text(
                        'Data is stored securely on this device.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}