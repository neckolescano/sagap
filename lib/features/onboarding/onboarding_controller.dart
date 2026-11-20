import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';

/// Whether the first-run guide has been completed or skipped.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(initialSettingsProvider)[SettingsKeys.onboardingDone] == 'true';

  Future<void> complete() async {
    state = true;
    await ref.read(settingsStoreProvider).write(SettingsKeys.onboardingDone, 'true');
  }

  /// Shows the guide again (from Settings).
  Future<void> replay() async {
    state = false;
    await ref.read(settingsStoreProvider).write(SettingsKeys.onboardingDone, 'false');
  }
}

final onboardingDoneProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
