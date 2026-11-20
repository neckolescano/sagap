import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/data/settings_store.dart';

import 'helpers/fakes.dart';

void main() {
  ThemeMode currentMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  group('first-run guide (AT3)', () {
    testWidgets('shows 3 steps and Get started opens the app', (tester) async {
      final store = MemorySettingsStore();
      await pumpSagap(tester, store: store, initialSettings: const {});

      expect(find.text('Start at your router'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Walk every room'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Get your fixes'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pump();
      expect(find.text('Scan'), findsWidgets);
      expect(store.values[SettingsKeys.onboardingDone], 'true');
    });

    testWidgets('Skip opens the app and saves it', (tester) async {
      final store = MemorySettingsStore();
      await pumpSagap(tester, store: store, initialSettings: const {});
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(find.text('Start at your router'), findsNothing);
      expect(store.values[SettingsKeys.onboardingDone], 'true');
    });

    testWidgets('not shown when already done', (tester) async {
      await pumpSagap(tester);
      expect(find.text('Start at your router'), findsNothing);
    });

    testWidgets('replayable from Settings', (tester) async {
      await pumpSagap(tester);
      await tester.tap(find.text('Homes'));
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show the guide again'));
      await tester.pumpAndSettle();
      expect(find.text('Start at your router'), findsOneWidget);
    });
  });

  testWidgets('switches between the 3 tabs (AT2)', (tester) async {
    await pumpSagap(tester);

    await tester.tap(find.text('Map'));
    await tester.pump();
    expect(find.text('No map yet'), findsOneWidget);

    await tester.tap(find.text('Homes'));
    await tester.pump();
    expect(find.text('No homes yet'), findsOneWidget);

    await tester.tap(find.text('Start a scan'));
    await tester.pump();
    expect(find.text('Start scan'), findsOneWidget);
  });

  testWidgets('map legend shows words, not colour only (AT12)', (tester) async {
    await pumpSagap(tester);
    await tester.tap(find.text('Map'));
    await tester.pump();
    for (final word in ['Excellent', 'Good', 'Weak', 'Dead zone']) {
      expect(find.text(word), findsOneWidget);
    }
  });

  testWidgets('theme choice is applied and saved (AT2)', (tester) async {
    final store = MemorySettingsStore();
    await pumpSagap(tester, store: store);
    expect(currentMode(tester), ThemeMode.dark);

    await tester.tap(find.text('Homes'));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(currentMode(tester), ThemeMode.light);
    expect(store.values[SettingsKeys.themeMode], 'light');

    await tester.tap(find.text('Match system'));
    await tester.pumpAndSettle();
    expect(currentMode(tester), ThemeMode.system);
    expect(store.values[SettingsKeys.themeMode], 'system');
  });

  testWidgets('saved theme is restored on launch', (tester) async {
    await pumpSagap(
      tester,
      initialSettings: const {
        SettingsKeys.onboardingDone: 'true',
        SettingsKeys.themeMode: 'light',
      },
    );
    expect(currentMode(tester), ThemeMode.light);
  });
}
