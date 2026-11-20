import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ar_readiness.dart';
import '../../domain/path_track.dart';
import '../../domain/scan_session.dart';
import '../../platform/ar_bridge.dart';
import 'scan_controller.dart';

/// ARCore readiness for this phone, re-checkable after an install.
class ArReadinessController extends AsyncNotifier<ArReadiness> {
  @override
  Future<ArReadiness> build() => _check();

  Future<ArReadiness> _check() async {
    final bridge = ref.read(arBridgeProvider);
    return readinessFor(await resolveAvailability(bridge.checkAvailability));
  }

  Future<void> recheck() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_check);
  }

  Future<ArInstallResult> install() async {
    final result = await ref.read(arBridgeProvider).requestInstall();
    if (result == ArInstallResult.installed) await recheck();
    return result;
  }
}

final arReadinessProvider =
    AsyncNotifierProvider<ArReadinessController, ArReadiness>(
  ArReadinessController.new,
);

/// Whether the current scan uses the AR camera (true) or signal only.
class ArModeController extends Notifier<bool> {
  @override
  bool build() {
    // Leaving the scan closes the AR session (the camera view unmounts).
    ref.listen(scanControllerProvider.select((s) => s.status), (_, status) {
      if (status == ScanStatus.finished || status == ScanStatus.idle) {
        state = false;
      }
    });
    return false;
  }

  void enable() => state = true;
}

final arModeProvider = NotifierProvider<ArModeController, bool>(ArModeController.new);

/// Walked path for the current AR scan.
class PathTrackController extends Notifier<PathTrack> {
  @override
  PathTrack build() {
    ref.listen(poseStreamProvider, (_, next) {
      final recording =
          ref.read(scanControllerProvider).status == ScanStatus.recording;
      if (!recording || !ref.read(arModeProvider)) return;
      if (next case AsyncData(:final value)) state = state.add(value);
    });
    ref.listen(scanControllerProvider.select((s) => s.status), (previous, status) {
      final freshStart =
          status == ScanStatus.recording && previous != ScanStatus.paused;
      if (freshStart) state = const PathTrack.empty();
    });
    return const PathTrack.empty();
  }
}

final pathTrackProvider =
    NotifierProvider<PathTrackController, PathTrack>(PathTrackController.new);

/// Plain-language tracking message, or null when tracking is fine (SPEC.md §10).
String? trackingMessage(PoseSample pose) {
  if (pose.tracking == ArTracking.tracking) return null;
  return switch (pose.failure) {
    'INSUFFICIENT_LIGHT' => 'Too dark. Turn on a light.',
    'INSUFFICIENT_FEATURES' => 'Point at a textured area, not a blank wall.',
    'EXCESSIVE_MOTION' => 'Move slower.',
    'CAMERA_UNAVAILABLE' => 'The camera is unavailable.',
    'BAD_STATE' => 'AR stopped. Try Pause, then Resume.',
    _ => 'Move the phone slowly to start tracking.',
  };
}
