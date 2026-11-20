import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../platform/ar_bridge.dart';
import '../ar_controller.dart';
import 'ar_camera_view.dart';

/// Camera preview with a tracking banner (S4). Mounted only during an AR scan.
class ArCameraCard extends ConsumerWidget {
  const ArCameraCard({super.key});

  static const double _height = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pose = ref.watch(poseStreamProvider);
    final builder = ref.watch(arCameraBuilderProvider);

    final String? banner = switch (pose) {
      AsyncData(:final value) => trackingMessage(value),
      AsyncError(:final error) => _errorMessage(error),
      _ => 'Starting the camera…',
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(cardRadius),
      child: SizedBox(
        height: _height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(child: Builder(builder: builder)),
            if (banner != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Text(
                      banner,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _errorMessage(Object error) {
    final code = error is PlatformException ? error.code : null;
    return switch (code) {
      'camera_permission' => 'Camera not allowed. Recording signal only.',
      'camera_unavailable' => 'The camera is in use by another app.',
      'ar_unavailable' => "AR couldn't start on this phone.",
      _ => "AR couldn't start.",
    };
  }
}
