import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/signal/signal_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_theme.dart';
import '../../data/scan_repository.dart';
import '../../domain/home_layout.dart';
import '../../domain/hotspot.dart';
import '../../platform/signal_source.dart';
import '../common/empty_state.dart';
import '../common/split_canvas_layout.dart';
import '../scan/save_scan_dialog.dart';
import '../sketch/room_sketch_page.dart';
import '../sketch/sketch_canvas.dart';
import '../sketch/sketch_controller.dart';
import 'hotspot_controller.dart';

/// Newest saved hotspot test per home. Invalidate after saving.
final latestHotspotProvider =
    FutureProvider.family<(DateTime, HotspotTest)?, int>(
      (ref, homeId) =>
          ref.watch(scanRepositoryProvider).latestHotspotTest(homeId),
      retry: (_, _) => null,
    );

/// Laptop hotspot test (S11, SPEC.md §9C).
class HotspotTestPage extends ConsumerWidget {
  const HotspotTestPage({super.key, required this.homeId});

  final int homeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(sketchControllerProvider(homeId)).value;
    final session = ref.watch(hotspotControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Hotspot test')),
      body: layout == null
          ? const Center(child: CircularProgressIndicator())
          : layout.spots.isEmpty
          ? _NeedsSpots(homeId: homeId)
          : switch (session.phase) {
              HotspotPhase.setup => _Setup(layout: layout, session: session),
              HotspotPhase.run => _Run(layout: layout, session: session),
              HotspotPhase.results => _Results(
                homeId: homeId,
                session: session,
              ),
            },
    );
  }
}

class _NeedsSpots extends StatelessWidget {
  const _NeedsSpots({required this.homeId});

  final int homeId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.place_outlined,
        title: 'Add priority spots first',
        message:
            'The test compares signal at places you care about, like '
            'your desk or TV. Add them on your room sketch.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoomSketchPage(homeId: homeId),
            ),
          ),
          child: const Text('Edit sketch'),
        ),
      ),
    );
  }
}

class _Setup extends ConsumerWidget {
  const _Setup({required this.layout, required this.session});

  final HomeLayout layout;
  final HotspotSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(hotspotControllerProvider.notifier);
    final candidates = session.test.candidates;
    final textTheme = Theme.of(context).textTheme;
    return SplitCanvasLayout(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Use a Windows laptop\'s Mobile Hotspot as a stand-in router. '
          'Tap 2 or 3 places you could put the router.',
          style: textTheme.bodyLarge,
        ),
      ),
      canvas: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SketchCanvas(
              layout: layout,
              labelledPins: [for (final c in candidates) (c.point, c.label)],
              onTap: controller.addCandidate,
              semanticLabel: 'Room sketch. Tap to add a candidate router spot.',
            ),
          ),
        ),
      ),
      footer: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      candidates.isEmpty
                          ? 'No spots yet'
                          : 'Spots: ${candidates.map((c) => c.label).join(', ')}',
                      style: textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: candidates.isEmpty
                        ? null
                        : controller.removeLastCandidate,
                    child: const Text('Remove last'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: candidates.length >= minHotspotCandidates
                      ? controller.begin
                      : null,
                  child: const Text('Start test'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Run extends ConsumerWidget {
  const _Run({required this.layout, required this.session});

  final HomeLayout layout;
  final HotspotSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(hotspotControllerProvider.notifier);
    final candidate = session.currentCandidate!;
    final readings = session.test.readings[candidate.label] ?? const {};
    final live = ref.watch(liveSignalProvider).value?.validRssi;
    final allDone = layout.spots.every((s) => readings.containsKey(s.label));
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final total = session.test.candidates.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Spot ${candidate.label} (${session.current + 1} of $total)',
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '1. Put the laptop at spot ${candidate.label} and turn on its Mobile '
          'Hotspot. Keep its settings the same for every spot.\n'
          '2. Connect this phone to the laptop\'s hotspot Wi-Fi.',
          style: textTheme.bodyLarge,
        ),
        CheckboxListTile(
          value: session.connected,
          onChanged: (v) => controller.setConnected(v ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text('This phone is connected to the laptop hotspot'),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            live == null
                ? 'Now: no Wi-Fi signal'
                : 'Now: ${signalQualityFor(live).label} · ${formatDbm(live)}',
            style: textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Stand at each spot and hold still while it records 5 readings.',
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        for (final spot in layout.spots)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(spot.label),
              subtitle: Text(switch (readings[spot.label]) {
                final dbm? =>
                  '${signalQualityFor(dbm).label} · ${formatDbm(dbm)}',
                null => 'Not recorded',
              }),
              trailing: session.collectingSpot == spot.label
                  ? TextButton(
                      onPressed: controller.cancelRecording,
                      child: Text(
                        '${session.collected.length} of $manualReadingsPerSpot · Cancel',
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 48),
                      ),
                      onPressed:
                          session.connected &&
                              live != null &&
                              session.collectingSpot == null
                          ? () => controller.record(spot.label)
                          : null,
                      child: Text(
                        readings.containsKey(spot.label) ? 'Redo' : 'Record',
                      ),
                    ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: allDone && session.collectingSpot == null
              ? controller.next
              : null,
          child: Text(
            session.isLast
                ? 'See results'
                : 'Next: spot ${session.test.candidates[session.current + 1].label}',
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.homeId, required this.session});

  final int homeId;
  final HotspotSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = compareHotspots(session.test);
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final labels = [for (final c in session.test.candidates) c.label];
    final spots = {for (final r in session.test.readings.values) ...r.keys}
        .toList();

    Future<void> save() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await ref
          .read(scanRepositoryProvider)
          .saveHotspotTest(homeId, ref.read(clockProvider)(), session.test);
      ref.invalidate(latestHotspotProvider(homeId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Hotspot test saved')),
      );
      navigator.pop();
    }

    Future<void> discard() async {
      final sure = await confirmDelete(
        context,
        title: 'Discard this test?',
        message: 'The readings from this hotspot test will be lost.',
        confirmLabel: 'Discard',
      );
      if (sure && context.mounted) Navigator.of(context).pop();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Results', style: textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          result?.sentence ?? 'Not enough readings to compare the spots.',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'The spots are compared with each other only: a laptop hotspot is '
          'weaker than a router, so the numbers are not what your router would give.',
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        for (final spot in spots)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spot, style: textTheme.titleSmall),
                  for (final label in labels)
                    if (session.test.readings[label]?[spot] case final dbm?)
                      Semantics(
                        container: true,
                        label:
                            '$spot, spot $label: ${signalQualityFor(dbm).label}, '
                            '${formatDbm(dbm)}'
                            '${result?.bestBySpot[spot] == label ? ', best' : ''}',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            SizedBox(width: 28, child: Text(label)),
                            Expanded(
                              child: Text(
                                '${signalQualityFor(dbm).label} · ${formatDbm(dbm)}',
                              ),
                            ),
                            if (result?.bestBySpot[spot] == label)
                              const Text(
                                'Best',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Reconnect this phone to your home Wi-Fi when you are done.',
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: discard,
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: result == null ? null : save,
                child: const Text('Save result'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
