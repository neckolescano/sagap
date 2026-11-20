import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/signal/signal_format.dart';
import '../../domain/ar_readiness.dart';
import '../../domain/scan_session.dart';
import '../../platform/ar_bridge.dart';
import '../../platform/signal_reading.dart';
import '../../platform/signal_source.dart';
import 'ar_controller.dart';
import '../../platform/wifi_scan_bridge.dart';
import 'channel_check_controller.dart';
import 'finish_scan_flow.dart';
import 'manual_controller.dart';
import 'scan_controller.dart';
import 'widgets/ar_camera_card.dart';
import 'widgets/ar_status_card.dart';
import 'widgets/manual_mode_card.dart';
import 'widgets/manual_scan_panel.dart';
import 'widgets/path_mini_map.dart';
import 'widgets/scan_controls.dart';
import 'widgets/scan_stats_row.dart';
import 'widgets/signal_gauge.dart';
import 'widgets/signal_timeline.dart';

/// Scan tab (S3/S4).
class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveSignalProvider);
    final session = ref.watch(scanControllerProvider);
    final history = ref.watch(signalHistoryProvider);
    final arMode = ref.watch(arModeProvider);
    final manualHomeId = ref.watch(manualHomeProvider);

    final latest = live.value;
    final connected = latest?.validRssi != null;
    final status = session.status;
    final inScan = status == ScanStatus.recording || status == ScanStatus.paused;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StatusChip(
              status: status,
              mode: arMode ? 'AR' : (manualHomeId != null ? 'Sketch' : null),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (inScan && session.isLong)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.battery_alert_outlined),
                        title: const Text('Long scan'),
                        subtitle: Text(
                          'You have been recording for over '
                          '${longScanNudge.inMinutes} minutes. Finish when you can '
                          'to save battery.',
                        ),
                      ),
                    ),
                  ),
                if (inScan && arMode) ...[
                  const SizedBox(height: 8),
                  const ArCameraCard(),
                  const SizedBox(height: 4),
                ],
                // Sketch first during a manual scan so "Record here" stays in
                // thumb reach without scrolling.
                if (inScan && manualHomeId != null) ...[
                  const SizedBox(height: 8),
                  ManualScanPanel(homeId: manualHomeId, connected: connected),
                ],
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: inScan && (arMode || manualHomeId != null) ? 72 : 8,
                  ),
                  child: SignalGauge(
                    reading: _gaugeFor(live, latest),
                    active: status == ScanStatus.recording,
                  ),
                ),
                if (!inScan) ...[
                  const ArStatusCard(),
                  const SizedBox(height: 12),
                  const ManualModeCard(),
                  const SizedBox(height: 12),
                ],
                ScanStatsRow(session: session),
                const SizedBox(height: 12),
                if (inScan && arMode) ...[
                  PathMiniMap(track: ref.watch(pathTrackProvider)),
                  const SizedBox(height: 12),
                ],
                SignalTimeline(history: history),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!connected && status == ScanStatus.idle)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Connect to your home Wi-Fi to start.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ScanControls(
                    status: status,
                    canStart: connected,
                    onStart: () => _start(context, ref),
                    onPause: () => _pause(ref),
                    onResume: () => _resume(ref),
                    onFinish: () => runFinishFlow(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Starts a scan, in AR mode when the phone supports it and the camera is
  /// allowed; otherwise signal only (SPEC.md §6, §10).
  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final readiness = ref.read(arReadinessProvider).value;
    final manual = ref.read(manualHomeProvider) != null;
    var useAr = false;
    if (readiness == ArReadiness.ready && !manual) {
      useAr = await _ensureCamera(context, ref);
      if (!context.mounted) return;
      if (!useAr) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera not allowed. Recording signal only.')),
        );
      }
    }
    if (useAr) ref.read(arModeProvider.notifier).enable();
    await _askLocationOnce(context, ref);
    ref.read(scanControllerProvider.notifier).start();
  }

  /// Asks for location once per app launch, with a reason first. Android
  /// needs it to list nearby networks for the channel check (SPEC.md §6).
  /// "Not now" or a denial only disables the channel check.
  Future<void> _askLocationOnce(BuildContext context, WidgetRef ref) async {
    final bridge = ref.read(wifiScanBridgeProvider);
    if (ref.read(locationAskedProvider) || await bridge.locationGranted()) return;
    ref.read(locationAskedProvider.notifier).markAsked();
    if (!context.mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.wifi_find),
        title: const Text('Check nearby Wi-Fi channels?'),
        content: const Text(
          'Android only lets apps list nearby Wi-Fi networks with the location '
          'permission. Sagap uses it to see if neighbours share your channel. '
          'It does not read or save your location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow == true) await bridge.requestLocation();
  }

  Future<bool> _ensureCamera(BuildContext context, WidgetRef ref) async {
    final bridge = ref.read(arBridgeProvider);
    if (await bridge.cameraGranted()) return true;
    if (!context.mounted) return false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.photo_camera_outlined),
        title: const Text('Allow the camera?'),
        content: const Text(
          'Sagap uses the camera only to track where you walk, so it can draw '
          'your rooms. No photos or video are saved or shared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow camera'),
          ),
        ],
      ),
    );
    if (allow != true) return false;
    return bridge.requestCamera();
  }

  Future<void> _pause(WidgetRef ref) async {
    ref.read(scanControllerProvider.notifier).pause();
    if (ref.read(arModeProvider)) await ref.read(arBridgeProvider).pause();
  }

  Future<void> _resume(WidgetRef ref) async {
    ref.read(scanControllerProvider.notifier).resume();
    if (ref.read(arModeProvider)) await ref.read(arBridgeProvider).resume();
  }

  GaugeReading _gaugeFor(AsyncValue<SignalReading> live, SignalReading? latest) {
    if (live.hasError && latest == null) {
      return const GaugeMessage(
        "Can't read",
        'Sagap could not read the Wi-Fi signal on this phone.',
      );
    }
    if (latest == null) {
      return const GaugeMessage('Checking…', 'Reading your Wi-Fi signal');
    }
    final rssi = latest.validRssi;
    if (rssi == null) {
      return const GaugeMessage('No Wi-Fi', 'Not connected to a Wi-Fi network');
    }
    return GaugeSignal(rssi, bandLabel: bandLabelFor(latest.freqMhz));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.mode});

  final ScanStatus status;

  /// Short position-mode label ("AR", "Sketch"), or null for signal only.
  final String? mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (String label, Color color) = switch (status) {
      ScanStatus.recording => (mode == null ? 'Recording' : 'Recording · $mode', scheme.primary),
      ScanStatus.paused => ('Paused', scheme.onSurfaceVariant),
      ScanStatus.idle || ScanStatus.finished => ('Live', scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
