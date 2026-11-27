import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3x/m3x.dart' show M3x;
import 'package:m3x_core/m3x_core.dart';
import 'package:m3x_dict/m3x_dict.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gol_grid.dart';
import 'gol_models.dart';
import 'pattern_library.dart';
import 'rle_codec.dart';

/// Central state machine, simulation loop, camera controller, and persistence
/// layer for Golr. Never holds a [BuildContext].
class GolEngine extends ChangeNotifier {
  static const double minCellSize = 1.5;
  static const double maxCellSize = 64.0;
  static const double minTps = 1.0;
  static const double maxTps = 120.0;
  static const int maxUndoDepth = 30;

  // SharedPreferences keys
  static const String _prefTopology = 'gol_topology';
  static const String _prefFiniteWidth = 'gol_finite_width';
  static const String _prefFiniteHeight = 'gol_finite_height';
  static const String _prefRuleNotation = 'gol_rule_notation';
  static const String _prefTargetTps = 'gol_target_tps';
  static const String _prefPalette = 'gol_palette';
  static const String _prefShowGridLines = 'gol_show_grid_lines';
  static const String _prefShowCellAge = 'gol_show_cell_age';
  static const String _prefCellCornerRadius = 'gol_cell_corner_radius';
  static const String _prefHapticsEnabled = 'gol_haptics_enabled';
  static const String _prefEnableScrollBlur = 'gol_enable_scroll_blur';
  static const String _prefCustomPatterns = 'gol_custom_patterns';

  SharedPreferences? _prefs;
  late Dictionary dict;
  late final AnalyticsService analytics;

  bool _initialized = false;
  GolGrid _grid = GolGrid(topology: GridTopology.infinite);
  GridTopology _topology = GridTopology.infinite;
  int _finiteWidth = 128;
  int _finiteHeight = 128;
  GolRule _rule = GolRule.conway;

  // Simulation playback
  bool _isPlaying = false;
  double _targetTps = 15.0;
  Timer? _simTimer;

  // Camera (world cell at viewport center)
  double _cameraX = 0.0;
  double _cameraY = 0.0;
  double _cellSize = 14.0;

  // Appearance & controls
  GolPalette _palette = GolPalette.system;
  bool _showGridLines = true;
  bool _showCellAge = true;
  double _cellCornerRadius = 0.18;
  bool _hapticsEnabled = true;
  bool _enableScrollBlur = true;

  // Tools & patterns
  CanvasTool _activeTool = CanvasTool.draw;
  GolPattern? _selectedPattern;
  List<(int, int)> _stampBaseCells = const <(int, int)>[];
  List<(int, int)> _stampCells = const <(int, int)>[];
  ({int width, int height}) _stampSize = (width: 0, height: 0);
  int _stampRotation = 0;
  bool _stampFlipped = false;

  (int, int)? _cropStart;
  (int, int)? _cropEnd;

  List<GolPattern> _customPatterns = <GolPattern>[];
  List<GolPattern> _catalogPatterns = PatternLibrary.builtInPatterns;

  // Undo / Redo stacks
  final List<GolGridSnapshot> _undoStack = <GolGridSnapshot>[];
  final List<GolGridSnapshot> _redoStack = <GolGridSnapshot>[];

  GolEngine({Dictionary? dictionary}) {
    analytics = AnalyticsService(notifyEngine: notifyListeners);
    dict = dictionary ??
        Dictionary(
          path: 'assets/translations',
          debugHighlightFallbacks: kDebugMode,
        );
  }

  // Getters
  bool get initialized => _initialized;
  GolGrid get grid => _grid;
  int get generation => _grid.generation;
  int get population => _grid.population;
  GridTopology get topology => _topology;
  int get finiteWidth => _finiteWidth;
  int get finiteHeight => _finiteHeight;
  GolRule get rule => _rule;

  bool get isPlaying => _isPlaying;
  double get targetTps => _targetTps;

  double get cameraX => _cameraX;
  double get cameraY => _cameraY;
  double get cellSize => _cellSize;

  GolPalette get palette => _palette;
  bool get showGridLines => _showGridLines;
  bool get showCellAge => _showCellAge;
  double get cellCornerRadius => _cellCornerRadius;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get enableScrollBlur => _enableScrollBlur;

  CanvasTool get activeTool => _activeTool;
  GolPattern? get selectedPattern => _selectedPattern;
  List<(int, int)> get stampCells => _stampCells;
  ({int width, int height}) get stampSize => _stampSize;
  int get stampRotation => _stampRotation;
  bool get stampFlipped => _stampFlipped;

  (int, int)? get cropStart => _cropStart;
  (int, int)? get cropEnd => _cropEnd;

  List<GolPattern> get builtInPatterns => PatternLibrary.builtInPatterns;
  List<GolPattern> get catalogPatterns =>
      List<GolPattern>.unmodifiable(_catalogPatterns);
  List<GolPattern> get customPatterns =>
      List<GolPattern>.unmodifiable(_customPatterns);
  List<GolPattern> get allPatterns =>
      <GolPattern>[..._customPatterns, ..._catalogPatterns];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Localization shorthand delegating to [dict].
  String tr(String key) => dict.value(key);

  /// Initializes preferences, M3x services, localization, and seeds the board.
  Future<void> init() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      dict = Dictionary(
        path: 'assets/translations',
        url: !kDebugMode
            ? 'https://raw.githubusercontent.com/Puzzaks/gol/main/assets/translations'
            : '',
        debugHighlightFallbacks: kDebugMode,
        onRemoteUpdated: notifyListeners,
        storage: CallbackDictionaryStorage(
          getFn: (String k) => prefs.get(k),
          putFn: (String k, dynamic v) => prefs.setString(k, v.toString()),
          deleteFn: (String k) => prefs.remove(k),
          containsKeyFn: (String k) => prefs.containsKey(k),
        ),
      );
      _restoreFromPrefs(prefs);
    } catch (e) {
      analytics.log('Engine', 'Warning', 'Preferences unavailable: $e');
    }

    try {
      await dict.setup(backgroundRefresh: !kDebugMode);
    } catch (e) {
      analytics.log('Dict', 'Warning', 'Dictionary setup fallback: $e');
    }

    try {
      await M3x.init(enableMesh: false);
    } catch (_) {}

    _catalogPatterns = await PatternLibrary.loadCatalog();
    _rebuildGridAndSeed();
    _initialized = true;
    analytics.log('Engine', 'Info', 'GolEngine initialized');
    notifyListeners();
  }

  void _restoreFromPrefs(SharedPreferences prefs) {
    final String? topoName = prefs.getString(_prefTopology);
    if (topoName != null) {
      _topology = GridTopology.values.firstWhere(
        (GridTopology t) => t.name == topoName,
        orElse: () => GridTopology.infinite,
      );
    }
    _finiteWidth = (prefs.getInt(_prefFiniteWidth) ?? 128).clamp(8, 2048);
    _finiteHeight = (prefs.getInt(_prefFiniteHeight) ?? 128).clamp(8, 2048);

    final String? ruleStr = prefs.getString(_prefRuleNotation);
    if (ruleStr != null) {
      _rule = GolRule.tryParse(ruleStr) ?? GolRule.conway;
    }

    _targetTps = (prefs.getDouble(_prefTargetTps) ?? 15.0).clamp(minTps, maxTps);

    final String? paletteName = prefs.getString(_prefPalette);
    if (paletteName != null) {
      _palette = GolPalette.values.firstWhere(
        (GolPalette p) => p.name == paletteName,
        orElse: () => GolPalette.system,
      );
    }

    _showGridLines = prefs.getBool(_prefShowGridLines) ?? true;
    _showCellAge = prefs.getBool(_prefShowCellAge) ?? true;
    _cellCornerRadius =
        (prefs.getDouble(_prefCellCornerRadius) ?? 0.18).clamp(0.0, 0.5);
    _hapticsEnabled = prefs.getBool(_prefHapticsEnabled) ?? true;
    _enableScrollBlur = prefs.getBool(_prefEnableScrollBlur) ?? true;

    final String? rawCustom = prefs.getString(_prefCustomPatterns);
    if (rawCustom != null && rawCustom.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawCustom);
        if (decoded is List) {
          _customPatterns = decoded
              .whereType<Map>()
              .map((Map m) => GolPattern.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        }
      } catch (e) {
        analytics.log('Engine', 'Warning', 'Failed to parse custom patterns: $e');
      }
    }
  }

  void _rebuildGridAndSeed() {
    _grid = GolGrid(
      topology: _topology,
      width: _finiteWidth,
      height: _finiteHeight,
    );
    _undoStack.clear();
    _redoStack.clear();
    _seedInitialBoard();
    resetCamera();
  }

  void _seedInitialBoard() {
    final bool fitsGun = _topology == GridTopology.infinite ||
        (_finiteWidth >= 40 && _finiteHeight >= 20);
    if (fitsGun) {
      final DecodedPattern gun =
          RleCodec.decode(PatternLibrary.gosperGliderGun.rle);
      final int cx = _topology == GridTopology.infinite ? 0 : _finiteWidth ~/ 2;
      final int cy =
          _topology == GridTopology.infinite ? 0 : _finiteHeight ~/ 2;
      _grid.stamp(
        gun.cells,
        cx - (gun.width ~/ 2),
        cy - (gun.height ~/ 2),
      );
    } else {
      final DecodedPattern glider = RleCodec.decode(PatternLibrary.glider.rle);
      final DecodedPattern blinker =
          RleCodec.decode(PatternLibrary.blinker.rle);
      _grid.stamp(glider.cells, 1, 1);
      final int bx = math.max(1, _finiteWidth - 5);
      final int by = math.max(1, _finiteHeight ~/ 2);
      _grid.stamp(blinker.cells, bx, by);
    }
  }

  // ── Camera ─────────────────────────────────────────────────────────────────

  /// Converts a screen-space [Offset] in [viewport] to floating-point world
  /// cell coordinates.
  Offset screenToWorld(Offset screenPos, Size viewport) {
    final double wx =
        _cameraX + (screenPos.dx - viewport.width * 0.5) / _cellSize;
    final double wy =
        _cameraY + (screenPos.dy - viewport.height * 0.5) / _cellSize;
    return Offset(wx, wy);
  }

  /// Converts world cell coordinates `(wx, wy)` to screen-space [Offset].
  Offset worldToScreen(double wx, double wy, Size viewport) {
    final double sx = (wx - _cameraX) * _cellSize + viewport.width * 0.5;
    final double sy = (wy - _cameraY) * _cellSize + viewport.height * 0.5;
    return Offset(sx, sy);
  }

  /// Pans the camera by screen-space [delta] pixels.
  void panByPixels(Offset delta) {
    _cameraX -= delta.dx / _cellSize;
    _cameraY -= delta.dy / _cellSize;
    notifyListeners();
  }

  /// Zooms by [scaleFactor] while keeping the world point under [focalPoint]
  /// stationary on screen.
  void zoomAtFocalPoint(double scaleFactor, Offset focalPoint, Size viewport) {
    if (scaleFactor <= 0 || viewport.isEmpty) return;
    final double oldSize = _cellSize;
    final double newSize = (oldSize * scaleFactor).clamp(minCellSize, maxCellSize);
    if (newSize == oldSize) return;

    final double dx = focalPoint.dx - viewport.width * 0.5;
    final double dy = focalPoint.dy - viewport.height * 0.5;
    final double worldFocalX = _cameraX + dx / oldSize;
    final double worldFocalY = _cameraY + dy / oldSize;

    _cellSize = newSize;
    _cameraX = worldFocalX - dx / newSize;
    _cameraY = worldFocalY - dy / newSize;
    notifyListeners();
  }

  /// Centers the camera on the grid origin (infinite) or finite board center.
  void resetCamera() {
    if (_topology == GridTopology.infinite) {
      _cameraX = 0.0;
      _cameraY = 0.0;
    } else {
      _cameraX = _finiteWidth * 0.5;
      _cameraY = _finiteHeight * 0.5;
    }
    _cellSize = 14.0;
    notifyListeners();
  }

  /// Fits the camera to frame all live cells (or finite bounds) within [viewport].
  void fitToContent(Size viewport) {
    if (viewport.isEmpty) return;
    final ({int minX, int minY, int maxX, int maxY})? box = _grid.boundingBox();
    if (box == null) {
      resetCamera();
      return;
    }

    final int spanX = (box.maxX - box.minX + 1).clamp(1, 1 << 20);
    final int spanY = (box.maxY - box.minY + 1).clamp(1, 1 << 20);
    _cameraX = (box.minX + box.maxX + 1) * 0.5;
    _cameraY = (box.minY + box.maxY + 1) * 0.5;

    final double paddedW = viewport.width * 0.8;
    final double paddedH = viewport.height * 0.8;
    final double targetSize = math.min(paddedW / spanX, paddedH / spanY);
    _cellSize = targetSize.clamp(minCellSize, maxCellSize);
    notifyListeners();
  }

  // ── Simulation ─────────────────────────────────────────────────────────────

  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      _isPlaying = true;
      _restartSimTimer();
      notifyListeners();
    }
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _simTimer?.cancel();
    _simTimer = null;
    notifyListeners();
  }

  void _restartSimTimer() {
    _simTimer?.cancel();
    if (!_isPlaying) return;
    final int intervalMs = math.max(8, (1000.0 / _targetTps).round());
    _simTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _grid.step(_rule);
      notifyListeners();
    });
  }

  void stepOnce() {
    pause();
    pushUndo();
    _grid.step(_rule);
    notifyListeners();
  }

  void clear() {
    pause();
    pushUndo();
    _grid.clear();
    notifyListeners();
  }

  void randomizeViewport(Size viewport, {double density = 0.25}) {
    pushUndo();
    if (_topology == GridTopology.infinite && !viewport.isEmpty) {
      final Offset topLeft = screenToWorld(Offset.zero, viewport);
      final Offset bottomRight =
          screenToWorld(Offset(viewport.width, viewport.height), viewport);
      _grid.randomizeRect(
        topLeft.dx.floor(),
        topLeft.dy.floor(),
        bottomRight.dx.ceil(),
        bottomRight.dy.ceil(),
        density,
      );
    } else {
      _grid.randomizeRect(0, 0, _finiteWidth - 1, _finiteHeight - 1, density);
    }
    notifyListeners();
  }

  /// Sets a single cell `(x, y)` to [alive].
  void setCell(int x, int y, bool alive) {
    _grid.setCell(x, y, alive);
    notifyListeners();
  }

  /// Pushes the current grid state onto the undo stack (capped at [maxUndoDepth]).
  void pushUndo() {
    _undoStack.add(_grid.takeSnapshot());
    if (_undoStack.length > maxUndoDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    pause();
    _redoStack.add(_grid.takeSnapshot());
    final GolGridSnapshot prev = _undoStack.removeLast();
    _grid.restoreSnapshot(prev);
    _topology = prev.topology;
    _finiteWidth = prev.width;
    _finiteHeight = prev.height;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    pause();
    _undoStack.add(_grid.takeSnapshot());
    final GolGridSnapshot next = _redoStack.removeLast();
    _grid.restoreSnapshot(next);
    _topology = next.topology;
    _finiteWidth = next.width;
    _finiteHeight = next.height;
    notifyListeners();
  }

  void setTargetTps(double tps) {
    final double clamped = tps.clamp(minTps, maxTps);
    if (_targetTps == clamped) return;
    _targetTps = clamped;
    _prefs?.setDouble(_prefTargetTps, clamped);
    if (_isPlaying) {
      _restartSimTimer();
    }
    notifyListeners();
  }

  void setTopology(GridTopology topology) {
    if (_topology == topology) return;
    pause();
    _topology = topology;
    _prefs?.setString(_prefTopology, topology.name);
    _rebuildGridAndSeed();
    notifyListeners();
  }

  void setFiniteSize(int width, int height) {
    final int w = width.clamp(8, 2048);
    final int h = height.clamp(8, 2048);
    if (_finiteWidth == w && _finiteHeight == h) return;
    pause();
    _finiteWidth = w;
    _finiteHeight = h;
    _prefs?.setInt(_prefFiniteWidth, w);
    _prefs?.setInt(_prefFiniteHeight, h);
    if (_topology != GridTopology.infinite) {
      _rebuildGridAndSeed();
    }
    notifyListeners();
  }

  void setRule(GolRule rule) {
    if (_rule == rule) return;
    _rule = rule;
    _prefs?.setString(_prefRuleNotation, rule.notation);
    notifyListeners();
  }

  // ── Appearance & Controls ──────────────────────────────────────────────────

  void setPalette(GolPalette palette) {
    if (_palette == palette) return;
    _palette = palette;
    _prefs?.setString(_prefPalette, palette.name);
    notifyListeners();
  }

  void setShowGridLines(bool show) {
    if (_showGridLines == show) return;
    _showGridLines = show;
    _prefs?.setBool(_prefShowGridLines, show);
    notifyListeners();
  }

  void setShowCellAge(bool show) {
    if (_showCellAge == show) return;
    _showCellAge = show;
    _prefs?.setBool(_prefShowCellAge, show);
    notifyListeners();
  }

  void setCellCornerRadius(double radius) {
    final double clamped = radius.clamp(0.0, 0.5);
    if (_cellCornerRadius == clamped) return;
    _cellCornerRadius = clamped;
    _prefs?.setDouble(_prefCellCornerRadius, clamped);
    notifyListeners();
  }

  void setHapticsEnabled(bool enabled) {
    if (_hapticsEnabled == enabled) return;
    _hapticsEnabled = enabled;
    _prefs?.setBool(_prefHapticsEnabled, enabled);
    notifyListeners();
  }

  void setEnableScrollBlur(bool enabled) {
    if (_enableScrollBlur == enabled) return;
    _enableScrollBlur = enabled;
    _prefs?.setBool(_prefEnableScrollBlur, enabled);
    notifyListeners();
  }

  // ── Tools & Patterns ───────────────────────────────────────────────────────

  void setActiveTool(CanvasTool tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
    if (tool != CanvasTool.crop) {
      _cropStart = null;
      _cropEnd = null;
    }
    notifyListeners();
  }

  void selectPatternForStamp(GolPattern pattern) {
    _selectedPattern = pattern;
    final DecodedPattern decoded = RleCodec.decode(pattern.rle);
    _stampBaseCells = decoded.cells;
    _stampRotation = 0;
    _stampFlipped = false;
    _recomputeStampCells();
    _activeTool = CanvasTool.stamp;
    notifyListeners();
  }

  void rotateStamp() {
    if (_stampBaseCells.isEmpty) return;
    _stampRotation = (_stampRotation + 1) % 4;
    _recomputeStampCells();
    notifyListeners();
  }

  void flipStamp() {
    if (_stampBaseCells.isEmpty) return;
    _stampFlipped = !_stampFlipped;
    _recomputeStampCells();
    notifyListeners();
  }

  void _recomputeStampCells() {
    List<(int, int)> cells = _stampBaseCells;
    int width = 0;
    int height = 0;
    if (_stampFlipped) {
      final ({List<(int, int)> cells, int width, int height}) flipped =
          flipCellsHorizontal(cells);
      cells = flipped.cells;
      width = flipped.width;
      height = flipped.height;
    }
    final ({List<(int, int)> cells, int width, int height}) rotated =
        rotateCellsCW(cells, _stampRotation);
    _stampCells = rotated.cells;
    _stampSize = (
      width: rotated.width == 0 ? width : rotated.width,
      height: rotated.height == 0 ? height : rotated.height,
    );
  }

  /// Stamps the currently selected pattern centered on `(worldX, worldY)`.
  void stampAt(int worldX, int worldY) {
    if (_stampCells.isEmpty) return;
    pushUndo();
    final int originX = worldX - (_stampSize.width ~/ 2);
    final int originY = worldY - (_stampSize.height ~/ 2);
    _grid.stamp(_stampCells, originX, originY);
    notifyListeners();
  }

  /// Clears the grid, stamps [pattern] centered at `(0, 0)`, and fits camera
  /// to [viewport].
  void loadPatternCentered(GolPattern pattern, Size viewport) {
    final DecodedPattern decoded = RleCodec.decode(pattern.rle);
    if (decoded.cells.isEmpty) return;
    pushUndo();
    _grid.clear();
    _grid.stamp(decoded.cells, -decoded.width ~/ 2, -decoded.height ~/ 2);
    fitToContent(viewport);
    notifyListeners();
  }

  void setCropRect(int x1, int y1, int x2, int y2) {
    _cropStart = (math.min(x1, x2), math.min(y1, y2));
    _cropEnd = (math.max(x1, x2), math.max(y1, y2));
    notifyListeners();
  }

  void clearCropRect() {
    _cropStart = null;
    _cropEnd = null;
    notifyListeners();
  }

  /// Saves a custom pattern from raw cell coordinates or an RLE string.
  GolPattern saveCustomPattern({
    required String name,
    required List<(int, int)> cells,
    String description = '',
    PatternCategory category = PatternCategory.custom,
  }) {
    final RleEncodeResult encoded = RleCodec.encode(
      cells,
      name: name,
      rule: _rule.notation,
    );
    final GolPattern pattern = GolPattern(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Pattern' : name.trim(),
      category: category,
      rle: encoded.rle,
      width: encoded.width,
      height: encoded.height,
      description: description,
      isBuiltIn: false,
    );
    _customPatterns = <GolPattern>[pattern, ..._customPatterns];
    _persistCustomPatterns();
    notifyListeners();
    return pattern;
  }

  void deleteCustomPattern(String id) {
    final int before = _customPatterns.length;
    _customPatterns.removeWhere((GolPattern p) => p.id == id);
    if (_customPatterns.length != before) {
      if (_selectedPattern?.id == id) {
        _selectedPattern = null;
        _stampBaseCells = const <(int, int)>[];
        _stampCells = const <(int, int)>[];
        _stampSize = (width: 0, height: 0);
      }
      _persistCustomPatterns();
      notifyListeners();
    }
  }

  void _persistCustomPatterns() {
    final String encoded = jsonEncode(
      _customPatterns.map((GolPattern p) => p.toJson()).toList(),
    );
    _prefs?.setString(_prefCustomPatterns, encoded);
  }

  /// Resets all user preferences to defaults and re-seeds the board.
  Future<void> resetAllSettings() async {
    pause();
    _topology = GridTopology.infinite;
    _finiteWidth = 128;
    _finiteHeight = 128;
    _rule = GolRule.conway;
    _targetTps = 15.0;
    _palette = GolPalette.system;
    _showGridLines = true;
    _showCellAge = true;
    _cellCornerRadius = 0.18;
    _hapticsEnabled = true;
    _enableScrollBlur = true;
    _activeTool = CanvasTool.draw;
    _customPatterns = <GolPattern>[];

    final SharedPreferences? prefs = _prefs;
    if (prefs != null) {
      await Future.wait(<Future<bool>>[
        prefs.remove(_prefTopology),
        prefs.remove(_prefFiniteWidth),
        prefs.remove(_prefFiniteHeight),
        prefs.remove(_prefRuleNotation),
        prefs.remove(_prefTargetTps),
        prefs.remove(_prefPalette),
        prefs.remove(_prefShowGridLines),
        prefs.remove(_prefShowCellAge),
        prefs.remove(_prefCellCornerRadius),
        prefs.remove(_prefHapticsEnabled),
        prefs.remove(_prefEnableScrollBlur),
        prefs.remove(_prefCustomPatterns),
      ]);
    }

    _rebuildGridAndSeed();
    notifyListeners();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _simTimer = null;
    super.dispose();
  }
}
