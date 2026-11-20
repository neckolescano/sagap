import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/home_shell.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/onboarding/onboarding_page.dart';

class SagapApp extends ConsumerWidget {
  const SagapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingDone = ref.watch(onboardingDoneProvider);
    return MaterialApp(
      title: 'Sagap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: onboardingDone ? const HomeShell() : const OnboardingPage(),
    );
  }
}
