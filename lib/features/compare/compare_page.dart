import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../data/scan_repository.dart';
import '../../domain/compare.dart';
import '../../domain/scan_record.dart';
import '../common/empty_state.dart';
import '../map/map_controller.dart';
import '../report/report_page.dart';

/// Before and after walks of one home, compared (SPEC.md §9).
final comparisonProvider =
    FutureProvider.family<ScanComparison, (MappableScan, MappableScan)>((ref, pair) async {
  final (before, after) = pair;
  final b = await ref.watch(mapDataProvider(before).future);
  final a = await ref.watch(mapDataProvider(after).future);
  WalkData walk(MapData d) =>
      WalkData(heatmap: d.heatmap, samples: d.samples, noSignalSpots: d.noSignalSpots);
  return compareWalks(before: walk(b), after: walk(a), layout: a.layout);
}, retry: (_, _) => null);

/// Sketch scans, newest first; only these share the sketch's coordinates.
/// Sorted here, not trusted from the caller, so "after" is always newer.
List<ScanSummary> comparableScans(List<ScanSummary> scans) =>
    [for (final s in scans) if (s.mode == ScanMode.manual) s]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

String verdictLabel(ChangeVerdict v) => switch (v) {
      ChangeVerdict.better => 'Better',
      ChangeVerdict.same => 'About the same',
      ChangeVerdict.worse => 'Worse',
      ChangeVerdict.unknown => 'Not measured in both',
    };

String _word(int? dbm) => dbm == null ? '—' : signalQualityFor(dbm).label;

String _delta(int d) => d > 0 ? '+$d dB' : '−${d.abs()} dB';

/// "Weak → Good · +12 dB · Better".
String changeLine(PlaceChange c) {
  final delta = c.deltaDb;
  return [
    '${_word(c.beforeDbm)} → ${_word(c.afterDbm)}',
    if (delta != null) _delta(delta),
    verdictLabel(c.verdict),
    if (c.predicted) 'predicted',
  ].join(' · ');
}

String areaLine(double before, double after) =>
    '${before.toStringAsFixed(1)} m² → ${after.toStringAsFixed(1)} m²';

/// Compare screen: pick two sketch walks, see what changed.
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key, required this.homeId});

  final int homeId;

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  int? _beforeId;
  int? _afterId;

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homesProvider).value?.where((h) => h.id == widget.homeId).firstOrNull;
    final scans = ref.watch(scansForHomeProvider(widget.homeId)).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Before and after')),
      body: home == null || scans == null
          ? const Center(child: CircularProgressIndicator())
          : _body(home, comparableScans(scans)),
    );
  }

  Widget _body(HomeSummary home, List<ScanSummary> scans) {
    if (scans.length < 2) {
      return const Center(
        child: EmptyState(
          icon: Icons.compare_arrows,
          title: 'Two sketch scans needed',
          message: 'Scan once, make a change (like moving the router), then scan '
              'the same spots again. Both scans must use this home’s room sketch.',
        ),
      );
    }
    // Newest is "after", the one before it is "before", unless picked.
    final after = scans.firstWhere((s) => s.id == _afterId, orElse: () => scans[0]);
    final before = scans.firstWhere(
      (s) => s.id == _beforeId,
      orElse: () => scans.firstWhere((s) => s.id != after.id),
    );
    final pair = (MappableScan(home, before), MappableScan(home, after));
    final result = ref.watch(comparisonProvider(pair));
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ScanPicker(
          label: 'Before',
          scans: scans,
          selected: before,
          onChanged: (id) => setState(() => _beforeId = id),
        ),
        const SizedBox(height: 8),
        _ScanPicker(
          label: 'After',
          scans: scans,
          selected: after,
          onChanged: (id) => setState(() => _afterId = id),
        ),
        if (before.id == after.id)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Pick two different scans.', style: textTheme.bodyMedium),
          ),
        if (before.startedAt.isAfter(after.startedAt))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '"Before" is newer than "After", so changes read backwards.',
              style: textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 16),
        switch (result) {
          AsyncData(:final value) => ComparisonSummary(comparison: value),
          AsyncError(:final error) => Text("Couldn't compare these scans: $error"),
          _ => const Center(child: CircularProgressIndicator()),
        },
        const SizedBox(height: 12),
        Text(
          'Wi-Fi moves by a few dB on its own, so changes under '
          '$noticeableChangeDb dB read "About the same". For a fair result, '
          'record the same spots in both scans.',
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        if (result case AsyncData(:final value))
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportPage(
                  item: pair.$2,
                  comparison: value,
                  comparedWith: before.startedAt,
                ),
              ),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Make a report'),
          ),
      ],
    );
  }
}

class _ScanPicker extends StatelessWidget {
  const _ScanPicker({
    required this.label,
    required this.scans,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<ScanSummary> scans;
  final ScanSummary selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        initialValue: selected.id,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final s in scans)
            DropdownMenuItem(value: s.id, child: Text(formatDateTime(s.startedAt))),
        ],
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      );
}

/// The comparison as cards; also used inside the shareable report.
class ComparisonSummary extends StatelessWidget {
  const ComparisonSummary({super.key, required this.comparison});

  final ScanComparison comparison;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final textTheme = Theme.of(context).textTheme;
    Widget row(String title, String value) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(value),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Typical signal', changeLine(c.overall)),
        row('Dead-zone area', areaLine(c.deadAreaBeforeM2, c.deadAreaAfterM2)),
        if (c.noSignalBefore > 0 || c.noSignalAfter > 0)
          row('Out-of-range spots', '${c.noSignalBefore} → ${c.noSignalAfter}'),
        if (c.rooms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Rooms', style: textTheme.titleMedium),
          for (final r in c.rooms) row(r.name, changeLine(r)),
        ],
        if (c.spots.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Your spots', style: textTheme.titleMedium),
          for (final s in c.spots) row(s.name, changeLine(s)),
        ],
      ],
    );
  }
}
