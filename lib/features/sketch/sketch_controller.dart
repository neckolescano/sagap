import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/scan_repository.dart';
import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';

/// One home's room sketch. Every edit is saved immediately, so leaving the
/// editor never loses work.
class SketchController extends AsyncNotifier<HomeLayout> {
  SketchController(this.homeId);

  final int homeId;

  ScanRepository get _repo => ref.read(scanRepositoryProvider);

  HomeLayout get _layout => state.requireValue;

  @override
  Future<HomeLayout> build() => _repo.layoutForHome(homeId);

  Future<void> addRoom(String name, double width, double length, {bool outside = false}) async {
    // Place and snap first, then store with a real id.
    final room = _layout
        .addRoom(id: -1, name: name, width: width, length: length, outside: outside)
        .rooms
        .last;
    final id = await _repo.saveRoom(homeId, room);
    state = AsyncData(_layout.addRoomWithId(room, id));
  }

  /// Moves or resizes a room on screen only (during a drag).
  void previewRoom(SketchRoom room) =>
      state = AsyncData(_layout.updateRoom(room));

  /// Saves a room's position, size or name.
  Future<void> commitRoom(SketchRoom room) async {
    final updated = _layout.updateRoom(room);
    state = AsyncData(updated);
    await _repo.saveRoom(homeId, updated.rooms.firstWhere((r) => r.id == room.id));
  }

  /// Moves [room] by one [nudgeStepM] grid step per unit of [dx] / [dy].
  Future<void> nudgeRoom(SketchRoom room, int dx, int dy) => commitRoom(
        room.copyWith(x: room.x + dx * nudgeStepM, y: room.y + dy * nudgeStepM),
      );

  /// Puts [room] [gapM] meters to [side] of the room [anchorId].
  Future<void> placeBeside(SketchRoom room, int anchorId, RoomSide side, double gapM) {
    final anchor = _layout.rooms.firstWhere((r) => r.id == anchorId);
    return commitRoom(_layout.placeBeside(room, anchor, side, gapM));
  }

  Future<void> removeRoom(int roomId) async {
    state = AsyncData(_layout.removeRoom(roomId));
    await _repo.deleteRoom(roomId);
  }

  Future<void> setRouter(FloorPoint point) async {
    final updated = _layout.setRouter(point);
    state = AsyncData(updated);
    await _repo.setRouter(homeId, updated.router);
  }

  Future<void> clearRouter() async {
    state = AsyncData(_layout.clearRouter());
    await _repo.setRouter(homeId, null);
  }

  Future<void> addSpot(String label, FloorPoint point) async {
    final draft = _layout.addSpot(PrioritySpot(id: -1, label: label, point: point));
    final snapped = draft.spots.last.point;
    final id = await _repo.addSpot(homeId, label, snapped);
    state = AsyncData(
      _layout.addSpot(PrioritySpot(id: id, label: label, point: snapped)),
    );
  }

  Future<void> removeSpot(int spotId) async {
    state = AsyncData(_layout.removeSpot(spotId));
    await _repo.deleteSpot(spotId);
  }
}

extension on HomeLayout {
  /// Appends [room] with its stored [id], keeping its snapped geometry.
  HomeLayout addRoomWithId(SketchRoom room, int id) => HomeLayout(
        rooms: [...rooms, room.copyWith(id: id)],
        router: router,
        spots: spots,
      );
}

final sketchControllerProvider =
    AsyncNotifierProvider.family<SketchController, HomeLayout, int>(
  SketchController.new,
  retry: (_, _) => null,
);
