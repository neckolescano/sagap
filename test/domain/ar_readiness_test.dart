import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/domain/ar_readiness.dart';
import 'package:sagap/platform/ar_bridge.dart';

void main() {
  group('readinessFor routes every availability (AT5)', () {
    const expected = {
      ArAvailability.supportedInstalled: ArReadiness.ready,
      ArAvailability.supportedNotInstalled: ArReadiness.needsInstall,
      ArAvailability.supportedApkTooOld: ArReadiness.needsInstall,
      ArAvailability.unsupportedDeviceNotCapable: ArReadiness.unsupported,
      ArAvailability.unknownChecking: ArReadiness.unknown,
      ArAvailability.unknownError: ArReadiness.unknown,
      ArAvailability.unknownTimedOut: ArReadiness.unknown,
    };
    expected.forEach((availability, readiness) {
      test('$availability -> $readiness', () {
        expect(readinessFor(availability), readiness);
      });
    });

    test('covers all values', () {
      expect(expected.keys.toSet(), ArAvailability.values.toSet());
    });
  });

  test('fromChannel parses Kotlin enum names and rejects others', () {
    expect(ArAvailability.fromChannel('SUPPORTED_INSTALLED'),
        ArAvailability.supportedInstalled);
    expect(ArAvailability.fromChannel('UNSUPPORTED_DEVICE_NOT_CAPABLE'),
        ArAvailability.unsupportedDeviceNotCapable);
    expect(() => ArAvailability.fromChannel('NOPE'), throwsFormatException);
    expect(() => ArAvailability.fromChannel(null), throwsFormatException);
  });

  group('resolveAvailability', () {
    test('re-checks while ARCore is still checking', () async {
      final answers = [
        ArAvailability.unknownChecking,
        ArAvailability.unknownChecking,
        ArAvailability.supportedInstalled,
      ];
      var calls = 0;
      final result = await resolveAvailability(
        () async => answers[calls++],
        interval: const Duration(milliseconds: 1),
        limit: const Duration(milliseconds: 10),
      );
      expect(result, ArAvailability.supportedInstalled);
      expect(calls, 3);
    });

    test('gives up after the limit and returns unknownChecking', () async {
      var calls = 0;
      final result = await resolveAvailability(
        () async {
          calls++;
          return ArAvailability.unknownChecking;
        },
        interval: const Duration(milliseconds: 1),
        limit: const Duration(milliseconds: 10),
      );
      expect(result, ArAvailability.unknownChecking);
      expect(calls, 11);
    });
  });
}
