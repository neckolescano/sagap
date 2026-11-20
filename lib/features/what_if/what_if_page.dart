import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/path_loss.dart';
import '../../domain/path_track.dart';
import '../../domain/what_if.dart';
import '../common/empty_state.dart';
import '../map/heatmap_view.dart';
import '../map/map_controller.dart';
import 'what_if_controller.dart';

/// What-if simulator (S10): drag the router and see the predicted map.
class WhatIfPage extends ConsumerStatefulWidget {
  const WhatIfPage({super.key, required this.item});

  final MappableScan item;

  @override
  ConsumerState<WhatIfPage> createState() => _WhatIfPageState();
}

class _WhatIfPageState extends ConsumerState<WhatIfPage> {
  FloorPoint? _moved;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(whatIfProvider(widget.item));
    return Scaffold(
      appBar: AppBar(title: const Text('What if I move the router?')),
      body: switch (data) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => Center(child: Text("Couldn't build the model: $error")),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(WhatIfData data) {
    final router = data.router;
    final check = data.check;
    if (router == null || check == null) {
      return const Center(
        child: EmptyState(
          icon: Icons.router_outlined,
          title: 'Mark your router first',
          message: 'Place the router on your room sketch, then try again.',
        ),
      );
    }
    final model = check.model;
    if (!check.usable || model == null) {
      return Center(
        child: EmptyState(
          icon: Icons.info_outline,
          title: "Can't predict yet",
          message: check.problem!,
        ),
      );
    }

    final base = data.map.heatmap;
    final layout = data.map.layout;
    final newRouter = _moved ?? router;
    final predicted = predictMap(base, layout, model, newRouter);
    final before = outcomeFor(base, layout, model, router);
    final after = outcomeFor(base, layout, model, newRouter);
    final best = bestRouterSpot(base, layout, model, router);
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Drag on the map to move the router. Everything shown here is predicted.',
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          child: AspectRatio(
            aspectRatio: 1,
            child: Semantics(
              label: 'Predicted signal map with the router at the pin. '
                  'Drag to move the router.',
              child: HeatmapView(
                heatmap: predicted,
                layout: layout,
                pins: [newRouter],
                onTapPoint: (p) => setState(() => _moved = p),
                onDragPoint: (p) => setState(() => _moved = p),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Predicted change', style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Semantics(
                  liveRegion: true,
                  child: Text(describeChange(before, after), style: textTheme.titleMedium),
                ),
                const SizedBox(height: 8),
                Text(
                  'Moved ${router.distanceTo(newRouter).toStringAsFixed(1)} m. '
                  'Model fit: about ±${check.rmseDb!.toStringAsFixed(1)} dB '
                  'from ${check.sampleCount} readings.',
                  style: textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _moved == null ? null : () => setState(() => _moved = null),
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: best == null ? null : () => setState(() => _moved = best),
                child: const Text('Best spot'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (data.routerGuessed) 'Assumes you started the walk next to the router.',
            "Walls you didn't sketch, furniture, other floors and router height "
                "aren't included. Confirm with the hotspot test or a re-walk "
                'before moving the router.',
          ].join(' '),
          style: textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (best == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No spot in the mapped area is predicted to do clearly better.',
              style: textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Model: ${PathLossSettings.folds}-fold checked, wall losses learned '
          'from your readings.',
          style: textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
