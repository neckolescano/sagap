import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../data/scan_repository.dart';
import '../../domain/scan_record.dart';
import '../common/empty_state.dart';
import '../home_shell.dart';
import 'home_detail_page.dart';
import 'settings_page.dart';

/// Homes tab (S12): saved homes, newest activity first.
class HomesPage extends ConsumerWidget {
  const HomesPage({super.key});

  static const int _scanTab = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homes = ref.watch(homesProvider);
    void goScan() => ref.read(selectedTabProvider.notifier).select(_scanTab);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homes'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: switch (homes) {
        AsyncData(:final value) when value.isEmpty => Center(
            child: SingleChildScrollView(
              child: EmptyState(
                icon: Icons.home_outlined,
                title: 'No homes yet',
                message: 'Homes you scan are saved here, only on this phone.',
                action: FilledButton.icon(
                  onPressed: goScan,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Start a scan'),
                ),
              ),
            ),
          ),
        AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _HomeCard(home: value[i]),
          ),
        AsyncError(:final error) => Center(
            child: EmptyState(
              icon: Icons.error_outline,
              title: "Couldn't load your homes",
              message: '$error',
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.home});

  final HomeSummary home;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scans = home.scanCount == 1 ? '1 scan' : '${home.scanCount} scans';
    final last = home.lastScanAt;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.home_outlined, color: scheme.primary),
        ),
        title: Text(home.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(last == null ? scans : '$scans · last ${formatDate(last)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => HomeDetailPage(homeId: home.id)),
        ),
      ),
    );
  }
}
