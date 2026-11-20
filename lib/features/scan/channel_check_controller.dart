import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../domain/channel_check.dart';
import '../../domain/scan_session.dart';
import '../../platform/wifi_scan_bridge.dart';
import 'scan_controller.dart';

/// Channel checks for the current survey.
class ChannelCheckState {
  const ChannelCheckState({
    this.checks = const [],
    this.budget = const ScanBudget(),
    this.unavailableReason,
  });

  final List<ChannelCheck> checks;
  final ScanBudget budget;

  /// Why the last attempt could not run, or null.
  final String? unavailableReason;
}

/// Runs the channel check at Start and at Finish (SPEC.md §7), at most
/// [scansPerSurvey] per survey and within Android's throttle (AT18).
class ChannelCheckController extends Notifier<ChannelCheckState> {
  @override
  ChannelCheckState build() {
    ref.listen(scanControllerProvider.select((s) => s.status), (previous, status) {
      final freshStart = status == ScanStatus.recording && previous != ScanStatus.paused;
      if (freshStart) {
        state = ChannelCheckState(budget: state.budget);
        checkNow();
      }
    });
    return const ChannelCheckState();
  }

  /// Runs one check if allowed. Never throws: a failure is recorded as
  /// [ChannelCheckState.unavailableReason], and the Fixes screen then shows
  /// the manual channel tip instead (SPEC.md §6).
  Future<void> checkNow() async {
    if (state.checks.length >= scansPerSurvey) return;
    final now = ref.read(clockProvider)();
    if (!state.budget.canScan(now)) {
      state = ChannelCheckState(
        checks: state.checks,
        budget: state.budget,
        unavailableReason: 'scan limit reached',
      );
      return;
    }
    final bridge = ref.read(wifiScanBridgeProvider);
    if (!await bridge.locationGranted()) {
      state = ChannelCheckState(
        checks: state.checks,
        budget: state.budget,
        unavailableReason: 'location not allowed',
      );
      return;
    }
    final budget = state.budget.record(now);
    try {
      final check = await bridge.channelScan();
      state = ChannelCheckState(checks: [...state.checks, check], budget: budget);
    } on PlatformException catch (e) {
      state = ChannelCheckState(
        checks: state.checks,
        budget: budget,
        unavailableReason: e.code == 'location_off' ? 'location is off' : e.code,
      );
    }
  }
}

/// Whether the location reason dialog was shown this app launch.
class LocationAsked extends Notifier<bool> {
  @override
  bool build() => false;

  void markAsked() => state = true;
}

final locationAskedProvider = NotifierProvider<LocationAsked, bool>(LocationAsked.new);

final channelCheckProvider =
    NotifierProvider<ChannelCheckController, ChannelCheckState>(ChannelCheckController.new);
