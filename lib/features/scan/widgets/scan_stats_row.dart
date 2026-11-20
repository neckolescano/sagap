import 'package:flutter/material.dart';

import '../../../core/signal/signal_format.dart';
import '../../../core/signal/signal_quality.dart';
import '../../../domain/scan_session.dart';

/// Time · Readings · Weakest for the current scan.
class ScanStatsRow extends StatelessWidget {
  const ScanStatsRow({super.key, required this.session});

  final ScanSession session;

  @override
  Widget build(BuildContext context) {
    final weakest = session.weakestDbm;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            _Stat(label: 'Time', value: formatDuration(session.recordedMs)),
            const _Divider(),
            _Stat(label: 'Readings', value: '${session.samplesDbm.length}'),
            const _Divider(),
            _Stat(
              label: 'Weakest',
              value: weakest == null ? '—' : signalQualityFor(weakest).label,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          children: [
            FittedBox(
              child: Text(
                value,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );
}
