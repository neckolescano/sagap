import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/scan_repository.dart';
import '../../core/format/date_format.dart';
import '../../domain/fixes.dart';
import '../../domain/hotspot.dart';
import '../../domain/scan_record.dart';
import '../../domain/what_if.dart';
import '../hotspot/hotspot_test_page.dart';
import '../map/heatmap_view.dart';
import '../map/map_controller.dart';
import '../what_if/what_if_controller.dart';
import '../what_if/what_if_page.dart';

/// Inputs for the fixes of one scan.
class FixesData {
  const FixesData({
    required this.map,
    required this.fixes,
    required this.targets,
    this.routerGuessed = false,
    this.modelUsable = false,
  });
  final MapData map;
  final List<Fix> fixes;
  final List<FixTarget> targets;

  /// True when the router position is where an AR walk started.
  final bool routerGuessed;

  /// Whether the what-if model passed its quality check.
  final bool modelUsable;
}

String tierLabel(CostTier tier) => switch (tier) {
      CostTier.free => 'Free',
      CostTier.lowCost => 'Low cost',
      CostTier.higherCost => 'Higher cost',
    };

String evidenceLabel(Evidence evidence) => switch (evidence) {
      Evidence.measured => 'Measured',
      Evidence.measuredRelative => 'Measured (relative)',
      Evidence.predicted => 'Predicted',
      Evidence.notEstimated => 'Not estimated',
    };

/// Builds the ranked fixes for a saved scan (SPEC.md §9).
final fixesProvider = FutureProvider.family<FixesData, MappableScan>((ref, item) async {
  final whatIf = await ref.watch(whatIfProvider(item).future);
  final data = whatIf.map;
  final checks =
      await ref.watch(scanRepositoryProvider).channelChecksForScan(item.scan.id);
  final router = whatIf.router;
  final model = whatIf.check;
  final hotspot = await ref.watch(latestHotspotProvider(item.home.id).future);
  return FixesData(
    map: data,
    targets: findTargets(data.heatmap, data.layout),
    routerGuessed: whatIf.routerGuessed,
    modelUsable: model?.usable ?? false,
    fixes: buildFixes(
      map: data.heatmap,
      layout: data.layout,
      router: router,
      channelChecks: checks,
      channelCheckAvailable: checks.isNotEmpty,
      moveRouter: router == null || model == null
          ? null
          : moveRouterFix(base: data.heatmap, layout: data.layout, check: model, router: router),
      hotspotResult: hotspot == null
          ? null
          : hotspotFix(
              hotspot.$2,
              formatDate(hotspot.$1),
              showPin: item.scan.mode == ScanMode.manual,
            ),
    ),
  );
}, retry: (_, _) => null);

/// Fixes screen (S9): cards ranked by cost; tap one to see where on the map.
class FixesPage extends ConsumerStatefulWidget {
  const FixesPage({super.key, required this.item});

  final MappableScan item;

  @override
  ConsumerState<FixesPage> createState() => _FixesPageState();
}

class _FixesPageState extends ConsumerState<FixesPage> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(fixesProvider(widget.item));
    return Scaffold(
      appBar: AppBar(title: const Text('Fixes')),
      body: switch (data) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => Center(child: Text("Couldn't work out fixes: $error")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(FixesData data) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final selectedFix = _selected == null ? null : data.fixes[_selected!];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          child: AspectRatio(
            aspectRatio: 1.3,
            child: HeatmapView(
              heatmap: data.map.heatmap,
              layout: data.map.layout,
              pins: selectedFix?.points ?? const [],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (data.targets.isEmpty)
          Text(
            'No dead zones found in this scan. Where you walked, the signal '
            'is Weak or better.',
            style: textTheme.titleMedium,
          )
        else ...[
          Text(
            'Weak areas: ${[for (final t in data.targets) t.label].join(', ')}',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Ranked by cost, free first. Sagap measures and suggests; '
            'it does not change your Wi-Fi.',
            style: textTheme.bodyMedium?.copyWith(color: muted),
          ),
          if (data.routerGuessed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Assumes you started the walk next to the router.',
                style: textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => WhatIfPage(item: widget.item)),
          ),
          icon: const Icon(Icons.open_with),
          label: Text(data.modelUsable
              ? 'Try moving the router'
              : 'Try moving the router (needs more data)'),
        ),
        const SizedBox(height: 12),
        for (final (i, fix) in data.fixes.indexed) ...[
          _FixCard(
            fix: fix,
            selected: i == _selected,
            onTap: fix.points.isEmpty ? null : () => setState(() => _selected = i),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FixCard extends StatelessWidget {
  const _FixCard({required this.fix, required this.selected, required this.onTap});

  final Fix fix;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tier = tierLabel(fix.tier);
    final evidence = evidenceLabel(fix.evidence);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _Tag(tier, highlight: fix.tier == CostTier.free),
                  _Tag(evidence),
                ],
              ),
              const SizedBox(height: 8),
              Text(fix.what, style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(fix.where, style: textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(fix.improvement,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    selected ? 'Shown on the map above' : 'Tap to show on the map',
                    style: textTheme.labelLarge?.copyWith(color: scheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
