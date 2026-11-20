import 'package:flutter/material.dart';

import '../../domain/scan_record.dart';

/// Where to save a scan: an existing home, or a new one by name.
sealed class HomeChoice {
  const HomeChoice();
}

class ExistingHome extends HomeChoice {
  const ExistingHome(this.homeId);
  final int homeId;
}

class NewHome extends HomeChoice {
  const NewHome(this.name);
  final String name;
}

/// Name suggested for the first home.
const String defaultHomeName = 'My home';

/// Longest home name accepted.
const int maxHomeNameLength = 40;

/// Asks which home to use. Returns null when cancelled.
Future<HomeChoice?> showSaveScanDialog(
  BuildContext context,
  List<HomeSummary> homes, {
  String title = 'Save scan to',
  String confirmLabel = 'Save',
}) =>
    showDialog<HomeChoice>(
      context: context,
      builder: (_) => _SaveScanDialog(
        homes: homes,
        title: title,
        confirmLabel: confirmLabel,
      ),
    );

class _SaveScanDialog extends StatefulWidget {
  const _SaveScanDialog({
    required this.homes,
    required this.title,
    required this.confirmLabel,
  });

  final List<HomeSummary> homes;
  final String title;
  final String confirmLabel;

  @override
  State<_SaveScanDialog> createState() => _SaveScanDialogState();
}

class _SaveScanDialogState extends State<_SaveScanDialog> {
  /// Selected home id, or null for "New home".
  late int? _selected = widget.homes.isEmpty ? null : widget.homes.first.id;
  late final _name = TextEditingController(
    text: widget.homes.isEmpty ? defaultHomeName : '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _selected != null || _name.text.trim().isNotEmpty;

  void _save() {
    final selected = _selected;
    Navigator.of(context).pop(
      selected != null ? ExistingHome(selected) : NewHome(_name.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: RadioGroup<int?>(
          groupValue: _selected,
          onChanged: (value) => setState(() => _selected = value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final home in widget.homes)
                RadioListTile<int?>(
                  value: home.id,
                  title: Text(home.name),
                  contentPadding: EdgeInsets.zero,
                ),
              if (widget.homes.isNotEmpty)
                const RadioListTile<int?>(
                  value: null,
                  title: Text('New home'),
                  contentPadding: EdgeInsets.zero,
                ),
              if (_selected == null)
                TextField(
                  controller: _name,
                  autofocus: widget.homes.isNotEmpty,
                  maxLength: maxHomeNameLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Home name'),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _save : null,
          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Asks before deleting something that cannot be recovered.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 48),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
