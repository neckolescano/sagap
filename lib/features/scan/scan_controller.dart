import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../domain/scan_session.dart';
import '../../platform/ar_bridge.dart';
import '../../platform/signal_reading.dart';
import '../../platform/signal_source.dart';

/// Number of readings kept for the live timeline (about 60 s at 1 Hz).
const int signalHistoryLength = 60;

/// Drives the current [ScanSession] from live readings and AR poses.
class ScanController extends Notifier<ScanSession> {
  @override
  ScanSession build() {
    ref.listen(liveSignalProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        state = state.addReading(value);
      }
    });
    ref.listen(poseStreamProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        state = state.addPose(value);
      }
    });
    return const ScanSession.idle();
  }

  void start() => state = state.start(ref.read(clockProvider)());
  void pause() => state = state.pause();
  void resume() => state = state.resume();
  void finish() => state = state.finish();
  void reset() => state = const ScanSession.idle();
}

final scanControllerProvider =
    NotifierProvider<ScanController, ScanSession>(ScanController.new);

/// Last [signalHistoryLength] readings, recorded or not.
class SignalHistory extends Notifier<List<SignalReading>> {
  @override
  List<SignalReading> build() {
    ref.listen(liveSignalProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        final updated = [...state, value];
        state = updated.length > signalHistoryLength
            ? updated.sublist(updated.length - signalHistoryLength)
            : updated;
      }
    });
    return const [];
  }
}

final signalHistoryProvider =
    NotifierProvider<SignalHistory, List<SignalReading>>(SignalHistory.new);
