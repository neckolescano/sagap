import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/platform/ar_bridge.dart';

import '../helpers/fakes.dart';

void main() {
  const settle = Duration(milliseconds: 700);
  const fakeCamera = Key('fake-ar-camera');

  Future<FakeSignalSource> connect(WidgetTester tester, FakeArBridge ar) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source, ar: ar);
    source.emit(connectedReading(1000, -55));
    await tester.pump(settle);
    return source;
  }

  testWidgets('unsupported phone: explains and records signal only (§10 step 3)',
      (tester) async {
    final ar = FakeArBridge();
    await connect(tester, ar);
    expect(find.text("This phone doesn't support AR"), findsOneWidget);

    await tester.tap(find.text('Start scan'));
    await tester.pump();
    expect(find.text('Allow the camera?'), findsNothing);
    expect(find.byKey(fakeCamera), findsNothing);
    expect(find.text('Recording'), findsOneWidget);
    expect(ar.cameraRequests, 0);
  });

  testWidgets('ready + camera granted: AR camera and path map appear',
      (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await connect(tester, ar);
    expect(find.text('AR ready'), findsOneWidget);

    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);
    expect(find.byKey(fakeCamera), findsOneWidget);
    expect(find.text('Recording · AR'), findsOneWidget);
    expect(find.text('Starting the camera…'), findsOneWidget);

    ar.emitPose(trackedPose(1000, 0, 0));
    ar.emitPose(trackedPose(1200, 0, -1.5));
    ar.emitPose(trackedPose(1400, 0, -3.0));
    await tester.pump(settle);
    expect(find.text('Starting the camera…'), findsNothing);
    expect(find.bySemanticsLabel('From start: 3.00 m'), findsOneWidget);
    expect(find.bySemanticsLabel('Walked: 3.00 m'), findsOneWidget);
  });

  testWidgets('tracking loss shows a plain-language banner', (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await connect(tester, ar);
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);

    ar.emitPose(lostPose(1000, failure: 'INSUFFICIENT_LIGHT'));
    await tester.pump(settle);
    expect(find.text('Too dark. Turn on a light.'), findsOneWidget);
  });

  testWidgets('AR start error shows a message instead of a crash', (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await connect(tester, ar);
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);

    ar.emitPoseError(PlatformException(code: 'camera_unavailable'));
    await tester.pump(settle);
    expect(find.text('The camera is in use by another app.'), findsOneWidget);
  });

  testWidgets('camera explainer: Allow requests permission, then AR',
      (tester) async {
    final ar = FakeArBridge(availability: ArAvailability.supportedInstalled);
    await connect(tester, ar);

    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text('Allow the camera?'), findsOneWidget);

    await tester.tap(find.text('Allow camera'));
    await tester.pump(settle);
    expect(ar.cameraRequests, 1);
    expect(find.byKey(fakeCamera), findsOneWidget);
  });

  testWidgets('camera denied (AT19): records signal only with a notice',
      (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      grantOnRequest: false,
    );
    await connect(tester, ar);

    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow camera'));
    await tester.pump(settle);

    expect(find.byKey(fakeCamera), findsNothing);
    expect(find.text('Camera not allowed. Recording signal only.'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
  });

  testWidgets('Not now skips the system prompt', (tester) async {
    final ar = FakeArBridge(availability: ArAvailability.supportedInstalled);
    await connect(tester, ar);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pump(settle);
    expect(ar.cameraRequests, 0);
    expect(find.byKey(fakeCamera), findsNothing);
  });

  testWidgets('pause and resume pause the AR session; finish closes it',
      (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await connect(tester, ar);
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);

    await tester.tap(find.text('Pause'));
    await tester.pump(settle);
    await tester.tap(find.text('Resume'));
    await tester.pump(settle);
    expect(ar.calls, ['pause', 'resume']);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Walked 0.00 m'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(fakeCamera), findsNothing);
    expect(find.text('AR ready'), findsOneWidget);
  });

  testWidgets('poses are ignored while paused', (tester) async {
    final ar = FakeArBridge(
      availability: ArAvailability.supportedInstalled,
      cameraAlreadyGranted: true,
    );
    await connect(tester, ar);
    await tester.tap(find.text('Start scan'));
    await tester.pump(settle);
    ar.emitPose(trackedPose(1000, 0, 0));
    await tester.pump(settle);

    await tester.tap(find.text('Pause'));
    await tester.pump(settle);
    ar.emitPose(trackedPose(1200, 0, -4));
    await tester.pump(settle);
    expect(find.bySemanticsLabel('Walked: 0.00 m'), findsOneWidget);
  });

  testWidgets('needs install: Install, then Finish the install', (tester) async {
    final ar = FakeArBridge(availability: ArAvailability.supportedNotInstalled);
    await connect(tester, ar);
    expect(find.text('AR needs one more app'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pump(settle);
    expect(ar.calls, ['install']);
    expect(find.text('Finish the install'), findsOneWidget);

    ar.availability = ArAvailability.supportedInstalled;
    await tester.tap(find.text('Check again'));
    await tester.pump(settle);
    expect(find.text('AR ready'), findsOneWidget);
  });
}
