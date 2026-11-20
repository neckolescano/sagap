import 'package:flutter/material.dart';

import '../../domain/home_layout.dart';

/// Values entered in the room dialog.
class RoomInput {
  const RoomInput(this.name, this.width, this.length, {this.outside = false});
  final String name;
  final double width;
  final double length;

  /// Yard, hallway or a neighbour's place (see [SketchRoom.outside]).
  final bool outside;
}

/// Longest room name accepted.
const int maxRoomNameLength = 24;

/// Default size for a new room, in meters.
const double defaultRoomSizeM = 3;

/// Asks for a room's name and size. Returns null when cancelled.
Future<RoomInput?> showRoomDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  double initialWidth = defaultRoomSizeM,
  double initialLength = defaultRoomSizeM,
  bool initialOutside = false,
}) =>
    showDialog<RoomInput>(
      context: context,
      builder: (_) => _RoomDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialName: initialName,
        initialWidth: initialWidth,
        initialLength: initialLength,
        initialOutside: initialOutside,
      ),
    );

/// Parses a size in meters, accepting a comma as decimal separator.
/// Returns null when not a number inside the allowed range.
double? parseRoomSize(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value < minRoomSizeM || value > maxRoomSizeM) return null;
  return value;
}

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialWidth,
    required this.initialLength,
    required this.initialOutside,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final double initialWidth;
  final double initialLength;
  final bool initialOutside;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  late bool _outside = widget.initialOutside;
  late final _name = TextEditingController(text: widget.initialName);
  late final _width = TextEditingController(text: _format(widget.initialWidth));
  late final _length = TextEditingController(text: _format(widget.initialLength));

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static const _sizeHint =
      '${minRoomSizeM ~/ 1}–${maxRoomSizeM ~/ 1} m';

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _length.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      parseRoomSize(_width.text) != null &&
      parseRoomSize(_length.text) != null;

  @override
  Widget build(BuildContext context) {
    String? sizeError(TextEditingController c) =>
        c.text.isEmpty || parseRoomSize(c.text) != null ? null : _sizeHint;
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.initialName.isEmpty,
              maxLength: maxRoomNameLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Room name'),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(
                      labelText: 'Width (m)',
                      errorText: sizeError(_width),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _length,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(
                      labelText: 'Length (m)',
                      errorText: sizeError(_length),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A rough size is fine. You can change it later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _outside,
              onChanged: (v) => setState(() => _outside = v),
              title: const Text('Outside my home'),
              subtitle: const Text(
                "A yard, hallway or a neighbour's place. Its walls still count, "
                "but it isn't suggested for the router and needs no minimum spots.",
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(RoomInput(
                    _name.text.trim(),
                    parseRoomSize(_width.text)!,
                    parseRoomSize(_length.text)!,
                    outside: _outside,
                  ))
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Where to place a room: [side] of [anchorId], [gapM] meters away.
class PlacementInput {
  const PlacementInput(this.anchorId, this.side, this.gapM);
  final int anchorId;
  final RoomSide side;
  final double gapM;
}

/// Parses a gap in meters (comma accepted). Null when not a number in
/// 0–[maxPlacementGapM].
double? parsePlacementGap(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value < 0 || value > maxPlacementGapM) return null;
  return value;
}

/// About one normal walking step, for pacing out a gap.
const double stepLengthM = 0.7;

String roomSideLabel(RoomSide side) => switch (side) {
      RoomSide.left => 'Left of',
      RoomSide.right => 'Right of',
      RoomSide.above => 'Above',
      RoomSide.below => 'Below',
    };

/// Asks where to put [room] relative to one of [others]. Null when cancelled.
Future<PlacementInput?> showPlaceBesideDialog(
  BuildContext context, {
  required SketchRoom room,
  required List<SketchRoom> others,
}) =>
    showDialog<PlacementInput>(
      context: context,
      builder: (_) => _PlaceBesideDialog(room: room, others: others),
    );

class _PlaceBesideDialog extends StatefulWidget {
  const _PlaceBesideDialog({required this.room, required this.others});

  final SketchRoom room;
  final List<SketchRoom> others;

  @override
  State<_PlaceBesideDialog> createState() => _PlaceBesideDialogState();
}

class _PlaceBesideDialogState extends State<_PlaceBesideDialog> {
  late int _anchorId = widget.others.first.id;
  RoomSide _side = RoomSide.right;
  final _gap = TextEditingController(text: '0');

  @override
  void dispose() {
    _gap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gap = parsePlacementGap(_gap.text);
    return AlertDialog(
      title: Text('Place ${widget.room.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<RoomSide>(
              initialValue: _side,
              decoration: const InputDecoration(labelText: 'Side'),
              items: [
                for (final s in RoomSide.values)
                  DropdownMenuItem(value: s, child: Text(roomSideLabel(s))),
              ],
              onChanged: (s) => setState(() => _side = s ?? _side),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _anchorId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Room'),
              items: [
                for (final r in widget.others)
                  DropdownMenuItem(
                    value: r.id,
                    child: Text(r.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _anchorId = id ?? _anchorId),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gap,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Gap between them (m)',
                errorText: _gap.text.isEmpty || gap != null
                    ? null
                    : '0–${maxPlacementGapM ~/ 1} m',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              'No tape? One normal step is about ${stepLengthM.toStringAsFixed(1)} m. '
              'Use 0 if they share a wall.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: gap == null
              ? null
              : () => Navigator.of(context).pop(PlacementInput(_anchorId, _side, gap)),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: const Text('Place'),
        ),
      ],
    );
  }
}

/// Suggested priority-spot labels (SPEC.md §9, notes feature 3).
const List<String> spotSuggestions = ['Desk', 'TV', 'Bed', 'Sofa'];

/// Longest spot label accepted.
const int maxSpotLabelLength = 20;

/// Asks for a priority spot's label. Returns null when cancelled.
Future<String?> showSpotDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _SpotDialog());

class _SpotDialog extends StatefulWidget {
  const _SpotDialog();

  @override
  State<_SpotDialog> createState() => _SpotDialogState();
}

class _SpotDialogState extends State<_SpotDialog> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What is here?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final s in spotSuggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () => setState(() => _label.text = s),
                ),
            ],
          ),
          TextField(
            controller: _label,
            maxLength: maxSpotLabelLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _label.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_label.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
