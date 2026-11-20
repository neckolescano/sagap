import '../platform/ar_bridge.dart';

/// What the Scan screen should do with ARCore (SPEC.md §10, AT5).
enum ArReadiness {
  /// AR mode available.
  ready,

  /// Supported, but Google Play Services for AR must be installed or updated.
  needsInstall,

  /// Device cannot run ARCore: signal-only / manual mode, permanently.
  unsupported,

  /// Check failed or timed out: offer "Check again".
  unknown,
}

ArReadiness readinessFor(ArAvailability availability) => switch (availability) {
      ArAvailability.supportedInstalled => ArReadiness.ready,
      ArAvailability.supportedNotInstalled ||
      ArAvailability.supportedApkTooOld =>
        ArReadiness.needsInstall,
      ArAvailability.unsupportedDeviceNotCapable => ArReadiness.unsupported,
      ArAvailability.unknownChecking ||
      ArAvailability.unknownError ||
      ArAvailability.unknownTimedOut =>
        ArReadiness.unknown,
    };

/// Re-check interval and limit while ARCore reports UNKNOWN_CHECKING.
const Duration arRecheckInterval = Duration(milliseconds: 200);
const Duration arRecheckLimit = Duration(seconds: 2);

/// Calls [check] until it stops reporting `unknownChecking` or [limit] passes.
Future<ArAvailability> resolveAvailability(
  Future<ArAvailability> Function() check, {
  Duration interval = arRecheckInterval,
  Duration limit = arRecheckLimit,
}) async {
  final maxAttempts = limit.inMilliseconds ~/ interval.inMilliseconds;
  var result = await check();
  for (var attempt = 0;
      result == ArAvailability.unknownChecking && attempt < maxAttempts;
      attempt++) {
    await Future<void>.delayed(interval);
    result = await check();
  }
  return result;
}
