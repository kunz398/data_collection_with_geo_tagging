import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/data_record.dart';
import '../services/database_service.dart';
import 'data_collection_screen.dart';
import 'record_detail_screen_maplibre_new.dart';

class RecordsListScreen extends StatefulWidget {
  const RecordsListScreen({super.key, required this.themeModeNotifier});

  final ValueNotifier<ThemeMode> themeModeNotifier;

  @override
  State<RecordsListScreen> createState() => _RecordsListScreenState();
}

class _RecordsListScreenState extends State<RecordsListScreen> {
  List<DataRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  void _toggleTheme() {
    final currentMode = widget.themeModeNotifier.value;
    widget.themeModeNotifier.value =
        currentMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final records = await DatabaseService.instance.getAllRecords();
      setState(() {
        _records = records;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteRecord(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseService.instance.deleteRecord(id);
        _loadRecords();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Record deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting record: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 120,
              width: 120,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(36),
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No records yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Start collecting insights in the Collect tab. Saved entries will appear here for quick review.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.color
            ?.withValues(alpha: 0.72),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DataCollectionScreen(
                      themeModeNotifier: widget.themeModeNotifier,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Collect a new record'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(DataRecord record, ColorScheme colorScheme) {
    final initials = record.name.isNotEmpty
        ? record.name
            .trim()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0])
            .take(2)
            .join()
            .toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RecordDetailScreenMapLibre(record: record),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Recorded ${DateFormat('MMM dd, yyyy – HH:mm').format(record.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => RecordDetailScreenMapLibre(record: record),
                          ),
                        );
                      } else if (value == 'delete') {
                        _deleteRecord(record.id!);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined),
                            SizedBox(width: 8),
                            Text('View details'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildInfoLine(
                label: 'DOB',
                value: DateFormat('yyyy-MM-dd').format(record.dateOfBirth),
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 12),
              _buildInfoLine(
                label: 'Location',
                value: record.address.isNotEmpty
                    ? record.address
                    : '${record.latitude.toStringAsFixed(5)}, ${record.longitude.toStringAsFixed(5)}',
                colorScheme: colorScheme,
                maxLines: 2,
              ),
              if (record.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoLine(
                  label: 'Notes',
                  value: record.notes,
                  colorScheme: colorScheme,
                  maxLines: 3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoLine({
    required String label,
    required String value,
    required ColorScheme colorScheme,
    int maxLines = 2,
  }) {
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: labelStyle),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: valueStyle,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Collected Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh records',
            onPressed: _loadRecords,
          ),
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
                ? const [Color(0xFF0B1220), Color(0xFF101827)]
                : const [Color(0xFFF4F7FD), Color(0xFFE4EBFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _records.isEmpty
                  ? _buildEmptyState(colorScheme)
                  : RefreshIndicator(
                      onRefresh: _loadRecords,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                        itemCount: _records.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 18),
                        itemBuilder: (context, index) => _buildRecordTile(
                          _records[index],
                          colorScheme,
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}