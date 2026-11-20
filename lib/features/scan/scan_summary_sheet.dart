import 'package:flutter/material.dart';

import '../../core/signal/signal_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/signal_pattern.dart';
import '../../domain/path_track.dart';
import '../../domain/scan_session.dart';

enum SummaryOutcome { save, discard }

/// Shown after Finish (S7). Pops with a [SummaryOutcome].
class ScanSummarySheet extends StatelessWidget {
  const ScanSummarySheet({
    super.key,
    required this.session,
    required this.savedSampleCount,
    this.track,
    this.manualSpots,
  });

  /// Spots recorded on the room sketch; null when not a sketch scan.
  final int? manualSpots;

  final ScanSession session;

  /// Samples that will be saved (AR: readings matched to a position).
  final int savedSampleCount;

  /// Walked path when the scan used AR; null for signal-only scans.
  final PathTrack? track;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final counts = session.countsByQuality;
    final total = session.samplesDbm.length;
    final median = session.medianDbm;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scan finished', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${formatDuration(session.recordedMs)} · $total readings'
              '${median == null ? '' : ' · typical ${signalQualityFor(median).label.toLowerCase()}'}',
              style: textTheme.bodyLarge?.copyWith(color: muted),
            ),
            if (track case final track?) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Walked ${track.walkedM.toStringAsFixed(2)} m · ended '
                  '${track.distanceFromStartM.toStringAsFixed(2)} m from the start',
                  style: textTheme.bodyLarge?.copyWith(color: muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$savedSampleCount of $total readings have a position',
                  style: textTheme.bodyLarge?.copyWith(color: muted),
                ),
              ),
            ],
            if (manualSpots case final spots?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  spots == 1
                      ? '1 spot recorded on the sketch'
                      : '$spots spots recorded on the sketch',
                  style: textTheme.bodyLarge?.copyWith(color: muted),
                ),
              ),
            const SizedBox(height: 20),
            for (final quality in SignalQuality.values)
              _QualityBar(
                quality: quality,
                count: counts[quality]!,
                total: total,
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(SummaryOutcome.discard),
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(SummaryOutcome.save),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityBar extends StatelessWidget {
  const _QualityBar({
    required this.quality,
    required this.count,
    required this.total,
  });

  final SignalQuality quality;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : count / total;
    final percent = (share * 100).round();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${quality.label}: $percent percent of readings',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SignalSwatch(quality),
            const SizedBox(width: 10),
            SizedBox(width: 92, child: Text(quality.label)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 10,
                  color: AppColors.forQuality(quality),
                  backgroundColor: scheme.surfaceContainerHigh,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '$percent%',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
