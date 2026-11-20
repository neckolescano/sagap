import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      body: IndexedStack(
        index: index,
        children: const [ScanPage(), MapPage(), HomesPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(selectedTabProvider.notifier).select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_find_outlined),
            selectedIcon: Icon(Icons.wifi_find),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Homes',
          ),
        ],
      ),
    );
  }
}
