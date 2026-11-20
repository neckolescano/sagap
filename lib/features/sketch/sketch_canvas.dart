import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/signal/signal_quality.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/home_layout.dart';
import '../../domain/path_track.dart';

/// Smallest area shown, in meters, so one small room isn't blown up.
const double _minViewSpanM = 6;

/// Margin around the content, in meters.
const double _viewPaddingM = 1;

/// Maps sketch meters to canvas pixels: uniform scale, content centred.
class SketchTransform {
  SketchTransform.fit(HomeLayout layout, Size size, {Iterable<FloorPoint> extra = const []}) {
    final xs = <double>[];
    final ys = <double>[];
    for (final r in layout.rooms) {
      xs.addAll([r.x, r.x + r.width]);
      ys.addAll([r.y, r.y + r.length]);
    }
    for (final p in [?layout.router, ...layout.spots.map((s) => s.point), ...extra]) {
      xs.add(p.x);
      ys.add(p.y);
    }
    final minX = xs.isEmpty ? 0.0 : xs.reduce(math.min);
    final maxX = xs.isEmpty ? 0.0 : xs.reduce(math.max);
    final minY = ys.isEmpty ? 0.0 : ys.reduce(math.min);
    final maxY = ys.isEmpty ? 0.0 : ys.reduce(math.max);
    final spanX = math.max(_minViewSpanM, maxX - minX + 2 * _viewPaddingM);
    final spanY = math.max(_minViewSpanM, maxY - minY + 2 * _viewPaddingM);
    pxPerM = math.min(size.width / spanX, size.height / spanY);
    _centerM = FloorPoint((minX + maxX) / 2, (minY + maxY) / 2);
    _centerPx = size.center(Offset.zero);
  }

  late final double pxPerM;
  late final FloorPoint _centerM;
  late final Offset _centerPx;

  Offset toPx(FloorPoint p) =>
      _centerPx + Offset((p.x - _centerM.x) * pxPerM, (p.y - _centerM.y) * pxPerM);

  FloorPoint toMeters(Offset px) => FloorPoint(
        _centerM.x + (px.dx - _centerPx.dx) / pxPerM,
        _centerM.y + (px.dy - _centerPx.dy) / pxPerM,
      );
}

/// A recorded manual spot, drawn as a dot in its band colour.
class SketchPoint {
  const SketchPoint(this.point, this.rssiDbm);
  final FloorPoint point;
  final int rssiDbm;
}

/// Draws a home sketch and reports taps and room drags in meters.
///
/// The transform is frozen during a drag so the view doesn't rescale under
/// the finger.
class SketchCanvas extends StatefulWidget {
  const SketchCanvas({
    super.key,
    required this.layout,
    this.selectedRoomId,
    this.points = const [],
    this.marker,
    this.onTap,
    this.onRoomDrag,
    this.onRoomDragEnd,
    this.semanticLabel = 'Room sketch',
    this.fixedTransform,
    this.transparentRooms = false,
    this.labelledPins = const [],
  });

  /// Lettered pins (hotspot candidates A, B, C).
  final List<(FloorPoint, String)> labelledPins;

  /// Use this transform instead of fitting the layout (heatmap overlay).
  final SketchTransform? fixedTransform;

  /// Draw room outlines and labels only, so a heatmap shows through.
  final bool transparentRooms;

  final HomeLayout layout;
  final int? selectedRoomId;
  final List<SketchPoint> points;

  /// "You are here" marker during a manual scan.
  final FloorPoint? marker;

  final ValueChanged<FloorPoint>? onTap;

  /// Called with the room moved by the drag so far (not snapped).
  final ValueChanged<SketchRoom>? onRoomDrag;
  final ValueChanged<SketchRoom>? onRoomDragEnd;
  final String semanticLabel;

  @override
  State<SketchCanvas> createState() => _SketchCanvasState();
}

class _SketchCanvasState extends State<SketchCanvas> {
  SketchTransform? _frozen;
  SketchRoom? _dragRoom;
  Offset _dragTotal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final transform = _frozen ??
            widget.fixedTransform ??
            SketchTransform.fit(
              widget.layout,
              size,
              extra: [
                ?widget.marker,
                ...widget.points.map((p) => p.point),
                ...widget.labelledPins.map((p) => p.$1),
              ],
            );
        return Semantics(
          label: widget.semanticLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.onTap == null
                ? null
                : (d) => widget.onTap!(transform.toMeters(d.localPosition)),
            onPanStart: widget.onRoomDrag == null
                ? null
                : (d) {
                    final room = widget.layout.roomAt(transform.toMeters(d.localPosition));
                    if (room == null) return;
                    setState(() {
                      _frozen = transform;
                      _dragRoom = room;
                      _dragTotal = Offset.zero;
                    });
                  },
            onPanUpdate: widget.onRoomDrag == null
                ? null
                : (d) {
                    final room = _dragRoom;
                    if (room == null) return;
                    _dragTotal += d.delta;
                    widget.onRoomDrag!(_moved(room, transform));
                  },
            onPanEnd: widget.onRoomDrag == null
                ? null
                : (_) {
                    final room = _dragRoom;
                    if (room != null) widget.onRoomDragEnd?.call(_moved(room, transform));
                    setState(() {
                      _frozen = null;
                      _dragRoom = null;
                    });
                  },
            child: CustomPaint(
              size: size,
              painter: _SketchPainter(
                layout: widget.layout,
                transform: transform,
                selectedRoomId: widget.selectedRoomId,
                points: widget.points,
                marker: widget.marker,
                labelledPins: widget.labelledPins,
                colors: _SketchColors(
                  grid: scheme.outlineVariant.withValues(alpha: 0.5),
                  roomFill: widget.transparentRooms
                      ? Colors.transparent
                      : scheme.surfaceContainerHigh,
                  roomLine: scheme.onSurfaceVariant,
                  selected: scheme.primary,
                  text: scheme.onSurface,
                  muted: scheme.onSurfaceVariant,
                  router: scheme.primary,
                  spot: AppColors.weak,
                ),
                textStyle: Theme.of(context).textTheme.labelMedium!,
              ),
            ),
          ),
        );
      },
    );
  }

  SketchRoom _moved(SketchRoom room, SketchTransform t) => room.copyWith(
        x: room.x + _dragTotal.dx / t.pxPerM,
        y: room.y + _dragTotal.dy / t.pxPerM,
      );
}

class _SketchColors {
  const _SketchColors({
    required this.grid,
    required this.roomFill,
    required this.roomLine,
    required this.selected,
    required this.text,
    required this.muted,
    required this.router,
    required this.spot,
  });

  final Color grid;
  final Color roomFill;
  final Color roomLine;
  final Color selected;
  final Color text;
  final Color muted;
  final Color router;
  final Color spot;
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.layout,
    required this.transform,
    required this.selectedRoomId,
    required this.points,
    required this.marker,
    required this.labelledPins,
    required this.colors,
    required this.textStyle,
  });

  final HomeLayout layout;
  final SketchTransform transform;
  final int? selectedRoomId;
  final List<SketchPoint> points;
  final FloorPoint? marker;
  final List<(FloorPoint, String)> labelledPins;
  final _SketchColors colors;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size);
    for (final room in layout.rooms) {
      _room(canvas, room);
    }
    for (final p in points) {
      final o = transform.toPx(p.point);
      canvas.drawCircle(o, 7, Paint()..color = AppColors.forQuality(signalQualityFor(p.rssiDbm)));
      canvas.drawCircle(
        o,
        7,
        Paint()
          ..color = colors.text.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    for (final spot in layout.spots) {
      _spot(canvas, spot);
    }
    if (layout.router case final router?) _router(canvas, router);
    for (final (p, label) in labelledPins) {
      final o = transform.toPx(p);
      canvas.drawCircle(o, 14, Paint()..color = colors.selected);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: textStyle.copyWith(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, o - Offset(painter.width / 2, painter.height / 2));
    }
    if (marker case final m?) _marker(canvas, m);
  }

  void _grid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    final topLeft = transform.toMeters(Offset.zero);
    final bottomRight = transform.toMeters(Offset(size.width, size.height));
    for (var m = topLeft.x.ceilToDouble(); m <= bottomRight.x; m++) {
      final x = transform.toPx(FloorPoint(m, 0)).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var m = topLeft.y.ceilToDouble(); m <= bottomRight.y; m++) {
      final y = transform.toPx(FloorPoint(0, m)).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _room(Canvas canvas, SketchRoom room) {
    final rect = Rect.fromPoints(
      transform.toPx(FloorPoint(room.x, room.y)),
      transform.toPx(FloorPoint(room.x + room.width, room.y + room.length)),
    );
    final selected = room.id == selectedRoomId;
    canvas.drawRect(rect, Paint()..color = colors.roomFill.withValues(alpha: 0.85));
    canvas.drawRect(
      rect,
      Paint()
        ..color = selected ? colors.selected : colors.roomLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2,
    );
    _label(
      canvas,
      '${room.name}\n${_m(room.width)} × ${_m(room.length)} m',
      rect.center,
      maxWidth: rect.width - 8,
      color: colors.text,
    );
  }

  void _router(Canvas canvas, FloorPoint p) {
    final o = transform.toPx(p);
    canvas.drawCircle(o, 12, Paint()..color = colors.router);
    final arc = Paint()
      ..color = colors.router
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 2; i++) {
      canvas.drawArc(Rect.fromCircle(center: o, radius: 12.0 + i * 7), 3.8, 1.65, false, arc);
    }
    _label(canvas, 'Router', o + const Offset(0, 24), maxWidth: 80, color: colors.text);
  }

  void _spot(Canvas canvas, PrioritySpot spot) {
    final o = transform.toPx(spot.point);
    final path = Path()
      ..moveTo(o.dx, o.dy - 10)
      ..lineTo(o.dx + 9, o.dy)
      ..lineTo(o.dx, o.dy + 10)
      ..lineTo(o.dx - 9, o.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = colors.spot);
    _label(canvas, spot.label, o + const Offset(0, 20), maxWidth: 90, color: colors.text);
  }

  void _marker(Canvas canvas, FloorPoint p) {
    final o = transform.toPx(p);
    canvas.drawCircle(o, 16, Paint()..color = colors.selected.withValues(alpha: 0.25));
    canvas.drawCircle(o, 8, Paint()..color = colors.selected);
    canvas.drawCircle(
      o,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _label(Canvas canvas, String text, Offset center,
      {required double maxWidth, required Color color}) {
    if (maxWidth <= 10) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle.copyWith(color: color)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  static String _m(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(_SketchPainter old) =>
      old.layout != layout ||
      old.selectedRoomId != selectedRoomId ||
      old.points != points ||
      old.marker != marker ||
      old.labelledPins != labelledPins ||
      old.transform != transform;
}
