import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/scan_repository.dart';
import '../../../domain/ar_readiness.dart';
import '../../sketch/room_sketch_page.dart';
import '../../sketch/sketch_controller.dart';
import '../ar_controller.dart';
import '../manual_controller.dart';
import '../save_scan_dialog.dart';

/// Entry to manual mode (SPEC.md §10 step 4): pick a home, sketch its rooms,
/// then scans record tapped positions on that sketch.
class ManualModeCard extends ConsumerWidget {
  const ManualModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeId = ref.watch(manualHomeProvider);
    if (homeId == null) return _Offer(onTap: () => _choose(context, ref));

    final home = ref.watch(homesProvider).value?.where((h) => h.id == homeId).firstOrNull;
    final rooms = ref.watch(sketchControllerProvider(homeId)).value?.rooms.length ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_square, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Room sketch: ${home?.name ?? ''}',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        rooms == 1 ? '1 room' : '$rooms rooms',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: ref.read(manualHomeProvider.notifier).clear,
                  child: const Text('Stop using'),
                ),
                TextButton(
                  onPressed: () => _openEditor(context, ref, homeId),
                  child: const Text('Edit sketch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final homes = await ref.read(homesProvider.future);
    if (!context.mounted) return;
    final choice = await showSaveScanDialog(
      context,
      homes,
      title: 'Sketch which home?',
      confirmLabel: 'Next',
    );
    if (choice == null || !context.mounted) return;
    final homeId = switch (choice) {
      ExistingHome(:final homeId) => homeId,
      NewHome(:final name) => await ref
          .read(scanRepositoryProvider)
          .createHome(name, ref.read(clockProvider)()),
    };
    ref.invalidate(homesProvider);
    if (!context.mounted) return;
    await _openEditor(context, ref, homeId);
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, int homeId) async {
    final ready = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RoomSketchPage(homeId: homeId)),
    );
    final layout = ref.read(sketchControllerProvider(homeId)).value;
    if (ready == true || (layout != null && !layout.isEmpty)) {
      ref.read(manualHomeProvider.notifier).select(homeId);
    }
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arReady = ref.watch(arReadinessProvider).value == ArReadiness.ready;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
        icon: const Icon(Icons.edit_square),
        label: Text(arReady ? 'Sketch rooms instead' : 'Map with a room sketch'),
      ),
    );
  }
}
