import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../domain/scan_record.dart';
import 'ar_controller.dart';
import 'channel_check_controller.dart';
import 'manual_controller.dart';
import 'save_scan_dialog.dart';
import 'scan_controller.dart';
import 'scan_summary_sheet.dart';

/// Finish → summary → Save (choose home) or Discard (confirm) (S7).
///
/// The summary cannot be swiped away; it reopens until the scan is saved or
/// the discard is confirmed, so a scan is never lost by accident.
Future<void> runFinishFlow(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(scanControllerProvider.notifier);
  final arMode = ref.read(arModeProvider);
  final manualHomeId = ref.read(manualHomeProvider);
  final track = arMode ? ref.read(pathTrackProvider) : null;
  final manualPoints = ref.read(manualCaptureProvider).points;
  // Second channel check runs while the summary is open (SPEC.md §7).
  final finishCheck = ref.read(channelCheckProvider.notifier).checkNow();
  controller.finish();

  final session = ref.read(scanControllerProvider);
  final (mode, samples) = switch ((arMode, manualHomeId)) {
    (true, _) => (ScanMode.ar, pairWithPoses(session.readings, session.poses)),
    (false, int()) => (ScanMode.manual, manualPoints),
    (false, null) => (ScanMode.signalOnly, unpositionedSamples(session.readings)),
  };
  Future<ScanRecord> record() async {
    await finishCheck;
    return buildScanRecord(
      startedAt: session.startedAt!,
      durationMs: session.recordedMs,
      mode: mode,
      samples: samples,
      track: track,
      channelChecks: ref.read(channelCheckProvider).checks,
    );
  }

  while (true) {
    if (!context.mounted) break;
    final outcome = await showModalBottomSheet<SummaryOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ScanSummarySheet(
        session: session,
        track: track,
        savedSampleCount: samples.length,
        manualSpots: mode == ScanMode.manual ? samples.length : null,
      ),
    );
    if (!context.mounted) break;

    if (outcome == SummaryOutcome.discard) {
      final sure = await confirmDelete(
        context,
        title: 'Discard this scan?',
        message: 'The readings from this walk will be lost.',
        confirmLabel: 'Discard',
      );
      if (sure) break;
      continue;
    }

    if (outcome == SummaryOutcome.save) {
      final built = await record();
      if (!context.mounted) break;
      final saved = await _save(context, ref, built, sketchHomeId: manualHomeId);
      if (saved) break;
    }
  }
  controller.reset();
}

/// Saves [record]. A sketch scan belongs to the sketched home, so it is saved
/// there without asking.
Future<bool> _save(
  BuildContext context,
  WidgetRef ref,
  ScanRecord record, {
  required int? sketchHomeId,
}) async {
  final repo = ref.read(scanRepositoryProvider);
  final homes = await ref.read(homesProvider.future);
  if (!context.mounted) return false;
  final choice = sketchHomeId != null
      ? ExistingHome(sketchHomeId)
      : await showSaveScanDialog(context, homes);
  if (choice == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final (homeId, homeName) = switch (choice) {
      ExistingHome(:final homeId) => (
          homeId,
          homes.firstWhere((h) => h.id == homeId).name,
        ),
      NewHome(:final name) => (
          await repo.createHome(name, ref.read(clockProvider)()),
          name,
        ),
    };
    await repo.saveScan(homeId, record);
    ref.invalidate(homesProvider);
    ref.invalidate(scansForHomeProvider(homeId));
    messenger.showSnackBar(SnackBar(content: Text('Saved to $homeName')));
    return true;
  } on Exception catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text("Couldn't save the scan: $e")),
    );
    return false;
  }
}
