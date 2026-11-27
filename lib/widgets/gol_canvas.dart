import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/gol_engine.dart';
import '../engine/gol_models.dart';

/// Interactive Game of Life viewport with multi-touch pan/zoom, stroke-locked
/// Bresenham drawing, stamp ghost preview, crop selection, and keyboard/mouse
/// shortcuts.
class GolCanvas extends StatefulWidget {
  final VoidCallback onToggleFullscreen;
  final ValueChanged<Size>? onViewportChanged;
  final VoidCallback? onTapWhenInspectorOpen;
  final bool inspectorOpen;
  final VoidCallback? onSaveCropRequested;

  const GolCanvas({
    super.key,
    required this.onToggleFullscreen,
    this.onViewportChanged,
    this.onTapWhenInspectorOpen,
    this.inspectorOpen = false,
    this.onSaveCropRequested,
  });

  @override
  State<GolCanvas> createState() => _GolCanvasState();
}

class _GolCanvasState extends State<GolCanvas> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'GolCanvasFocus');
  final Map<int, Offset> _pointers = <int, Offset>{};

  Size _lastViewport = Size.zero;

  // Single-pointer gesture state
  int? _primaryPointerId;
  Offset _downPos = Offset.zero;
  int _downButtons = 0;
  bool _moved = false;
  bool _longPressFired = false;
  bool _wasMultiTouch = false;
  Timer? _longPressTimer;

  // Draw stroke state
  bool _drawValue = true;
  (int, int)? _lastDrawCell;

  // Crop drag state
  (int, int)? _cropAnchor;

  // Stamp hover/drag cell
  (int, int)? _stampHoverCell;

  // Multi-touch pinch/pan state
  Offset _prevPinchFocal = Offset.zero;
  double _prevPinchSpan = 0.0;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _reportViewport(Size size) {
    if (size == _lastViewport || size.isEmpty) return;
    _lastViewport = size;
    final ValueChanged<Size>? callback = widget.onViewportChanged;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          callback(size);
        }
      });
    }
  }

  (int, int) _screenToCell(GolEngine engine, Offset localPos) {
    final Offset world = engine.screenToWorld(localPos, _lastViewport);
    return (world.dx.floor(), world.dy.floor());
  }

  bool _isPanMouseButton(int buttons) =>
      (buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0;

  void _startLongPressTimer(GolEngine engine) {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      if (_pointers.length == 1 && !_moved && !_wasMultiTouch) {
        _longPressFired = true;
        if (engine.hapticsEnabled) {
          HapticFeedback.mediumImpact();
        }
        widget.onToggleFullscreen();
      }
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _initPinch() {
    final List<Offset> pts = _pointers.values.take(2).toList(growable: false);
    if (pts.length < 2) return;
    _prevPinchFocal = (pts[0] + pts[1]) * 0.5;
    _prevPinchSpan = (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent event, GolEngine engine) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length == 1) {
      _primaryPointerId = event.pointer;
      _downPos = event.localPosition;
      _downButtons = event.buttons;
      _moved = false;
      _longPressFired = false;
      _wasMultiTouch = false;
      _lastDrawCell = null;
      _cropAnchor = null;

      if (engine.activeTool == CanvasTool.stamp) {
        setState(() {
          _stampHoverCell = _screenToCell(engine, event.localPosition);
        });
      }

      if (!_isPanMouseButton(event.buttons)) {
        _startLongPressTimer(engine);
      }
    } else {
      // 2+ pointers always transition cleanly into pinch-zoom & pan.
      _cancelLongPressTimer();
      _wasMultiTouch = true;
      _lastDrawCell = null;
      _cropAnchor = null;
      _initPinch();
    }
  }

  void _onPointerMove(PointerMoveEvent event, GolEngine engine) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      final List<Offset> pts = _pointers.values.take(2).toList(growable: false);
      final Offset focal = (pts[0] + pts[1]) * 0.5;
      final double span = (pts[0] - pts[1]).distance;

      final Offset panDelta = focal - _prevPinchFocal;
      if (panDelta != Offset.zero) {
        engine.panByPixels(panDelta);
      }
      if (_prevPinchSpan > 10.0 && span > 10.0) {
        final double scale = span / _prevPinchSpan;
        if ((scale - 1.0).abs() > 1e-4) {
          engine.zoomAtFocalPoint(scale, focal, _lastViewport);
        }
      }
      _prevPinchFocal = focal;
      _prevPinchSpan = span;
      return;
    }

    if (_wasMultiTouch || _longPressFired || event.pointer != _primaryPointerId) {
      return;
    }

    final double distFromDown = (event.localPosition - _downPos).distance;
    final bool forcePan = _isPanMouseButton(_downButtons) ||
        _isPanMouseButton(event.buttons);

    if (!_moved && distFromDown > 6.0) {
      _moved = true;
      _cancelLongPressTimer();

      if (forcePan || engine.activeTool == CanvasTool.pan) {
        engine.panByPixels(event.localPosition - _downPos);
      } else if (engine.activeTool == CanvasTool.draw) {
        final (int sx, int sy) = _screenToCell(engine, _downPos);
        final (int cx, int cy) = _screenToCell(engine, event.localPosition);
        _drawValue = !engine.grid.getCell(sx, sy);
        engine.pushUndo();
        _drawBresenhamLine(engine, sx, sy, cx, cy, _drawValue);
        _lastDrawCell = (cx, cy);
      } else if (engine.activeTool == CanvasTool.crop) {
        final (int sx, int sy) = _screenToCell(engine, _downPos);
        final (int cx, int cy) = _screenToCell(engine, event.localPosition);
        _cropAnchor = (sx, sy);
        engine.setCropRect(sx, sy, cx, cy);
      } else if (engine.activeTool == CanvasTool.stamp) {
        setState(() {
          _stampHoverCell = _screenToCell(engine, event.localPosition);
        });
      }
      return;
    }

    if (!_moved) return;

    if (forcePan || engine.activeTool == CanvasTool.pan) {
      engine.panByPixels(event.delta);
    } else if (engine.activeTool == CanvasTool.draw) {
      final (int cx, int cy) = _screenToCell(engine, event.localPosition);
      if (_lastDrawCell != null && _lastDrawCell != (cx, cy)) {
        _drawBresenhamLine(
          engine,
          _lastDrawCell!.$1,
          _lastDrawCell!.$2,
          cx,
          cy,
          _drawValue,
        );
        _lastDrawCell = (cx, cy);
      }
    } else if (engine.activeTool == CanvasTool.crop) {
      final (int cx, int cy) = _screenToCell(engine, event.localPosition);
      if (_cropAnchor != null) {
        engine.setCropRect(_cropAnchor!.$1, _cropAnchor!.$2, cx, cy);
      }
    } else if (engine.activeTool == CanvasTool.stamp) {
      final (int cx, int cy) = _screenToCell(engine, event.localPosition);
      if (_stampHoverCell != (cx, cy)) {
        setState(() {
          _stampHoverCell = (cx, cy);
        });
      }
    }
  }

  void _onPointerUp(PointerUpEvent event, GolEngine engine) {
    _pointers.remove(event.pointer);

    if (_pointers.length == 1) {
      // Transitioning down from multi-touch: keep _wasMultiTouch true until all
      // fingers lift so lifting the final finger does not trigger a tap/draw.
      return;
    }

    if (_pointers.isEmpty) {
      _cancelLongPressTimer();
      final bool isQuickTap =
          !_moved && !_longPressFired && !_wasMultiTouch && !_isPanMouseButton(_downButtons);

      if (isQuickTap) {
        if (widget.inspectorOpen && widget.onTapWhenInspectorOpen != null) {
          widget.onTapWhenInspectorOpen!();
        } else if (engine.activeTool == CanvasTool.draw) {
          final (int cx, int cy) = _screenToCell(engine, event.localPosition);
          engine.pushUndo();
          engine.setCell(cx, cy, !engine.grid.getCell(cx, cy));
          if (engine.hapticsEnabled) {
            HapticFeedback.selectionClick();
          }
        } else if (engine.activeTool == CanvasTool.stamp) {
          final (int cx, int cy) = _screenToCell(engine, event.localPosition);
          _stampHoverCell = (cx, cy);
          engine.stampAt(cx, cy);
          if (engine.hapticsEnabled) {
            HapticFeedback.lightImpact();
          }
        }
      } else if (!_wasMultiTouch &&
          !_longPressFired &&
          engine.activeTool == CanvasTool.stamp &&
          _moved) {
        // Released after dragging stamp ghost into position: stamp it there.
        final (int cx, int cy) = _screenToCell(engine, event.localPosition);
        _stampHoverCell = (cx, cy);
        engine.stampAt(cx, cy);
        if (engine.hapticsEnabled) {
          HapticFeedback.lightImpact();
        }
      }

      _primaryPointerId = null;
      _moved = false;
      _longPressFired = false;
      _wasMultiTouch = false;
      _lastDrawCell = null;
      _cropAnchor = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _cancelLongPressTimer();
      _primaryPointerId = null;
      _moved = false;
      _longPressFired = false;
      _wasMultiTouch = false;
      _lastDrawCell = null;
      _cropAnchor = null;
    }
  }

  void _onPointerHover(PointerHoverEvent event, GolEngine engine) {
    if (engine.activeTool != CanvasTool.stamp) return;
    final (int cx, int cy) = _screenToCell(engine, event.localPosition);
    if (_stampHoverCell != (cx, cy)) {
      setState(() {
        _stampHoverCell = (cx, cy);
      });
    }
  }

  void _onPointerSignal(PointerSignalEvent event, GolEngine engine) {
    if (event is PointerScrollEvent && !_lastViewport.isEmpty) {
      final double factor = math.exp(-event.scrollDelta.dy * 0.0018);
      engine.zoomAtFocalPoint(factor, event.localPosition, _lastViewport);
    }
  }

  /// Bresenham integer line rasterization so fast touch/mouse swipes never
  /// skip cells between move events.
  void _drawBresenhamLine(
    GolEngine engine,
    int x0,
    int y0,
    int x1,
    int y1,
    bool alive,
  ) {
    int dx = (x1 - x0).abs();
    int dy = -(y1 - y0).abs();
    final int sx = x0 < x1 ? 1 : -1;
    final int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    int x = x0;
    int y = y0;
    while (true) {
      if (x == x1 && y == y1) {
        engine.setCell(x, y, alive);
        break;
      }
      engine.grid.setCell(x, y, alive);
      final int e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, GolEngine engine) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;
    final bool isShift = HardwareKeyboard.instance.isShiftPressed;
    final Offset center = Offset(
      _lastViewport.width * 0.5,
      _lastViewport.height * 0.5,
    );
    const double panStep = 48.0;

    if (key == LogicalKeyboardKey.space) {
      engine.togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      engine.stepOnce();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      engine.setActiveTool(CanvasTool.draw);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      engine.setActiveTool(CanvasTool.pan);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      engine.setShowGridLines(!engine.showGridLines);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      engine.clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      engine.randomizeViewport(_lastViewport);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      engine.fitToContent(_lastViewport);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        engine.redo();
      } else {
        engine.undo();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      engine.zoomAtFocalPoint(1.25, center, _lastViewport);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      engine.zoomAtFocalPoint(0.8, center, _lastViewport);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      engine.panByPixels(const Offset(0, panStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      engine.panByPixels(const Offset(0, -panStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      engine.panByPixels(const Offset(panStep, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      engine.panByPixels(const Offset(-panStep, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (engine.activeTool == CanvasTool.stamp ||
          engine.activeTool == CanvasTool.crop) {
        engine.setActiveTool(CanvasTool.draw);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter &&
        engine.activeTool == CanvasTool.crop &&
        widget.onSaveCropRequested != null) {
      widget.onSaveCropRequested!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, KeyEvent event) => _handleKeyEvent(event, engine),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size viewport = constraints.biggest;
          _reportViewport(viewport);

          return MouseRegion(
            cursor: switch (engine.activeTool) {
              CanvasTool.pan => SystemMouseCursors.grab,
              CanvasTool.crop => SystemMouseCursors.precise,
              CanvasTool.stamp => SystemMouseCursors.cell,
              CanvasTool.draw => SystemMouseCursors.basic,
            },
            onExit: (_) {
              if (_stampHoverCell != null) {
                setState(() => _stampHoverCell = null);
              }
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent e) => _onPointerDown(e, engine),
              onPointerMove: (PointerMoveEvent e) => _onPointerMove(e, engine),
              onPointerUp: (PointerUpEvent e) => _onPointerUp(e, engine),
              onPointerCancel: _onPointerCancel,
              onPointerHover: (PointerHoverEvent e) =>
                  _onPointerHover(e, engine),
              onPointerSignal: (PointerSignalEvent e) =>
                  _onPointerSignal(e, engine),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: viewport,
                  painter: _GolPainter(
                    engine: engine,
                    colorScheme: scheme,
                    stampHoverCell: _stampHoverCell,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GolPainter extends CustomPainter {
  final GolEngine engine;
  final ColorScheme colorScheme;
  final (int, int)? stampHoverCell;

  // Reusable Paint objects to avoid per-cell allocations.
  final Paint _bgPaint = Paint()..style = PaintingStyle.fill;
  final Paint _cellPaint = Paint()..style = PaintingStyle.fill;
  final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  final Paint _ghostFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _ghostBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4;
  final Paint _cropFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _cropBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  _GolPainter({
    required this.engine,
    required this.colorScheme,
    required this.stampHoverCell,
  }) : super(repaint: engine);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final ({Color alive, Color aged, Color background, Color gridLine}) colors =
        engine.palette.resolveColors(colorScheme);
    final double cellSize = engine.cellSize;
    final double halfW = size.width * 0.5;
    final double halfH = size.height * 0.5;
    final double camX = engine.cameraX;
    final double camY = engine.cameraY;

    // 1. Background
    _bgPaint.color = colors.background;
    canvas.drawRect(Offset.zero & size, _bgPaint);

    // Compute visible world cell range.
    final int minX = (camX - halfW / cellSize).floor() - 1;
    final int maxX = (camX + halfW / cellSize).ceil() + 1;
    final int minY = (camY - halfH / cellSize).floor() - 1;
    final int maxY = (camY + halfH / cellSize).ceil() + 1;

    // 2. Grid lines (zoom-aware, batched in a single Path)
    if (engine.showGridLines && cellSize >= 3.5) {
      final double fade = ((cellSize - 3.5) / 4.5).clamp(0.0, 1.0);
      _gridPaint.color =
          colors.gridLine.withValues(alpha: (colors.gridLine.a * fade).clamp(0.0, 1.0));

      final bool isFinite = engine.topology != GridTopology.infinite;
      final int gxMin = isFinite ? math.max(0, minX) : minX;
      final int gxMax = isFinite ? math.min(engine.finiteWidth, maxX) : maxX;
      final int gyMin = isFinite ? math.max(0, minY) : minY;
      final int gyMax = isFinite ? math.min(engine.finiteHeight, maxY) : maxY;

      final double lineTop = isFinite
          ? math.max(0.0, (0.0 - camY) * cellSize + halfH)
          : 0.0;
      final double lineBottom = isFinite
          ? math.min(size.height, (engine.finiteHeight - camY) * cellSize + halfH)
          : size.height;
      final double lineLeft = isFinite
          ? math.max(0.0, (0.0 - camX) * cellSize + halfW)
          : 0.0;
      final double lineRight = isFinite
          ? math.min(size.width, (engine.finiteWidth - camX) * cellSize + halfW)
          : size.width;

      if (lineBottom > lineTop && lineRight > lineLeft) {
        final Path gridPath = Path();
        for (int gx = gxMin; gx <= gxMax; gx++) {
          final double sx = (gx - camX) * cellSize + halfW;
          if (sx < -1.0 || sx > size.width + 1.0) continue;
          gridPath.moveTo(sx, lineTop);
          gridPath.lineTo(sx, lineBottom);
        }
        for (int gy = gyMin; gy <= gyMax; gy++) {
          final double sy = (gy - camY) * cellSize + halfH;
          if (sy < -1.0 || sy > size.height + 1.0) continue;
          gridPath.moveTo(lineLeft, sy);
          gridPath.lineTo(lineRight, sy);
        }
        canvas.drawPath(gridPath, _gridPaint);
      }
    }

    // 3. Finite board boundary rectangle (toroidal / bounded)
    if (engine.topology != GridTopology.infinite) {
      final double left = (0.0 - camX) * cellSize + halfW;
      final double top = (0.0 - camY) * cellSize + halfH;
      final double right = (engine.finiteWidth - camX) * cellSize + halfW;
      final double bottom = (engine.finiteHeight - camY) * cellSize + halfH;
      _borderPaint.color = colors.alive.withValues(alpha: 0.45);
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), _borderPaint);
    }

    // 4. Live cells with viewport culling and precomputed age-heat LUT
    final bool showAge = engine.showCellAge;
    final List<Color>? ageLut = showAge
        ? List<Color>.generate(
            16,
            (int i) => Color.lerp(colors.alive, colors.aged, i / 15.0)!,
            growable: false,
          )
        : null;

    final double inset = cellSize >= 6.0 ? math.min(cellSize * 0.08, 1.2) : 0.0;
    final double drawSize = math.max(1.0, cellSize - inset * 2.0);
    final double radiusPx =
        drawSize >= 4.0 ? drawSize * engine.cellCornerRadius : 0.0;
    final bool useRRect = radiusPx > 0.35;
    final Radius cornerRadius = Radius.circular(radiusPx);

    if (!showAge) {
      _cellPaint.color = colors.alive;
    }

    engine.grid.forEachAliveInRect(minX, minY, maxX, maxY, (int x, int y, int age) {
      if (showAge) {
        // Map age 1..32 into 0..15 LUT buckets.
        final int bucket = ((age - 1) >> 1).clamp(0, 15);
        _cellPaint.color = ageLut![bucket];
      }
      final double sx = (x - camX) * cellSize + halfW + inset;
      final double sy = (y - camY) * cellSize + halfH + inset;
      if (useRRect) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(sx, sy, drawSize, drawSize),
            cornerRadius,
          ),
          _cellPaint,
        );
      } else {
        canvas.drawRect(Rect.fromLTWH(sx, sy, drawSize, drawSize), _cellPaint);
      }
    });

    // 5. Stamp ghost preview
    if (engine.activeTool == CanvasTool.stamp && engine.stampCells.isNotEmpty) {
      final (int anchorX, int anchorY) =
          stampHoverCell ?? (camX.floor(), camY.floor());
      final ({int width, int height}) stampSize = engine.stampSize;
      final int originX = anchorX - (stampSize.width ~/ 2);
      final int originY = anchorY - (stampSize.height ~/ 2);

      _ghostFillPaint.color = colors.alive.withValues(alpha: 0.55);
      for (final (int dx, int dy) in engine.stampCells) {
        final double sx = (originX + dx - camX) * cellSize + halfW + inset;
        final double sy = (originY + dy - camY) * cellSize + halfH + inset;
        if (useRRect) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(sx, sy, drawSize, drawSize),
              cornerRadius,
            ),
            _ghostFillPaint,
          );
        } else {
          canvas.drawRect(
            Rect.fromLTWH(sx, sy, drawSize, drawSize),
            _ghostFillPaint,
          );
        }
      }

      if (stampSize.width > 0 && stampSize.height > 0) {
        final double left = (originX - camX) * cellSize + halfW;
        final double top = (originY - camY) * cellSize + halfH;
        final double right = (originX + stampSize.width - camX) * cellSize + halfW;
        final double bottom = (originY + stampSize.height - camY) * cellSize + halfH;
        _ghostBorderPaint.color = colorScheme.primary.withValues(alpha: 0.8);
        canvas.drawRect(
          Rect.fromLTRB(left, top, right, bottom),
          _ghostBorderPaint,
        );
      }
    }

    // 6. Interactive Crop rectangle overlay + dimensions badge
    if (engine.activeTool == CanvasTool.crop &&
        engine.cropStart != null &&
        engine.cropEnd != null) {
      final (int x0, int y0) = engine.cropStart!;
      final (int x1, int y1) = engine.cropEnd!;
      final int wCells = (x1 - x0).abs() + 1;
      final int hCells = (y1 - y0).abs() + 1;

      final double left = (x0 - camX) * cellSize + halfW;
      final double top = (y0 - camY) * cellSize + halfH;
      final double right = (x1 + 1 - camX) * cellSize + halfW;
      final double bottom = (y1 + 1 - camY) * cellSize + halfH;
      final Rect cropRect = Rect.fromLTRB(left, top, right, bottom);

      _cropFillPaint.color = colorScheme.primary.withValues(alpha: 0.16);
      _cropBorderPaint.color = colorScheme.primary;
      canvas.drawRect(cropRect, _cropFillPaint);
      canvas.drawRect(cropRect, _cropBorderPaint);

      _paintCropBadge(canvas, size, cropRect, '$wCells × $hCells');
    }
  }

  void _paintCropBadge(
    Canvas canvas,
    Size viewport,
    Rect cropRect,
    String label,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const double padH = 10.0;
    const double padV = 5.0;
    final double badgeW = tp.width + padH * 2;
    final double badgeH = tp.height + padV * 2;

    final double bx =
        cropRect.left.clamp(8.0, math.max(8.0, viewport.width - badgeW - 8.0));
    final double preferredY = cropRect.top - badgeH - 8.0;
    final double by = preferredY >= 8.0
        ? preferredY
        : (cropRect.top + 8.0)
            .clamp(8.0, math.max(8.0, viewport.height - badgeH - 8.0));

    final RRect pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(bx, by, badgeW, badgeH),
      const Radius.circular(12),
    );
    _bgPaint.color = colorScheme.primaryContainer.withValues(alpha: 0.94);
    canvas.drawRRect(pill, _bgPaint);
    tp.paint(canvas, Offset(bx + padH, by + padV));
  }

  @override
  bool shouldRepaint(covariant _GolPainter oldDelegate) =>
      oldDelegate.engine != engine ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.stampHoverCell != stampHoverCell;
}
