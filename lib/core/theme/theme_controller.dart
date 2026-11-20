import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';

/// Selected theme mode, saved on the phone. Dark is the default (SPEC.md §11).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.read(initialSettingsProvider)[SettingsKeys.themeMode];
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.dark;
  }

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsStoreProvider).write(SettingsKeys.themeMode, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
