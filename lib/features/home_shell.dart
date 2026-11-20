import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common/floating_nav_bar.dart';
import 'homes/homes_page.dart';
import 'map/map_page.dart';
import 'scan/ar_controller.dart';
import 'scan/channel_check_controller.dart';
import 'scan/manual_controller.dart';
import 'scan/scan_controller.dart';
import 'scan/scan_page.dart';

/// Selected bottom tab: 0 Scan, 1 Map, 2 Homes.
class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<SelectedTab, int>(SelectedTab.new);

/// Bottom-tab shell: Scan · Map · Homes (SPEC.md §4).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen here, on an always-visible widget, so a scan keeps recording and
    // the timeline keeps filling while another tab is open.
    ref.listen(scanControllerProvider, (_, _) {});
    ref.listen(signalHistoryProvider, (_, _) {});
    ref.listen(arModeProvider, (_, _) {});
    ref.listen(pathTrackProvider, (_, _) {});
    ref.listen(manualHomeProvider, (_, _) {});
    ref.listen(manualCaptureProvider, (_, _) {});
    ref.listen(channelCheckProvider, (_, _) {});
    final index = ref.watch(selectedTabProvider);

    return Scaffold(
      // Content scrolls under the floating bar; pages keep
      // [floatingNavClearance] at the bottom so nothing ends up hidden.
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: const [ScanPage(), MapPage(), HomesPage()],
      ),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: index,
        onSelected: ref.read(selectedTabProvider.notifier).select,
        items: const [
          FloatingNavItem(
            icon: Icons.wifi_find_outlined,
            selectedIcon: Icons.wifi_find,
            label: 'Scan',
          ),
          FloatingNavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: 'Map',
          ),
          FloatingNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Homes',
          ),
        ],
      ),
    );
  }
}
