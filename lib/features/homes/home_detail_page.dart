import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../core/signal/signal_format.dart';
import '../../core/theme/signal_pattern.dart';
import '../../data/scan_repository.dart';
import '../../domain/scan_record.dart';
import '../common/empty_state.dart';
import '../compare/compare_page.dart';
import '../hotspot/hotspot_test_page.dart';
import '../scan/manual_controller.dart';
import '../scan/save_scan_dialog.dart';
import '../sketch/sketch_controller.dart';

/// One home's saved scans, with rename and delete (S13).
class HomeDetailPage extends ConsumerWidget {
  const HomeDetailPage({super.key, required this.homeId});

  final int homeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homesProvider).value?.where((h) => h.id == homeId).firstOrNull;
    final scans = ref.watch(scansForHomeProvider(homeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(home?.name ?? 'Home'),
        actions: [
          IconButton(
            tooltip: 'Before and after',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => ComparePage(homeId: homeId)),
            ),
          ),
          IconButton(
            tooltip: 'Hotspot test',
            icon: const Icon(Icons.laptop_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => HotspotTestPage(homeId: homeId)),
            ),
          ),
          PopupMenuButton<_HomeAction>(
            tooltip: 'Home options',
            onSelected: (action) => switch (action) {
              _HomeAction.rename => _rename(context, ref, home),
              _HomeAction.delete => _delete(context, ref, home),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _HomeAction.rename, child: Text('Rename')),
              PopupMenuItem(value: _HomeAction.delete, child: Text('Delete home')),
            ],
          ),
        ],
      ),
      body: switch (scans) {
        AsyncData(:final value) when value.isEmpty => const Center(
            child: EmptyState(
              icon: Icons.wifi_find,
              title: 'No scans',
              message: 'Scans you save to this home appear here.',
            ),
          ),
        AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _ScanCard(
              scan: value[i],
              onDelete: () => _deleteScan(context, ref, value[i]),
            ),
          ),
        AsyncError(:final error) => Center(
            child: EmptyState(
              icon: Icons.error_outline,
              title: "Couldn't load scans",
              message: '$error',
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, HomeSummary? home) async {
    if (home == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: home.name),
    );
    if (name == null || name.isEmpty || name == home.name) return;
    await ref.read(scanRepositoryProvider).renameHome(homeId, name);
    ref.invalidate(homesProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, HomeSummary? home) async {
    if (home == null) return;
    final scans = home.scanCount == 1 ? '1 scan' : '${home.scanCount} scans';
    final sure = await confirmDelete(
      context,
      title: 'Delete ${home.name}?',
      message: 'This deletes the home and its $scans from this phone. '
          'It cannot be undone.',
    );
    if (!sure || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(scanRepositoryProvider).deleteHome(homeId);
    if (ref.read(manualHomeProvider) == homeId) {
      ref.read(manualHomeProvider.notifier).clear();
    }
    ref.invalidate(sketchControllerProvider(homeId));
    ref.invalidate(homesProvider);
    ref.invalidate(scansForHomeProvider(homeId));
    navigator.pop();
  }

  Future<void> _deleteScan(BuildContext context, WidgetRef ref, ScanSummary scan) async {
    final sure = await confirmDelete(
      context,
      title: 'Delete this scan?',
      message: 'The scan from ${formatDateTime(scan.startedAt)} will be '
          'removed from this phone. It cannot be undone.',
    );
    if (!sure) return;
    await ref.read(scanRepositoryProvider).deleteScan(scan.id);
    ref.invalidate(scansForHomeProvider(homeId));
    ref.invalidate(homesProvider);
  }
}

enum _HomeAction { rename, delete }

/// Owns its text controller so it is disposed only after the dialog's
/// closing animation, not while the TextField is still on screen.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename home'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxHomeNameLength,
        decoration: const InputDecoration(labelText: 'Home name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan, required this.onDelete});

  final ScanSummary scan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final quality = scan.typicalQuality;
    final mode = switch (scan.mode) {
      ScanMode.ar => 'AR',
      ScanMode.signalOnly => 'Signal only',
      ScanMode.manual => 'Room sketch',
    };
    final details = [
      formatDuration(scan.durationMs),
      '${scan.sampleCount} readings',
      mode,
      if (scan.walkedM case final walked?) '${walked.toStringAsFixed(1)} m walked',
    ].join(' · ');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        leading: quality == null
            ? const Icon(Icons.signal_wifi_off)
            : SignalSwatch(quality, size: 32),
        title: Text(formatDateTime(scan.startedAt)),
        subtitle: Text(
          quality == null ? details : 'Typically ${quality.label.toLowerCase()}\n$details',
        ),
        isThreeLine: quality != null,
        trailing: IconButton(
          tooltip: 'Delete scan',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
