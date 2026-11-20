import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sagap/app.dart';
import 'package:sagap/data/scan_repository.dart';
import 'package:sagap/data/settings_store.dart';
import 'package:sagap/domain/channel_check.dart';
import 'package:sagap/domain/home_layout.dart';
import 'package:sagap/domain/hotspot.dart';
import 'package:sagap/platform/share_bridge.dart';
import 'package:sagap/platform/wifi_scan_bridge.dart';
import 'package:sagap/domain/path_track.dart';
import 'package:sagap/domain/scan_record.dart';
import 'package:sagap/features/scan/widgets/ar_camera_view.dart';
import 'package:sagap/platform/ar_bridge.dart';
import 'package:sagap/platform/signal_reading.dart';
import 'package:sagap/platform/signal_source.dart';

class FakeSignalSource implements SignalSource {
  final _controller = StreamController<SignalReading>.broadcast();

  void emit(SignalReading reading) => _controller.add(reading);

  void emitError(Object error) => _controller.addError(error);

  @override
  Stream<SignalReading> readings() => _controller.stream;
}

class FakeArBridge implements ArBridge {
  FakeArBridge({
    this.availability = ArAvailability.unsupportedDeviceNotCapable,
    this.cameraAlreadyGranted = false,
    this.grantOnRequest = true,
  });

  ArAvailability availability;
  bool cameraAlreadyGranted;
  bool grantOnRequest;
  ArInstallResult installResult = ArInstallResult.requested;
  int cameraRequests = 0;
  final List<String> calls = [];
  final _poses = StreamController<PoseSample>.broadcast();

  void emitPose(PoseSample pose) => _poses.add(pose);

  void emitPoseError(Object error) => _poses.addError(error);

  @override
  Future<ArAvailability> checkAvailability() async => availability;

  @override
  Future<ArInstallResult> requestInstall() async {
    calls.add('install');
    return installResult;
  }

  @override
  Future<bool> cameraGranted() async => cameraAlreadyGranted;

  @override
  Future<bool> requestCamera() async {
    cameraRequests++;
    cameraAlreadyGranted = grantOnRequest;
    return grantOnRequest;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Stream<PoseSample> poses() => _poses.stream;
}

PoseSample trackedPose(int tMs, double x, double z) => PoseSample(
      tMs: tMs,
      tracking: ArTracking.tracking,
      failure: 'NONE',
      x: x,
      y: 0,
      z: z,
    );

PoseSample lostPose(int tMs, {String failure = 'INSUFFICIENT_FEATURES'}) =>
    PoseSample(
      tMs: tMs,
      tracking: ArTracking.paused,
      failure: failure,
      x: 0,
      y: 0,
      z: 0,
    );

class FakeWifiScanBridge implements WifiScanBridge {
  FakeWifiScanBridge({this.granted = false, this.grantOnRequest = true, this.result});

  bool granted;
  bool grantOnRequest;
  int locationRequests = 0;
  int scans = 0;

  /// Returned by [channelScan]; null throws `location_off`.
  ChannelCheck? result;

  @override
  Future<bool> locationGranted() async => granted;

  @override
  Future<bool> requestLocation() async {
    locationRequests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<bool> locationServicesOn() async => result != null;

  int settingsOpened = 0;

  @override
  Future<void> openAppSettings() async => settingsOpened++;

  @override
  Future<ChannelCheck> channelScan() async {
    scans++;
    final r = result;
    if (r == null) throw PlatformException(code: 'location_off');
    return r;
  }
}

class MemoryScanRepository implements ScanRepository {
  final Map<int, (String, DateTime)> homesById = {};
  final Map<int, (int, ScanRecord)> scansById = {};
  int _nextId = 1;

  @override
  Future<List<HomeSummary>> homes() async {
    final list = [
      for (final MapEntry(key: id, value: (name, createdAt)) in homesById.entries)
        () {
          final scans = [
            for (final (homeId, scan) in scansById.values)
              if (homeId == id) scan,
          ];
          final last = scans.isEmpty
              ? null
              : scans.map((s) => s.startedAt).reduce((a, b) => a.isAfter(b) ? a : b);
          return HomeSummary(
            id: id,
            name: name,
            createdAt: createdAt,
            scanCount: scans.length,
            lastScanAt: last,
          );
        }(),
    ];
    list.sort((a, b) => (b.lastScanAt ?? b.createdAt).compareTo(a.lastScanAt ?? a.createdAt));
    return list;
  }

  @override
  Future<int> createHome(String name, DateTime createdAt) async {
    final id = _nextId++;
    homesById[id] = (name, createdAt);
    return id;
  }

  @override
  Future<void> renameHome(int homeId, String name) async {
    final home = homesById[homeId];
    if (home == null) throw StateError('Home $homeId not found');
    homesById[homeId] = (name, home.$2);
  }

  @override
  Future<void> deleteHome(int homeId) async {
    homesById.remove(homeId);
    scansById.removeWhere((_, value) => value.$1 == homeId);
  }

  @override
  Future<int> saveScan(int homeId, ScanRecord scan) async {
    final id = _nextId++;
    scansById[id] = (homeId, scan);
    return id;
  }

  @override
  Future<List<ScanSummary>> scansForHome(int homeId) async => [
        for (final MapEntry(key: id, value: (home, scan)) in scansById.entries)
          if (home == homeId)
            ScanSummary(
              id: id,
              homeId: home,
              startedAt: scan.startedAt,
              durationMs: scan.durationMs,
              mode: scan.mode,
              sampleCount: scan.samples.length,
              medianDbm: scan.medianDbm,
              walkedM: scan.walkedM,
              loopErrorM: scan.loopErrorM,
            ),
      ];

  @override
  Future<List<StoredSample>> samplesForScan(int scanId) async =>
      scansById[scanId]?.$2.samples ?? const [];

  @override
  Future<void> deleteScan(int scanId) async => scansById.remove(scanId);

  @override
  Future<List<ChannelCheck>> channelChecksForScan(int scanId) async =>
      scansById[scanId]?.$2.channelChecks ?? const [];

  @override
  Future<List<FloorPoint>> noSignalSpotsForScan(int scanId) async =>
      scansById[scanId]?.$2.noSignalSpots ?? const [];

  final Map<int, List<(DateTime, HotspotTest)>> hotspotTests = {};

  @override
  Future<void> saveHotspotTest(int homeId, DateTime at, HotspotTest test) async {
    hotspotTests.putIfAbsent(homeId, () => []).add((at, test));
  }

  @override
  Future<(DateTime, HotspotTest)?> latestHotspotTest(int homeId) async =>
      hotspotTests[homeId]?.last;

  final Map<int, HomeLayout> layouts = {};

  HomeLayout _layout(int homeId) {
    if (!homesById.containsKey(homeId)) throw StateError('Home $homeId not found');
    return layouts[homeId] ?? const HomeLayout();
  }

  @override
  Future<HomeLayout> layoutForHome(int homeId) async => _layout(homeId);

  @override
  Future<int> saveRoom(int homeId, SketchRoom room) async {
    final layout = _layout(homeId);
    if (room.id >= 0) {
      layouts[homeId] = HomeLayout(
        rooms: [for (final r in layout.rooms) r.id == room.id ? room : r],
        router: layout.router,
        spots: layout.spots,
      );
      return room.id;
    }
    final id = _nextId++;
    layouts[homeId] = HomeLayout(
      rooms: [...layout.rooms, room.copyWith(id: id)],
      router: layout.router,
      spots: layout.spots,
    );
    return id;
  }

  @override
  Future<void> deleteRoom(int roomId) async {
    layouts.updateAll((_, l) => l.removeRoom(roomId));
  }

  @override
  Future<void> setRouter(int homeId, FloorPoint? router) async {
    final layout = _layout(homeId);
    layouts[homeId] = router == null ? layout.clearRouter() : layout.setRouter(router);
  }

  @override
  Future<int> addSpot(int homeId, String label, FloorPoint point) async {
    final id = _nextId++;
    layouts[homeId] = _layout(homeId).addSpot(PrioritySpot(id: id, label: label, point: point));
    return id;
  }

  @override
  Future<void> deleteSpot(int spotId) async {
    layouts.updateAll((_, l) => l.removeSpot(spotId));
  }
}

/// Fixed wall-clock time used by widget tests.
final testNow = DateTime(2026, 11, 20, 14, 5);

class MemorySettingsStore implements SettingsStore {
  final Map<String, String> values = {};

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

SignalReading connectedReading(int tMs, int rssi, {int freqMhz = 5180}) =>
    SignalReading(tMs: tMs, connected: true, rssiDbm: rssi, freqMhz: freqMhz);

SignalReading disconnectedReading(int tMs) =>
    SignalReading(tMs: tMs, connected: false);

/// Pumps the app on a phone-sized screen (360 × 800 logical px).
Future<void> pumpSagap(
  WidgetTester tester, {
  FakeSignalSource? source,
  FakeArBridge? ar,
  MemorySettingsStore? store,
  MemoryScanRepository? repo,
  FakeWifiScanBridge? wifi,
  FakeShareBridge? share,
  Map<String, String> initialSettings = const {
    SettingsKeys.onboardingDone: 'true',
  },
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalSourceProvider.overrideWithValue(source ?? FakeSignalSource()),
        arBridgeProvider.overrideWithValue(ar ?? FakeArBridge()),
        scanRepositoryProvider.overrideWithValue(repo ?? MemoryScanRepository()),
        // Default: already granted, so the location dialog doesn't appear in
        // tests that are not about it.
        wifiScanBridgeProvider.overrideWithValue(wifi ?? FakeWifiScanBridge(granted: true)),
        clockProvider.overrideWithValue(() => testNow),
        shareBridgeProvider.overrideWithValue(share ?? FakeShareBridge()),
        arCameraBuilderProvider.overrideWithValue(
          (_) => const ColoredBox(
            key: Key('fake-ar-camera'),
            color: Color(0xFF000000),
          ),
        ),
        settingsStoreProvider.overrideWithValue(store ?? MemorySettingsStore()),
        initialSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const SagapApp(),
    ),
  );
}

/// Records shared images instead of opening Android's share sheet.
class FakeShareBridge implements ShareBridge {
  FakeShareBridge({this.error});

  /// Thrown by [shareImage] when set.
  final PlatformException? error;

  final List<(Uint8List, String)> shared = [];

  @override
  Future<void> shareImage(Uint8List png, String fileName) async {
    if (error case final e?) throw e;
    shared.add((png, fileName));
  }
}
