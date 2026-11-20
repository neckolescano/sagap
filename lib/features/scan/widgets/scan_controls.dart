import 'package:flutter/material.dart';

import '../../../domain/scan_session.dart';

/// One-handed Start / Pause / Resume / Finish, pinned to the bottom.
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.status,
    required this.canStart,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final ScanStatus status;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ScanStatus.idle || ScanStatus.finished => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canStart ? onStart : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('Start scan'),
          ),
        ),
      ScanStatus.recording => Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPause,
                icon: const Icon(Icons.pause_rounded, size: 28),
                label: const Text('Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.check_rounded, size: 28),
                label: const Text('Finish'),
              ),
            ),
          ],
        ),
      ScanStatus.paused => Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: const Text('Resume'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: onFinish,
                icon: const Icon(Icons.check_rounded, size: 28),
                label: const Text('Finish'),
              ),
            ),
          ],
        ),
    };
  }
}
