import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_controller.dart';
import '../onboarding/onboarding_controller.dart';
import 'settings_sections.dart';

/// Settings (part of S13): theme, guide replay and privacy note.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _options = [
    (ThemeMode.dark, 'Dark'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.system, 'Match system'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(title: Text('Theme')),
          RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).select(value);
              }
            },
            child: Column(
              children: [
                for (final (value, label) in _options)
                  RadioListTile<ThemeMode>(value: value, title: Text(label)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Show the guide again'),
            onTap: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              ref.read(onboardingDoneProvider.notifier).replay();
            },
          ),
          const Divider(),
          const PermissionsSection(),
          const SizedBox(height: 8),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Privacy'),
            subtitle: Text(
              'Scans stay on this phone. Sagap has no account and never uploads '
              'anything. A report leaves the phone only when you tap Share '
              'and pick an app. Wi-Fi network names are never saved or shown.',
            ),
          ),
          const DeleteAllDataTile(),
        ],
      ),
    );
  }
}
