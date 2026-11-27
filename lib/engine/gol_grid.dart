import 'dart:math' as math;
import 'dart:typed_data';

import 'gol_models.dart';

/// Immutable snapshot of a [GolGrid] state for undo/redo history.
class GolGridSnapshot {
  final GridTopology topology;
  final int width;
  final int height;
  final int generation;
  final int population;
  final Map<int, Uint8List>? chunks;
  final Uint8List? cells;

  const GolGridSnapshot._({
    required this.topology,
    required this.width,
    required this.height,
    required this.generation,
    required this.population,
    this.chunks,
    this.cells,
  });
}

/// Dual-backend high-speed Game of Life grid.
///
/// Uses sparse 16×16 chunks with JS/Web-safe packed integer keys in
/// [GridTopology.infinite] mode, and double-buffered flat [Uint8List] arrays
/// in [GridTopology.toroidal] and [GridTopology.bounded] modes.
class GolGrid {
  static const int chunkSize = 16;
  static const int chunkArea = chunkSize * chunkSize;
  static const int _keyOffset = 0x100000;
  static const int _keyStride = 0x200000;

  GridTopology _topology;
  int _width;
  int _height;
  int _generation = 0;
  int _population = 0;

  // Infinite backend state.
  Map<int, Uint8List> _chunks = <int, Uint8List>{};
  final Uint8List _neighborScratch = Uint8List(chunkArea);

  // Finite (toroidal / bounded) backend state.
  Uint8List _cells = Uint8List(0);
  Uint8List _nextCells = Uint8List(0);

  GolGrid({
    GridTopology topology = GridTopology.infinite,
    int width = 128,
    int height = 128,
  })  : _topology = topology,
        _width = width.clamp(8, 2048),
        _height = height.clamp(8, 2048) {
    if (_topology != GridTopology.infinite) {
      final int len = _width * _height;
      _cells = Uint8List(len);
      _nextCells = Uint8List(len);
    }
  }

  GridTopology get topology => _topology;
  int get width => _width;
  int get height => _height;
  int get generation => _generation;
  int get population => _population;

  @pragma('vm:prefer-inline')
  static int _floorDiv16(int v) => v >= 0 ? v ~/ 16 : -((-v + 15) ~/ 16);

  @pragma('vm:prefer-inline')
  static int _packKey(int cx, int cy) =>
      ((cx + _keyOffset) * _keyStride) + (cy + _keyOffset);

  @pragma('vm:prefer-inline')
  static (int, int) _unpackKey(int key) {
    final int shiftedX = key ~/ _keyStride;
    final int shiftedY = key - (shiftedX * _keyStride);
    return (shiftedX - _keyOffset, shiftedY - _keyOffset);
  }

  bool _inFiniteBounds(int x, int y) =>
      x >= 0 && x < _width && y >= 0 && y < _height;

  int _wrapX(int x) {
    final int m = x % _width;
    return m < 0 ? m + _width : m;
  }

  int _wrapY(int y) {
    final int m = y % _height;
    return m < 0 ? m + _height : m;
  }

  /// Returns `true` if cell `(x, y)` is alive.
  bool getCell(int x, int y) => getCellAge(x, y) > 0;

  /// Returns `0` if dead, or `1..255` representing cell age.
  int getCellAge(int x, int y) {
    switch (_topology) {
      case GridTopology.infinite:
        final int cx = _floorDiv16(x);
        final int cy = _floorDiv16(y);
        final Uint8List? chunk = _chunks[_packKey(cx, cy)];
        if (chunk == null) return 0;
        final int lx = x - cx * chunkSize;
        final int ly = y - cy * chunkSize;
        return chunk[ly * chunkSize + lx];
      case GridTopology.toroidal:
        final int wx = _wrapX(x);
        final int wy = _wrapY(y);
        return _cells[wy * _width + wx];
      case GridTopology.bounded:
        if (!_inFiniteBounds(x, y)) return 0;
        return _cells[y * _width + x];
    }
  }

  /// Sets cell `(x, y)` to [alive] (`1` if newly alive, `0` if dead).
  void setCell(int x, int y, bool alive) {
    switch (_topology) {
      case GridTopology.infinite:
        final int cx = _floorDiv16(x);
        final int cy = _floorDiv16(y);
        final int key = _packKey(cx, cy);
        final int lx = x - cx * chunkSize;
        final int ly = y - cy * chunkSize;
        final int idx = ly * chunkSize + lx;
        Uint8List? chunk = _chunks[key];
        if (alive) {
          if (chunk == null) {
            chunk = Uint8List(chunkArea);
            _chunks[key] = chunk;
          }
          if (chunk[idx] == 0) {
            chunk[idx] = 1;
            _population++;
          }
        } else if (chunk != null && chunk[idx] != 0) {
          chunk[idx] = 0;
          _population--;
          bool anyAlive = false;
          for (int i = 0; i < chunkArea; i++) {
            if (chunk[i] != 0) {
              anyAlive = true;
              break;
            }
          }
          if (!anyAlive) {
            _chunks.remove(key);
          }
        }
      case GridTopology.toroidal:
        final int wx = _wrapX(x);
        final int wy = _wrapY(y);
        final int idx = wy * _width + wx;
        final int prev = _cells[idx];
        if (alive && prev == 0) {
          _cells[idx] = 1;
          _population++;
        } else if (!alive && prev != 0) {
          _cells[idx] = 0;
          _population--;
        }
      case GridTopology.bounded:
        if (!_inFiniteBounds(x, y)) return;
        final int idx = y * _width + x;
        final int prev = _cells[idx];
        if (alive && prev == 0) {
          _cells[idx] = 1;
          _population++;
        } else if (!alive && prev != 0) {
          _cells[idx] = 0;
          _population--;
        }
    }
  }

  /// Advances the simulation by one generation using [rule].
  void step(GolRule rule) {
    switch (_topology) {
      case GridTopology.infinite:
        _stepInfinite(rule);
      case GridTopology.toroidal:
        _stepToroidal(rule);
      case GridTopology.bounded:
        _stepBounded(rule);
    }
    _generation++;
  }

  void _stepInfinite(GolRule rule) {
    if (_chunks.isEmpty) {
      _population = 0;
      return;
    }

    final Set<int> candidates = <int>{};
    for (final int key in _chunks.keys) {
      final (int cx, int cy) = _unpackKey(key);
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          candidates.add(_packKey(cx + dx, cy + dy));
        }
      }
    }

    final Map<int, Uint8List> nextChunks = <int, Uint8List>{};
    int nextPop = 0;

    for (final int key in candidates) {
      final (int cx, int cy) = _unpackKey(key);
      _neighborScratch.fillRange(0, chunkArea, 0);

      // Accumulate neighbor counts from center and 8 adjacent chunks.
      for (int dcy = -1; dcy <= 1; dcy++) {
        for (int dcx = -1; dcx <= 1; dcx++) {
          final Uint8List? src = _chunks[_packKey(cx + dcx, cy + dcy)];
          if (src == null) continue;

          if (dcx == 0 && dcy == 0) {
            for (int ly = 0; ly < chunkSize; ly++) {
              final int rowOff = ly * chunkSize;
              for (int lx = 0; lx < chunkSize; lx++) {
                if (src[rowOff + lx] == 0) continue;
                final int yMin = ly > 0 ? ly - 1 : 0;
                final int yMax = ly < chunkSize - 1 ? ly + 1 : chunkSize - 1;
                final int xMin = lx > 0 ? lx - 1 : 0;
                final int xMax = lx < chunkSize - 1 ? lx + 1 : chunkSize - 1;
                for (int ny = yMin; ny <= yMax; ny++) {
                  final int nRow = ny * chunkSize;
                  for (int nx = xMin; nx <= xMax; nx++) {
                    if (nx == lx && ny == ly) continue;
                    _neighborScratch[nRow + nx]++;
                  }
                }
              }
            }
          } else {
            final int startX = dcx == -1 ? chunkSize - 1 : 0;
            final int endX = dcx == 1 ? 0 : chunkSize - 1;
            final int startY = dcy == -1 ? chunkSize - 1 : 0;
            final int endY = dcy == 1 ? 0 : chunkSize - 1;
            final int baseX = dcx * chunkSize;
            final int baseY = dcy * chunkSize;

            for (int ly = startY; ly <= endY; ly++) {
              final int rowOff = ly * chunkSize;
              final int wy = baseY + ly;
              for (int lx = startX; lx <= endX; lx++) {
                if (src[rowOff + lx] == 0) continue;
                final int wx = baseX + lx;
                for (int oy = -1; oy <= 1; oy++) {
                  final int ty = wy + oy;
                  if (ty < 0 || ty >= chunkSize) continue;
                  final int tRow = ty * chunkSize;
                  for (int ox = -1; ox <= 1; ox++) {
                    final int tx = wx + ox;
                    if (tx < 0 || tx >= chunkSize) continue;
                    _neighborScratch[tRow + tx]++;
                  }
                }
              }
            }
          }
        }
      }

      final Uint8List? cur = _chunks[key];
      Uint8List? nextChunk;
      for (int i = 0; i < chunkArea; i++) {
        final int oldAge = cur != null ? cur[i] : 0;
        final int n = _neighborScratch[i];
        if (rule.nextState(oldAge != 0, n)) {
          nextChunk ??= Uint8List(chunkArea);
          nextChunk[i] = oldAge == 0 ? 1 : (oldAge < 255 ? oldAge + 1 : 255);
          nextPop++;
        }
      }

      if (nextChunk != null) {
        nextChunks[key] = nextChunk;
      }
    }

    _chunks = nextChunks;
    _population = nextPop;
  }

  void _stepToroidal(GolRule rule) {
    final int w = _width;
    final int h = _height;
    int nextPop = 0;

    for (int y = 0; y < h; y++) {
      final int ym = (y == 0 ? h - 1 : y - 1) * w;
      final int y0 = y * w;
      final int yp = (y == h - 1 ? 0 : y + 1) * w;

      for (int x = 0; x < w; x++) {
        final int xm = x == 0 ? w - 1 : x - 1;
        final int xp = x == w - 1 ? 0 : x + 1;

        int n = 0;
        if (_cells[ym + xm] != 0) n++;
        if (_cells[ym + x] != 0) n++;
        if (_cells[ym + xp] != 0) n++;
        if (_cells[y0 + xm] != 0) n++;
        if (_cells[y0 + xp] != 0) n++;
        if (_cells[yp + xm] != 0) n++;
        if (_cells[yp + x] != 0) n++;
        if (_cells[yp + xp] != 0) n++;

        final int idx = y0 + x;
        final int oldAge = _cells[idx];
        if (rule.nextState(oldAge != 0, n)) {
          _nextCells[idx] = oldAge == 0 ? 1 : (oldAge < 255 ? oldAge + 1 : 255);
          nextPop++;
        } else {
          _nextCells[idx] = 0;
        }
      }
    }

    final Uint8List tmp = _cells;
    _cells = _nextCells;
    _nextCells = tmp;
    _population = nextPop;
  }

  void _stepBounded(GolRule rule) {
    final int w = _width;
    final int h = _height;
    int nextPop = 0;

    for (int y = 0; y < h; y++) {
      final bool hasUp = y > 0;
      final bool hasDown = y < h - 1;
      final int ym = (y - 1) * w;
      final int y0 = y * w;
      final int yp = (y + 1) * w;

      for (int x = 0; x < w; x++) {
        final bool hasLeft = x > 0;
        final bool hasRight = x < w - 1;

        int n = 0;
        if (hasUp) {
          if (hasLeft && _cells[ym + x - 1] != 0) n++;
          if (_cells[ym + x] != 0) n++;
          if (hasRight && _cells[ym + x + 1] != 0) n++;
        }
        if (hasLeft && _cells[y0 + x - 1] != 0) n++;
        if (hasRight && _cells[y0 + x + 1] != 0) n++;
        if (hasDown) {
          if (hasLeft && _cells[yp + x - 1] != 0) n++;
          if (_cells[yp + x] != 0) n++;
          if (hasRight && _cells[yp + x + 1] != 0) n++;
        }

        final int idx = y0 + x;
        final int oldAge = _cells[idx];
        if (rule.nextState(oldAge != 0, n)) {
          _nextCells[idx] = oldAge == 0 ? 1 : (oldAge < 255 ? oldAge + 1 : 255);
          nextPop++;
        } else {
          _nextCells[idx] = 0;
        }
      }
    }

    final Uint8List tmp = _cells;
    _cells = _nextCells;
    _nextCells = tmp;
    _population = nextPop;
  }

  /// Clears all live cells and resets generation and population to 0.
  void clear() {
    _chunks.clear();
    if (_cells.isNotEmpty) {
      _cells.fillRange(0, _cells.length, 0);
      _nextCells.fillRange(0, _nextCells.length, 0);
    }
    _generation = 0;
    _population = 0;
  }

  /// Calls [visitor] for every live cell within `[minX..maxX] × [minY..maxY]`.
  void forEachAliveInRect(
    int minX,
    int minY,
    int maxX,
    int maxY,
    void Function(int x, int y, int age) visitor,
  ) {
    if (minX > maxX || minY > maxY || _population == 0) return;

    if (_topology == GridTopology.infinite) {
      final int minCx = _floorDiv16(minX);
      final int maxCx = _floorDiv16(maxX);
      final int minCy = _floorDiv16(minY);
      final int maxCy = _floorDiv16(maxY);

      final int chunkCount = (maxCx - minCx + 1) * (maxCy - minCy + 1);
      if (chunkCount <= _chunks.length) {
        for (int cy = minCy; cy <= maxCy; cy++) {
          for (int cx = minCx; cx <= maxCx; cx++) {
            final Uint8List? chunk = _chunks[_packKey(cx, cy)];
            if (chunk != null) {
              _visitChunkInRect(
                chunk,
                cx,
                cy,
                minX,
                minY,
                maxX,
                maxY,
                visitor,
              );
            }
          }
        }
      } else {
        for (final MapEntry<int, Uint8List> entry in _chunks.entries) {
          final (int cx, int cy) = _unpackKey(entry.key);
          if (cx < minCx || cx > maxCx || cy < minCy || cy > maxCy) continue;
          _visitChunkInRect(
            entry.value,
            cx,
            cy,
            minX,
            minY,
            maxX,
            maxY,
            visitor,
          );
        }
      }
      return;
    }

    // Finite (toroidal / bounded): clamp iteration to grid bounds.
    final int x0 = math.max(0, minX);
    final int x1 = math.min(_width - 1, maxX);
    final int y0 = math.max(0, minY);
    final int y1 = math.min(_height - 1, maxY);
    for (int y = y0; y <= y1; y++) {
      final int row = y * _width;
      for (int x = x0; x <= x1; x++) {
        final int age = _cells[row + x];
        if (age != 0) {
          visitor(x, y, age);
        }
      }
    }
  }

  void _visitChunkInRect(
    Uint8List chunk,
    int cx,
    int cy,
    int minX,
    int minY,
    int maxX,
    int maxY,
    void Function(int x, int y, int age) visitor,
  ) {
    final int baseX = cx * chunkSize;
    final int baseY = cy * chunkSize;
    final int lx0 = math.max(0, minX - baseX);
    final int lx1 = math.min(chunkSize - 1, maxX - baseX);
    final int ly0 = math.max(0, minY - baseY);
    final int ly1 = math.min(chunkSize - 1, maxY - baseY);

    for (int ly = ly0; ly <= ly1; ly++) {
      final int row = ly * chunkSize;
      final int wy = baseY + ly;
      for (int lx = lx0; lx <= lx1; lx++) {
        final int age = chunk[row + lx];
        if (age != 0) {
          visitor(baseX + lx, wy, age);
        }
      }
    }
  }

  /// Returns the bounding box of all live cells, or `null` if empty.
  ({int minX, int minY, int maxX, int maxY})? boundingBox() {
    if (_population == 0) return null;

    int minX = 0x7fffffff;
    int minY = 0x7fffffff;
    int maxX = -0x7fffffff;
    int maxY = -0x7fffffff;
    bool found = false;

    if (_topology == GridTopology.infinite) {
      for (final MapEntry<int, Uint8List> entry in _chunks.entries) {
        final (int cx, int cy) = _unpackKey(entry.key);
        final int baseX = cx * chunkSize;
        final int baseY = cy * chunkSize;
        final Uint8List chunk = entry.value;
        for (int ly = 0; ly < chunkSize; ly++) {
          final int row = ly * chunkSize;
          for (int lx = 0; lx < chunkSize; lx++) {
            if (chunk[row + lx] != 0) {
              final int wx = baseX + lx;
              final int wy = baseY + ly;
              if (wx < minX) minX = wx;
              if (wx > maxX) maxX = wx;
              if (wy < minY) minY = wy;
              if (wy > maxY) maxY = wy;
              found = true;
            }
          }
        }
      }
    } else {
      for (int y = 0; y < _height; y++) {
        final int row = y * _width;
        for (int x = 0; x < _width; x++) {
          if (_cells[row + x] != 0) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            found = true;
          }
        }
      }
    }

    if (!found) return null;
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Extracts live cell coordinates within `[minX..maxX] × [minY..maxY]`,
  /// capped at [maxCells].
  List<(int, int)> extractRegion(
    int minX,
    int minY,
    int maxX,
    int maxY, {
    int maxCells = 16384,
  }) {
    final List<(int, int)> result = <(int, int)>[];
    forEachAliveInRect(minX, minY, maxX, maxY, (int x, int y, int _) {
      if (result.length < maxCells) {
        result.add((x, y));
      }
    });
    return result;
  }

  /// Stamps [cells] onto the grid relative to `(originX, originY)`.
  void stamp(Iterable<(int, int)> cells, int originX, int originY) {
    for (final (int dx, int dy) in cells) {
      setCell(originX + dx, originY + dy, true);
    }
  }

  /// Randomizes cells within `[minX..maxX] × [minY..maxY]` with [density] in
  /// `0.0..1.0`.
  void randomizeRect(
    int minX,
    int minY,
    int maxX,
    int maxY,
    double density,
  ) {
    if (minX > maxX || minY > maxY) return;
    final double p = density.clamp(0.0, 1.0);
    final math.Random rng = math.Random();

    final int x0 = _topology == GridTopology.infinite ? minX : math.max(0, minX);
    final int x1 =
        _topology == GridTopology.infinite ? maxX : math.min(_width - 1, maxX);
    final int y0 = _topology == GridTopology.infinite ? minY : math.max(0, minY);
    final int y1 =
        _topology == GridTopology.infinite ? maxY : math.min(_height - 1, maxY);

    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        setCell(x, y, rng.nextDouble() < p);
      }
    }
  }

  /// Captures a full copy of the grid for undo/redo.
  GolGridSnapshot takeSnapshot() {
    if (_topology == GridTopology.infinite) {
      final Map<int, Uint8List> cloned = <int, Uint8List>{
        for (final MapEntry<int, Uint8List> e in _chunks.entries)
          e.key: Uint8List.fromList(e.value),
      };
      return GolGridSnapshot._(
        topology: _topology,
        width: _width,
        height: _height,
        generation: _generation,
        population: _population,
        chunks: cloned,
      );
    }
    return GolGridSnapshot._(
      topology: _topology,
      width: _width,
      height: _height,
      generation: _generation,
      population: _population,
      cells: Uint8List.fromList(_cells),
    );
  }

  /// Restores grid state from [snapshot].
  void restoreSnapshot(GolGridSnapshot snapshot) {
    _topology = snapshot.topology;
    _width = snapshot.width;
    _height = snapshot.height;
    _generation = snapshot.generation;
    _population = snapshot.population;

    if (_topology == GridTopology.infinite) {
      _chunks = <int, Uint8List>{
        if (snapshot.chunks != null)
          for (final MapEntry<int, Uint8List> e in snapshot.chunks!.entries)
            e.key: Uint8List.fromList(e.value),
      };
      _cells = Uint8List(0);
      _nextCells = Uint8List(0);
    } else {
      _chunks.clear();
      final int len = _width * _height;
      _cells = snapshot.cells != null
          ? Uint8List.fromList(snapshot.cells!)
          : Uint8List(len);
      _nextCells = Uint8List(len);
    }
  }
}
