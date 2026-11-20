import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../platform/ar_bridge.dart';
import '../../platform/wifi_scan_bridge.dart';
import '../map/map_controller.dart';
import '../scan/manual_controller.dart';
import '../scan/save_scan_dialog.dart';

/// Camera and location status, re-read when this screen returns to the
/// foreground (e.g. back from Android settings).
final permissionStatusProvider =
    FutureProvider.autoDispose<({bool camera, bool location})>((ref) async {
  final camera = await ref.watch(arBridgeProvider).cameraGranted();
  final location = await ref.watch(wifiScanBridgeProvider).locationGranted();
  return (camera: camera, location: location);
}, retry: (_, _) => null);

/// Permissions with what each is for and what happens without it (SPEC.md §6).
class PermissionsSection extends ConsumerStatefulWidget {
  const PermissionsSection({super.key});

  @override
  ConsumerState<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends ConsumerState<PermissionsSection> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(permissionStatusProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(permissionStatusProvider).value;
    String state(bool? allowed) =>
        allowed == null ? 'Checking…' : (allowed ? 'Allowed' : 'Not allowed');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(title: Text('Permissions')),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text('Camera: ${state(status?.camera)}'),
          subtitle: const Text(
            'Tracks where you walk on phones that support AR. Without it, '
            'scans record signal only or use a room sketch.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text('Location: ${state(status?.location)}'),
          subtitle: const Text(
            'Android needs it to list nearby Wi-Fi for the channel check. '
            'Sagap never reads or saves your location. Without it, the '
            'channel tip is shown instead.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: ref.read(wifiScanBridgeProvider).openAppSettings,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Android settings'),
          ),
        ),
      ],
    );
  }
}

/// Deletes every home, scan, sketch and hotspot test on this phone.
class DeleteAllDataTile extends ConsumerWidget {
  const DeleteAllDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
      title: const Text('Delete all data'),
      subtitle: const Text('Homes, scans, sketches and hotspot tests on this phone.'),
      onTap: () async {
        final sure = await confirmDelete(
          context,
          title: 'Delete all data?',
          message: 'This deletes every home, scan, sketch and hotspot test from '
              'this phone. It cannot be undone. Your theme setting is kept.',
          confirmLabel: 'Delete all',
        );
        if (!sure || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final repo = ref.read(scanRepositoryProvider);
        for (final home in await repo.homes()) {
          await repo.deleteHome(home.id);
        }
        ref.read(manualHomeProvider.notifier).clear();
        ref.read(selectedMapScanProvider.notifier).clear();
        ref.invalidate(homesProvider);
        ref.invalidate(scansForHomeProvider);
        messenger.showSnackBar(const SnackBar(content: Text('All data deleted')));
      },
    );
  }
}
