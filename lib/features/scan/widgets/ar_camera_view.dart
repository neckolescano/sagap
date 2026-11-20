import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native view type registered in MainActivity.
const String arCameraViewType = 'sagap/ar_camera';

/// ARCore camera preview via Hybrid Composition (SPEC.md §2). Mounting it
/// starts the AR session; unmounting closes it.
class ArCameraView extends StatelessWidget {
  const ArCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: arCameraViewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) => PlatformViewsService.initExpensiveAndroidView(
        id: params.id,
        viewType: arCameraViewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: const StandardMessageCodec(),
        onFocus: () => params.onFocusChanged(true),
      )
        ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
        ..create(),
    );
  }
}

/// Builds the camera preview. Widget tests override it, since platform views
/// do not exist in the test environment.
final arCameraBuilderProvider =
    Provider<WidgetBuilder>((ref) => (_) => const ArCameraView());
