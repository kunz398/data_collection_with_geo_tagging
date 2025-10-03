import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

class ConnectivityIndicator extends StatelessWidget {
  const ConnectivityIndicator({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<ConnectivityStatus>(
      valueListenable: ConnectivityService.instance.statusNotifier,
      builder: (context, status, _) {
        final tooltip = switch (status) {
          ConnectivityStatus.online => 'Online',
          ConnectivityStatus.offline => 'Offline',
          ConnectivityStatus.unknown => 'Checking connection…',
        };

        final indicatorColor = switch (status) {
          ConnectivityStatus.online => Colors.green,
          ConnectivityStatus.offline => Colors.grey,
          ConnectivityStatus.unknown => colorScheme.outlineVariant,
        };

        final background = colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);

        return Tooltip(
          message: tooltip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: compact
                ? const EdgeInsets.all(6)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: indicatorColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    tooltip,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
