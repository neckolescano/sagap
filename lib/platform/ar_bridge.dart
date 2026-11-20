import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ARCore availability, mirroring `ArCoreApk.Availability` (SPEC.md §10).
enum ArAvailability {
  supportedInstalled,
  supportedNotInstalled,
  supportedApkTooOld,
  unsupportedDeviceNotCapable,
  unknownChecking,
  unknownError,
  unknownTimedOut;

  /// Parses the Kotlin enum name, e.g. `SUPPORTED_INSTALLED`.
  static ArAvailability fromChannel(Object? value) => switch (value) {
        'SUPPORTED_INSTALLED' => supportedInstalled,
        'SUPPORTED_NOT_INSTALLED' => supportedNotInstalled,
        'SUPPORTED_APK_TOO_OLD' => supportedApkTooOld,
        'UNSUPPORTED_DEVICE_NOT_CAPABLE' => unsupportedDeviceNotCapable,
        'UNKNOWN_CHECKING' => unknownChecking,
        'UNKNOWN_ERROR' => unknownError,
        'UNKNOWN_TIMED_OUT' => unknownTimedOut,
        _ => throw FormatException('Unknown ARCore availability', value),
      };
}

enum ArInstallResult { installed, requested, failed }

enum ArTracking { tracking, paused, stopped }

/// One camera pose from ARCore. Translation is in meters (SPEC.md §7).
class PoseSample {
  const PoseSample({
    required this.tMs,
    required this.tracking,
    required this.failure,
    required this.x,
    required this.y,
    required this.z,
  });

  factory PoseSample.fromChannel(Object? event) {
    if (event is! Map) throw FormatException('Pose event is not a map', event);
    final tMs = event['tMs'];
    final tracking = event['tracking'];
    final failure = event['failure'];
    final x = event['x'];
    final y = event['y'];
    final z = event['z'];
    if (tMs is! int ||
        tracking is! String ||
        failure is! String ||
        x is! double ||
        y is! double ||
        z is! double) {
      throw FormatException('Pose event has missing or mistyped fields', event);
    }
    return PoseSample(
      tMs: tMs,
      tracking: switch (tracking) {
        'TRACKING' => ArTracking.tracking,
        'PAUSED' => ArTracking.paused,
        'STOPPED' => ArTracking.stopped,
        _ => throw FormatException('Unknown tracking state', tracking),
      },
      failure: failure,
      x: x,
      y: y,
      z: z,
    );
  }

  final int tMs;
  final ArTracking tracking;

  /// `TrackingFailureReason` name: NONE, BAD_STATE, INSUFFICIENT_LIGHT,
  /// EXCESSIVE_MOTION, INSUFFICIENT_FEATURES, CAMERA_UNAVAILABLE.
  final String failure;
  final double x;
  final double y;
  final double z;
}

/// Commands and pose stream for ARCore. Tests replace it with a fake.
abstract interface class ArBridge {
  Future<ArAvailability> checkAvailability();
  Future<ArInstallResult> requestInstall();
  Future<bool> cameraGranted();
  Future<bool> requestCamera();
  Future<void> pause();
  Future<void> resume();
  Stream<PoseSample> poses();
}

class PlatformArBridge implements ArBridge {
  static const _methods = MethodChannel('sagap/ar');
  static const _poses = EventChannel('sagap/pose');

  @override
  Future<ArAvailability> checkAvailability() async =>
      ArAvailability.fromChannel(await _methods.invokeMethod<String>('checkAvailability'));

  @override
  Future<ArInstallResult> requestInstall() async {
    try {
      final status = await _methods.invokeMethod<String>('requestInstall');
      return switch (status) {
        'INSTALLED' => ArInstallResult.installed,
        'INSTALL_REQUESTED' => ArInstallResult.requested,
        _ => throw FormatException('Unknown install status', status),
      };
    } on PlatformException catch (e) {
      if (e.code == 'install_failed') return ArInstallResult.failed;
      rethrow;
    }
  }

  @override
  Future<bool> cameraGranted() async =>
      await _methods.invokeMethod<String>('cameraPermission') == 'granted';

  @override
  Future<bool> requestCamera() async =>
      await _methods.invokeMethod<String>('requestCameraPermission') == 'granted';

  @override
  Future<void> pause() => _methods.invokeMethod<void>('pause');

  @override
  Future<void> resume() => _methods.invokeMethod<void>('resume');

  @override
  Stream<PoseSample> poses() =>
      _poses.receiveBroadcastStream().map(PoseSample.fromChannel);
}

final arBridgeProvider = Provider<ArBridge>((ref) => PlatformArBridge());

/// Live poses while an AR camera view is on screen.
///
/// No automatic retry: errors (camera unavailable, AR failed) must reach the
/// UI instead of silently re-subscribing.
final poseStreamProvider = StreamProvider<PoseSample>(
  (ref) => ref.watch(arBridgeProvider).poses(),
  retry: (_, _) => null,
);
