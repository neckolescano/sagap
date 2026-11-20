import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_format.dart';
import '../../data/scan_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/scan_record.dart';
import '../common/empty_state.dart';
import '../home_shell.dart';
import '../sketch/sketch_canvas.dart';
import '../sketch/sketch_controller.dart';
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

    Widget fill(Widget child) => SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: tabContentBottomPadding(context)),
            child: Center(child: child),
          ),
        );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
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
          switch (homes) {
            AsyncData(:final value) when value.isEmpty => fill(
                EmptyState(
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
            AsyncData(:final value) => SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, tabContentBottomPadding(context)),
                sliver: SliverList.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, i) => _HomeCard(home: value[i]),
                ),
              ),
            AsyncError(:final error) => fill(
                EmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load your homes",
                  message: '$error',
                ),
              ),
            _ => fill(const CircularProgressIndicator()),
          },
        ],
      ),
    );
  }
}

/// Height of the room-sketch preview on a home card.
const double _previewHeight = 140;

/// A home as a gallery card: bold name, sketch preview, caption.
class _HomeCard extends ConsumerWidget {
  const _HomeCard({required this.home});

  final HomeSummary home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final layout = ref.watch(sketchControllerProvider(home.id)).value;
    final scans = home.scanCount == 1 ? '1 scan' : '${home.scanCount} scans';
    final last = home.lastScanAt;
    final caption = last == null ? scans : '$scans · last ${formatDate(last)}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => HomeDetailPage(homeId: home.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      home.name,
                      style: theme.textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: _previewHeight,
                child: layout == null || layout.isEmpty
                    ? Center(
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: scheme.primary.withValues(alpha: 0.15),
                          child: Icon(Icons.home_outlined, size: 36, color: scheme.primary),
                        ),
                      )
                    : IgnorePointer(
                        child: SketchCanvas(
                          layout: layout,
                          semanticLabel: 'Room sketch of ${home.name}',
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
