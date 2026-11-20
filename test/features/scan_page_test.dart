import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  const settle = Duration(milliseconds: 700);

  FilledButton startButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.ancestor(of: find.text('Start scan'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
      );

  testWidgets('shows Checking before the first reading', (tester) async {
    await pumpSagap(tester);
    expect(find.text('Checking…'), findsOneWidget);
  });

  testWidgets('disconnected: No Wi-Fi and Start disabled', (tester) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source);
    source.emit(disconnectedReading(1000));
    await tester.pump(settle);

    expect(find.text('No Wi-Fi'), findsOneWidget);
    expect(find.text('Connect to your home Wi-Fi to start.'), findsOneWidget);
    expect(startButton(tester).onPressed, isNull);
  });

  testWidgets('connected: shows the word first, dBm and band second (AT4)',
      (tester) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source);
    source.emit(connectedReading(1000, -62, freqMhz: 5180));
    await tester.pump(settle);

    expect(find.text('Good'), findsOneWidget);
    expect(find.text('−62 dBm  ·  5 GHz'), findsOneWidget);
    expect(find.bySemanticsLabel('Signal: Good, −62 dBm'), findsOneWidget);
    expect(startButton(tester).onPressed, isNotNull);
  });

  testWidgets('channel error shows a plain message', (tester) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source);
    source.emitError(Exception('no wifi service'));
    await tester.pump(settle);
    expect(find.text("Can't read"), findsOneWidget);
  });

  testWidgets('start, pause, resume, finish flow with summary', (tester) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source);
    source.emit(connectedReading(1000, -55));
    await tester.pump(settle);

    await tester.tap(find.text('Start scan'));
    await tester.pump();
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    source.emit(connectedReading(2000, -58));
    source.emit(connectedReading(3000, -75));
    await tester.pump(settle);
    expect(find.bySemanticsLabel('Readings: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Weakest: Weak'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    source.emit(connectedReading(4000, -90));
    await tester.pump(settle);
    expect(find.bySemanticsLabel('Readings: 2'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    source.emit(connectedReading(5000, -66));
    await tester.pump(settle);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Scan finished'), findsOneWidget);
    expect(find.text('0:01 · 3 readings · typical good'), findsOneWidget);
    expect(find.bySemanticsLabel('Excellent: 33 percent of readings'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Scan finished'), findsNothing);
    expect(find.text('Start scan'), findsOneWidget);
    expect(find.bySemanticsLabel('Readings: 0'), findsOneWidget);
  });

  testWidgets('keeps recording while another tab is open', (tester) async {
    final source = FakeSignalSource();
    await pumpSagap(tester, source: source);
    source.emit(connectedReading(1000, -55));
    await tester.pump(settle);
    await tester.tap(find.text('Start scan'));
    await tester.pump();

    await tester.tap(find.text('Map'));
    await tester.pump();
    source.emit(connectedReading(2000, -60));
    source.emit(connectedReading(3000, -61));
    await tester.pump(settle);

    await tester.tap(find.text('Scan'));
    await tester.pump(settle);
    expect(find.bySemanticsLabel('Readings: 2'), findsOneWidget);
  });
}
