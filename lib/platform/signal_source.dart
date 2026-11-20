import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'signal_reading.dart';

/// Source of live Wi-Fi readings. Tests replace it with a fake.
abstract interface class SignalSource {
  Stream<SignalReading> readings();
}

/// Reads from the Kotlin `WifiSignalStreamHandler` over an EventChannel.
class PlatformSignalSource implements SignalSource {
  static const _channel = EventChannel('sagap/rssi');

  @override
  Stream<SignalReading> readings() =>
      _channel.receiveBroadcastStream().map(SignalReading.fromChannel);
}

final signalSourceProvider =
    Provider<SignalSource>((ref) => PlatformSignalSource());

/// Live readings, about one per second. No automatic retry, so a channel
/// error is shown as "Can't read" instead of being retried silently.
final liveSignalProvider = StreamProvider<SignalReading>(
  (ref) => ref.watch(signalSourceProvider).readings(),
  retry: (_, _) => null,
);
