import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/data/settings_store.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';

import '../helpers/fakes.dart';

/// Accessibility pass (SPEC.md §11, M10): Android tap-target size, labelled
/// tap targets and text contrast on every main screen, in both themes; and
/// no overflow at 200 % text size.
void main() {
  const settle = Duration(milliseconds: 700);

  Future<MemoryScanRepository> populated() async {
    final repo = MemoryScanRepository();
    final home = await repo.createHome('My home', testNow);
    await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Sala', x: 0, y: 0, width: 4, length: 3));
    await repo.saveRoom(home, const SketchRoom(id: -1, name: 'Bedroom', x: 4, y: 0, width: 3, length: 3));
    await repo.setRouter(home, const FloorPoint(0.5, 0.5));
    await repo.addSpot(home, 'Desk', const FloorPoint(6, 2));
    await repo.saveScan(
      home,
      ScanRecord(
        startedAt: testNow,
        durationMs: 60000,
        mode: ScanMode.manual,
        samples: [
          for (var i = 0; i < 12; i++)
            StoredSample(tMs: i, rssiDbm: -45 - i * 4, xM: 0.5 + i * 0.5, yM: 1.5),
        ],
        path: const [],
      ),
    );
    return repo;
  }

  Future<void> checkGuidelines(WidgetTester tester) async {
    // Let colour transitions (e.g. a button becoming enabled) finish first;
    // a single long pump() starts them without running their frames.
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  for (final theme in ['dark', 'light']) {
    group('$theme theme', () {
      Map<String, String> settings() => {
            SettingsKeys.onboardingDone: 'true',
            SettingsKeys.themeMode: theme,
          };

      testWidgets('Scan', (tester) async {
        final handle = tester.ensureSemantics();
        final source = FakeSignalSource();
        await pumpSagap(tester, source: source, initialSettings: settings());
        source.emit(connectedReading(1000, -62));
        await tester.pump(settle);
        await checkGuidelines(tester);
        handle.dispose();
      });

      testWidgets('Map with a heatmap', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpSagap(tester, repo: await populated(), initialSettings: settings());
        await tester.tap(find.text('Map'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        handle.dispose();
      });

      testWidgets('Fixes', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpSagap(tester, repo: await populated(), initialSettings: settings());
        await tester.tap(find.text('Map'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('See fixes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('See fixes'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        handle.dispose();
      });

      testWidgets('Homes, home detail and Settings', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpSagap(tester, repo: await populated(), initialSettings: settings());
        await tester.tap(find.text('Homes'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        await tester.tap(find.text('My home'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await checkGuidelines(tester);
        handle.dispose();
      });

      testWidgets('Before and after, and the report', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpSagap(
          tester,
          repo: await withSecondWalk(await populated()),
          initialSettings: settings(),
        );
        await openCompareAndReport(tester, check: () => checkGuidelines(tester));
        handle.dispose();
      });

      testWidgets('First-run guide', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpSagap(tester, initialSettings: {SettingsKeys.themeMode: theme});
        await checkGuidelines(tester);
        handle.dispose();
      });
    });
  }

  group('200 % text size: no overflow', () {
    setUp(() {});

    Future<void> atDoubleText(WidgetTester tester, Future<void> Function() steps) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await steps();
    }

    testWidgets('Scan, idle and recording', (tester) async {
      await atDoubleText(tester, () async {
        final source = FakeSignalSource();
        await pumpSagap(tester, source: source);
        source.emit(connectedReading(1000, -62));
        await tester.pump(settle);
        await tester.tap(find.text('Start scan'));
        await tester.pump(settle);
        source.emit(connectedReading(2000, -64));
        await tester.pump(settle);
        expect(find.text('Pause'), findsOneWidget);
      });
    });

    testWidgets('Map, Fixes, Homes, Settings', (tester) async {
      await atDoubleText(tester, () async {
        await pumpSagap(tester, repo: await populated());
        await tester.tap(find.text('Map'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('See fixes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('See fixes'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Homes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My home'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('First-run guide', (tester) async {
      await atDoubleText(tester, () async {
        await pumpSagap(tester, initialSettings: const {});
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Get started'), findsOneWidget);
      });
    });

    testWidgets('Sketch editor and hotspot setup', (tester) async {
      await atDoubleText(tester, () async {
        await pumpSagap(tester, repo: await populated());
        await tester.tap(find.text('Homes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My home'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Hotspot test'));
        await tester.pumpAndSettle();
        expect(find.text('Start test'), findsOneWidget);
      });
    });

    testWidgets('Sketch editor with a selected room and its tools', (tester) async {
      await atDoubleText(tester, () async {
        await pumpSagap(tester, repo: MemoryScanRepository());
        await tester.scrollUntilVisible(find.text('Map with a room sketch'), 200);
        // Align it to the top, clear of the bottom Start button.
        await tester.ensureVisible(find.text('Map with a room sketch'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Map with a room sketch'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Add room'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Touches Room 1'), findsOneWidget);
        expect(find.byTooltip('Move right'), findsOneWidget);
      });
    });

    testWidgets('Before and after, and the report', (tester) async {
      await atDoubleText(tester, () async {
        await pumpSagap(tester, repo: await withSecondWalk(await populated()));
        await openCompareAndReport(tester);
      });
    });
  });
}

/// Adds a second, newer sketch walk to the first home of [repo].
Future<MemoryScanRepository> withSecondWalk(MemoryScanRepository repo) async {
  await repo.saveScan(
    repo.homesById.keys.first,
    ScanRecord(
      startedAt: testNow.add(const Duration(days: 1)),
      durationMs: 60000,
      mode: ScanMode.manual,
      samples: [
        for (var i = 0; i < 12; i++)
          StoredSample(tMs: i, rssiDbm: -45 - i * 2, xM: 0.5 + i * 0.5, yM: 1.5),
      ],
      path: const [],
    ),
  );
  return repo;
}

/// Homes → My home → Before and after → Make a report.
Future<void> openCompareAndReport(WidgetTester tester, {Future<void> Function()? check}) async {
  await tester.tap(find.text('Homes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My home'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Before and after'));
  await tester.pumpAndSettle();
  expect(find.text('Typical signal'), findsOneWidget);
  await check?.call();
  await tester.scrollUntilVisible(find.text('Make a report'), 200);
  await tester.tap(find.text('Make a report'));
  await tester.pumpAndSettle();
  expect(find.text('Share image'), findsOneWidget);
  await check?.call();
}
