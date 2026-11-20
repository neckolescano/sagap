import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../core/signal/signal_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/signal_pattern.dart';
import '../../domain/heatmap.dart';
import '../../domain/path_track.dart';
import '../common/empty_state.dart';
import '../common/signal_legend.dart';
import '../fixes/fixes_page.dart';
import 'heatmap_view.dart';
import 'map_controller.dart';

/// Map tab (S8): heatmap of a saved AR or sketch scan.
class MapPage extends ConsumerWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scans = ref.watch(mappableScansProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          switch (scans) {
            AsyncData(:final value) when value.isEmpty => const EmptyState(
                icon: Icons.map_outlined,
                title: 'No map yet',
                message: 'Save a scan made with a room sketch or AR, '
                    'and its map shows up here.',
              ),
            AsyncData(:final value) => _MapForScans(scans: value),
            AsyncError(:final error) => EmptyState(
                icon: Icons.error_outline,
                title: "Couldn't load your scans",
                message: '$error',
              ),
            _ => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
          },
          const SizedBox(height: 12),
          const _LegendCard(),
        ],
      ),
    );
  }
}

class _MapForScans extends ConsumerStatefulWidget {
  const _MapForScans({required this.scans});

  final List<MappableScan> scans;

  @override
  ConsumerState<_MapForScans> createState() => _MapForScansState();
}

class _MapForScansState extends ConsumerState<_MapForScans> {
  FloorPoint? _tapped;

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedMapScanProvider);
    final current = widget.scans.where((s) => s.scan.id == selectedId).firstOrNull ??
        widget.scans.first;
    final data = ref.watch(mapDataProvider(current));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: current.scan.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Scan'),
          items: [
            for (final s in widget.scans)
              DropdownMenuItem(
                value: s.scan.id,
                child: Text(
                  '${s.home.name} · ${formatDateTime(s.scan.startedAt)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            setState(() => _tapped = null);
            ref.read(selectedMapScanProvider.notifier).select(id);
          },
        ),
        const SizedBox(height: 12),
        switch (data) {
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MapCard(
                  data: value,
                  tapped: _tapped,
                  onTap: (p) => setState(() => _tapped = p),
                ),
                if (!value.heatmap.isEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => FixesPage(item: current)),
                    ),
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('See fixes'),
                  ),
                ],
              ],
            ),
          AsyncError(:final error) => Text("Couldn't build the map: $error"),
          _ => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
        },
      ],
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.data, required this.tapped, required this.onTap});

  final MapData data;
  final FloorPoint? tapped;
  final ValueChanged<FloorPoint> onTap;

  @override
  Widget build(BuildContext context) {
    final heatmap = data.heatmap;
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (heatmap.isEmpty) {
      return const EmptyState(
        icon: Icons.location_off_outlined,
        title: 'No positions in this scan',
        message: 'None of its readings had a position, so it cannot be mapped.',
      );
    }
    final cell = tapped == null ? null : heatmap.cellAt(tapped!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius / 2),
              child: AspectRatio(
                aspectRatio: 1,
                child: Semantics(
                  label: 'Signal heatmap. ${heatmap.measuredCount} measured areas, '
                      '${heatmap.predictedCount} predicted. Tap to inspect a spot.',
                  child: HeatmapView(
                    heatmap: heatmap,
                    layout: data.layout,
                    selected: tapped,
                    onTapPoint: onTap,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _cellText(tapped, cell),
                style: textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Measured ${heatmap.measuredCount} · predicted ${heatmap.predictedCount} '
              '(${_m(heatmap.cellM)} m squares)',
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  static String _m(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  static String _cellText(FloorPoint? tapped, HeatCell? cell) {
    if (tapped == null) return 'Tap the map to see a spot’s signal.';
    if (cell == null) return 'Not mapped: too far from where you recorded.';
    final dbm = cell.dbm.round().clamp(validRssiMinDbm, validRssiMaxDbm);
    final word = signalQualityFor(dbm).label;
    final how = cell.measured
        ? 'measured (${cell.sampleCount == 1 ? '1 reading spot' : '${cell.sampleCount} readings'})'
        : 'predicted';
    return '$word · ${formatDbm(dbm)} · $how';
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to read the map', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Each signal level has its own pattern, not just a colour. '
              'Solid squares were measured; faded squares are predicted '
              'from nearby readings.',
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 8),
            const SignalLegend(),
            const SizedBox(height: 4),
            Row(
              children: [
                const Opacity(
                  opacity: predictedOpacity,
                  child: SignalSwatch(SignalQuality.good, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Faded = predicted', style: textTheme.titleMedium),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
