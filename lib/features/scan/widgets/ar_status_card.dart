import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/ar_readiness.dart';
import '../../../platform/ar_bridge.dart';
import '../ar_controller.dart';

/// AR support status before a scan (SPEC.md §10 steps 1–4).
class ArStatusCard extends ConsumerStatefulWidget {
  const ArStatusCard({super.key});

  @override
  ConsumerState<ArStatusCard> createState() => _ArStatusCardState();
}

class _ArStatusCardState extends ConsumerState<ArStatusCard> {
  bool _installRequested = false;

  Future<void> _install() async {
    final result = await ref.read(arReadinessProvider.notifier).install();
    if (!mounted) return;
    setState(() => _installRequested = result == ArInstallResult.requested);
    if (result == ArInstallResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AR install was cancelled or failed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(arReadinessProvider);
    final notifier = ref.read(arReadinessProvider.notifier);

    return switch (readiness) {
      AsyncLoading() => const _StatusTile(
          icon: Icons.view_in_ar_outlined,
          title: 'Checking AR support…',
          message: 'AR tracks where you walk so the map can be drawn.',
        ),
      AsyncError() => _StatusTile(
          icon: Icons.error_outline,
          title: "Couldn't check AR support",
          message: 'You can still record signal.',
          action: TextButton(onPressed: notifier.recheck, child: const Text('Check again')),
        ),
      AsyncData(:final value) => switch (value) {
          ArReadiness.ready => const _StatusTile(
              icon: Icons.view_in_ar,
              title: 'AR ready',
              message: 'Your walk will be tracked with the camera.',
              highlight: true,
            ),
          ArReadiness.needsInstall => _StatusTile(
              icon: Icons.download_outlined,
              title: _installRequested ? 'Finish the install' : 'AR needs one more app',
              message: _installRequested
                  ? 'Install Google Play Services for AR, then come back and check again.'
                  : 'Install Google Play Services for AR to track your walk.',
              action: _installRequested
                  ? TextButton(onPressed: notifier.recheck, child: const Text('Check again'))
                  : TextButton(onPressed: _install, child: const Text('Install')),
            ),
          ArReadiness.unsupported => const _StatusTile(
              icon: Icons.info_outline,
              title: "This phone doesn't support AR",
              message: 'Sagap records your signal without position tracking. '
                  'Room sketching is coming.',
            ),
          ArReadiness.unknown => _StatusTile(
              icon: Icons.help_outline,
              title: "Couldn't check AR support",
              message: 'You can still record signal.',
              action: TextButton(onPressed: notifier.recheck, child: const Text('Check again')),
            ),
        },
    };
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(icon, color: highlight ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
