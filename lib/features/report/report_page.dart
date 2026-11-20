import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../core/signal/signal_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_theme.dart';
import '../../data/scan_repository.dart';
import '../../domain/compare.dart';
import '../../domain/fixes.dart';
import '../../domain/scan_record.dart';
import '../../platform/share_bridge.dart';
import '../common/signal_legend.dart';
import '../compare/compare_page.dart';
import '../fixes/fixes_page.dart';
import '../map/heatmap_view.dart';
import '../map/map_controller.dart';

/// Fixes listed in the report, cheapest first (they are already ranked).
const int reportMaxFixes = 3;

/// The shared image is drawn at this many pixels per logical pixel.
const double reportPixelRatio = 3;

/// File name for a report shared at [at], e.g. sagap-report-20261121-1405.png.
String reportFileName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'sagap-report-${at.year}${two(at.month)}${two(at.day)}-'
      '${two(at.hour)}${two(at.minute)}.png';
}

/// Report preview and share (SPEC.md §9, "shareable report"). The report is
/// an image the user shares through Android's share sheet; Sagap uploads
/// nothing and the image holds no Wi-Fi name or address.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key, required this.item, this.comparison, this.comparedWith});

  final MappableScan item;

  /// Before/after result, when opened from the compare screen.
  final ScanComparison? comparison;

  /// Start time of the "before" scan of [comparison].
  final DateTime? comparedWith;

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final share = ref.read(shareBridgeProvider);
    final now = ref.read(clockProvider)();
    setState(() => _sharing = true);
    try {
      final render = _boundary.currentContext?.findRenderObject();
      if (render is! RenderRepaintBoundary) {
        throw StateError('Report is not on screen yet');
      }
      final image = await render.toImage(pixelRatio: reportPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not encode the report image');
      await share.shareImage(bytes.buffer.asUint8List(), reportFileName(now));
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't share the report: ${e.message}")));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't share the report: ${e.message}")));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixes = ref.watch(fixesProvider(widget.item));
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: switch (fixes) {
        AsyncData(:final value) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RepaintBoundary(
                    key: _boundary,
                    child: Theme(
                      data: AppTheme.light(),
                      child: _ReportCard(
                        item: widget.item,
                        data: value,
                        comparison: widget.comparison,
                        comparedWith: widget.comparedWith,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Share image'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        AsyncError(:final error) => Center(child: Text("Couldn't build the report: $error")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// The report itself, always in the light theme so it reads well anywhere.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.data,
    required this.comparison,
    required this.comparedWith,
  });

  final MappableScan item;
  final FixesData data;
  final ScanComparison? comparison;
  final DateTime? comparedWith;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final map = data.map;
    final median = item.scan.medianDbm;
    final deadArea = homeDeadAreaM2(map.heatmap, map.layout);
    final fixes = data.fixes.take(reportMaxFixes).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.colorScheme.onSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Wi-Fi report', style: textTheme.headlineSmall),
              Text(
                '${item.home.name} · scanned ${formatDateTime(item.scan.startedAt)}',
                style: textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              if (!map.heatmap.isEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(cardRadius / 2),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: HeatmapView(
                      heatmap: map.heatmap,
                      layout: map.layout,
                      noSignalPoints: map.noSignalSpots,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const SignalLegend(),
              const SizedBox(height: 12),
              Text('Summary', style: textTheme.titleMedium),
              Text(
                [
                  if (median != null)
                    'Typically ${signalQualityFor(median).label.toLowerCase()} (${formatDbm(median)})',
                  'Dead-zone area ${deadArea.toStringAsFixed(1)} m²',
                  item.scan.mode == ScanMode.manual
                      ? '${item.scan.sampleCount} spots measured'
                      : '${item.scan.sampleCount} readings',
                  if (map.noSignalSpots.isNotEmpty) '${map.noSignalSpots.length} out of range',
                ].join(' · '),
              ),
              if (comparison case final c?) ...[
                const SizedBox(height: 12),
                Text(
                  comparedWith == null
                      ? 'Before and after'
                      : 'Before and after (compared with ${formatDateTime(comparedWith!)})',
                  style: textTheme.titleMedium,
                ),
                ComparisonSummary(comparison: c),
              ],
              if (fixes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Suggested fixes', style: textTheme.titleMedium),
                for (final (i, fix) in fixes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${i + 1}. ${fix.what} (${tierLabel(fix.tier)} · '
                      '${evidenceLabel(fix.evidence)})\n${fix.where}',
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Made with Sagap on this phone. Sagap measures your Wi-Fi signal '
                'and gives advice; predicted values are marked. This report '
                'contains no Wi-Fi network name or address.',
                style: textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
