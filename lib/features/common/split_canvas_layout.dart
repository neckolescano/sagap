import 'package:flutter/material.dart';

/// Share of the screen the header / footer may use before they scroll.
const double _maxHeaderShare = 0.25;
const double _maxFooterShare = 0.35;

/// Header, canvas, footer. With large text the header and footer scroll
/// inside their own share of the screen, so the canvas always keeps space
/// and keeps its own drag gestures (a whole-page scroll would steal them).
class SplitCanvasLayout extends StatelessWidget {
  const SplitCanvasLayout({
    super.key,
    required this.header,
    required this.canvas,
    required this.footer,
  });

  final Widget header;
  final Widget canvas;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * _maxHeaderShare),
              child: SingleChildScrollView(child: header),
            ),
            Expanded(child: canvas),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * _maxFooterShare),
              child: SingleChildScrollView(child: footer),
            ),
          ],
        );
      },
    );
  }
}
