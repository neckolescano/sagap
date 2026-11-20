import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_controller.dart';
import 'onboarding_illustrations.dart';

/// First-run guide in 3 illustrated steps (S1, SPEC.md §4).
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;

  static const _steps = [
    (
      'Start at your router',
      'Stand next to your Wi-Fi router and press Start. Sagap reads your '
          'signal about once a second.',
    ),
    (
      'Walk every room',
      'Hold your phone at chest height and walk slowly through each room, '
          'including the spots you care about, like your desk or TV.',
    ),
    (
      'Get your fixes',
      'See where the signal is weak and get suggestions ranked by cost, '
          'free ones first. Everything stays on this phone.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _done() => ref.read(onboardingDoneProvider.notifier).complete();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLast = _index == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Visibility(
                  visible: !isLast,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: TextButton(
                    onPressed: _done,
                    child: const Text('Skip'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final (title, body) = _steps[i];
                  // Scrolls with large text; centred when it fits.
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox(
                                height: 240,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: _illustration(i, scheme),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Step ${i + 1} of ${_steps.length}',
                              style: textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              body,
                              textAlign: TextAlign.center,
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _Dots(count: _steps.length, index: _index),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast
                      ? _done
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                  child: Text(isLast ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  CustomPainter _illustration(int i, ColorScheme scheme) => switch (i) {
    0 => RouterIllustration(accent: scheme.primary, ink: scheme.onSurface),
    1 => WalkIllustration(ink: scheme.onSurfaceVariant),
    _ => FixesIllustration(
      card: scheme.surfaceContainerHigh,
      ink: scheme.onSurface,
      accent: scheme.primary,
    ),
  };
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Step ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
