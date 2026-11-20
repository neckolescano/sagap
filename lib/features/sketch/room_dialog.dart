import 'package:flutter/material.dart';

import '../../domain/home_layout.dart';

/// Values entered in the room dialog.
class RoomInput {
  const RoomInput(this.name, this.width, this.length);
  final String name;
  final double width;
  final double length;
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
}) =>
    showDialog<RoomInput>(
      context: context,
      builder: (_) => _RoomDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialName: initialName,
        initialWidth: initialWidth,
        initialLength: initialLength,
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
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final double initialWidth;
  final double initialLength;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
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
                  ))
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: Text(widget.confirmLabel),
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
