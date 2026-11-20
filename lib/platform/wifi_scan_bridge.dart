import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/channel_check.dart';

/// Location permission and the channel check. Tests replace it with a fake.
abstract interface class WifiScanBridge {
  Future<bool> locationGranted();
  Future<bool> requestLocation();
  Future<bool> locationServicesOn();

  /// Throws [PlatformException] when permission or location is missing.
  Future<ChannelCheck> channelScan();

  /// Opens Android's settings page for this app.
  Future<void> openAppSettings();
}

class PlatformWifiScanBridge implements WifiScanBridge {
  static const _channel = MethodChannel('sagap/wifi');

  @override
  Future<bool> locationGranted() async =>
      await _channel.invokeMethod<String>('locationPermission') == 'granted';

  @override
  Future<bool> requestLocation() async =>
      await _channel.invokeMethod<String>('requestLocationPermission') == 'granted';

  @override
  Future<bool> locationServicesOn() async =>
      await _channel.invokeMethod<bool>('locationServicesOn') ?? false;

  @override
  Future<void> openAppSettings() => _channel.invokeMethod<void>('openAppSettings');

  @override
  Future<ChannelCheck> channelScan() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('channelScan');
    if (raw == null) throw const FormatException('Empty channel scan result');
    final own = raw['ownFreqMhz'];
    final fresh = raw['fresh'];
    final counts = raw['counts'];
    if (own is! int || fresh is! bool || counts is! Map) {
      throw FormatException('Malformed channel scan result', raw);
    }
    return ChannelCheck(
      ownFreqMhz: own,
      fresh: fresh,
      strongByFreq: {
        for (final e in counts.entries) e.key as int: e.value as int,
      },
    );
  }
}

final wifiScanBridgeProvider =
    Provider<WifiScanBridge>((ref) => PlatformWifiScanBridge());
