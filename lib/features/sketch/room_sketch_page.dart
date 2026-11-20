import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';
import '../common/split_canvas_layout.dart';
import '../scan/save_scan_dialog.dart';
import 'room_dialog.dart';
import 'sketch_canvas.dart';
import 'sketch_controller.dart';

enum SketchTool { rooms, router, spots }

/// Room sketch editor (S6): rectangles, router and priority spots.
/// Pops `true` when the sketch has at least one room.
class RoomSketchPage extends ConsumerStatefulWidget {
  const RoomSketchPage({super.key, required this.homeId});

  final int homeId;

  @override
  ConsumerState<RoomSketchPage> createState() => _RoomSketchPageState();
}

class _RoomSketchPageState extends ConsumerState<RoomSketchPage> {
  SketchTool _tool = SketchTool.rooms;
  int? _selectedRoomId;

  SketchController get _controller =>
      ref.read(sketchControllerProvider(widget.homeId).notifier);

  Future<void> _addRoom(HomeLayout layout) async {
    final input = await showRoomDialog(
      context,
      title: 'Add room',
      confirmLabel: 'Add',
      initialName: 'Room ${layout.rooms.length + 1}',
    );
    if (input == null) return;
    await _controller.addRoom(input.name, input.width, input.length);
    if (!mounted) return;
    final rooms = ref
        .read(sketchControllerProvider(widget.homeId))
        .value
        ?.rooms;
    setState(() => _selectedRoomId = rooms?.last.id);
  }

  Future<void> _editRoom(SketchRoom room) async {
    final input = await showRoomDialog(
      context,
      title: 'Edit room',
      confirmLabel: 'Save',
      initialName: room.name,
      initialWidth: room.width,
      initialLength: room.length,
    );
    if (input == null) return;
    await _controller.commitRoom(
      room.copyWith(name: input.name, width: input.width, length: input.length),
    );
  }

  Future<void> _deleteRoom(SketchRoom room) async {
    final sure = await confirmDelete(
      context,
      title: 'Delete ${room.name}?',
      message: 'The room is removed from this sketch.',
    );
    if (!sure) return;
    setState(() => _selectedRoomId = null);
    await _controller.removeRoom(room.id);
  }

  Future<void> _onTap(HomeLayout layout, FloorPoint p) async {
    switch (_tool) {
      case SketchTool.rooms:
        setState(() => _selectedRoomId = layout.roomAt(p)?.id);
      case SketchTool.router:
        await _controller.setRouter(p);
      case SketchTool.spots:
        final label = await showSpotDialog(context);
        if (label != null) await _controller.addSpot(label, p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(sketchControllerProvider(widget.homeId));
    return Scaffold(
      appBar: AppBar(title: const Text('Sketch your rooms')),
      body: switch (layout) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => Center(
          child: Text("Couldn't load the sketch: $error"),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(HomeLayout layout) {
    final selected = layout.rooms
        .where((r) => r.id == _selectedRoomId)
        .firstOrNull;
    return SplitCanvasLayout(
      header: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<SketchTool>(
              segments: const [
                ButtonSegment(
                  value: SketchTool.rooms,
                  label: Text('Rooms'),
                  icon: Icon(Icons.crop_square),
                ),
                ButtonSegment(
                  value: SketchTool.router,
                  label: Text('Router'),
                  icon: Icon(Icons.router_outlined),
                ),
                ButtonSegment(
                  value: SketchTool.spots,
                  label: Text('Spots'),
                  icon: Icon(Icons.place_outlined),
                ),
              ],
              selected: {_tool},
              onSelectionChanged: (s) => setState(() => _tool = s.single),
            ),
          ),
          Text(_hint(layout), style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      canvas: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SketchCanvas(
              layout: layout,
              selectedRoomId: _tool == SketchTool.rooms
                  ? _selectedRoomId
                  : null,
              onTap: (p) => _onTap(layout, p),
              onRoomDrag: _tool == SketchTool.rooms
                  ? _controller.previewRoom
                  : null,
              onRoomDragEnd: _tool == SketchTool.rooms
                  ? (room) {
                      setState(() => _selectedRoomId = room.id);
                      _controller.commitRoom(room);
                    }
                  : null,
            ),
          ),
        ),
      ),
      footer: _BottomPanel(
        tool: _tool,
        layout: layout,
        selected: selected,
        onAddRoom: () => _addRoom(layout),
        onEditRoom: _editRoom,
        onDeleteRoom: _deleteRoom,
        onClearRouter: _controller.clearRouter,
        onRemoveSpot: _controller.removeSpot,
        onDone: layout.isEmpty ? null : () => Navigator.of(context).pop(true),
      ),
    );
  }

  String _hint(HomeLayout layout) => switch (_tool) {
    SketchTool.rooms when layout.isEmpty => 'Add each room as a rectangle.',
    SketchTool.rooms => 'Tap a room to select it. Drag to move it.',
    SketchTool.router => 'Tap where your router is.',
    SketchTool.spots => 'Tap places you care about, like your desk.',
  };
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.tool,
    required this.layout,
    required this.selected,
    required this.onAddRoom,
    required this.onEditRoom,
    required this.onDeleteRoom,
    required this.onClearRouter,
    required this.onRemoveSpot,
    required this.onDone,
  });

  final SketchTool tool;
  final HomeLayout layout;
  final SketchRoom? selected;
  final VoidCallback onAddRoom;
  final ValueChanged<SketchRoom> onEditRoom;
  final ValueChanged<SketchRoom> onDeleteRoom;
  final VoidCallback onClearRouter;
  final ValueChanged<int> onRemoveSpot;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final room = selected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            switch (tool) {
              SketchTool.rooms => Row(
                children: [
                  if (room != null) ...[
                    Expanded(
                      child: Text(
                        room.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit room',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEditRoom(room),
                    ),
                    IconButton(
                      tooltip: 'Delete room',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDeleteRoom(room),
                    ),
                  ] else
                    const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: onAddRoom,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add room'),
                  ),
                ],
              ),
              SketchTool.router => Row(
                children: [
                  Expanded(
                    child: Text(
                      layout.router == null
                          ? 'Router not placed'
                          : 'Router placed',
                    ),
                  ),
                  if (layout.router != null)
                    TextButton(
                      onPressed: onClearRouter,
                      child: const Text('Remove'),
                    ),
                ],
              ),
              SketchTool.spots => SizedBox(
                width: double.infinity,
                child: layout.spots.isEmpty
                    ? const Text('No spots yet')
                    : Wrap(
                        spacing: 8,
                        children: [
                          for (final s in layout.spots)
                            InputChip(
                              label: Text(s.label),
                              onDeleted: () => onRemoveSpot(s.id),
                              deleteButtonTooltipMessage: 'Remove ${s.label}',
                            ),
                        ],
                      ),
              ),
            },
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onDone, child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}
