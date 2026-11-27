import 'dart:math' as math;

/// Result of decoding an RLE or plaintext `.cells` pattern.
class DecodedPattern {
  final List<(int, int)> cells;
  final int width;
  final int height;
  final String? name;
  final String? rule;

  const DecodedPattern({
    required this.cells,
    required this.width,
    required this.height,
    this.name,
    this.rule,
  });
}

/// Result of encoding cell coordinates into Conway RLE format.
class RleEncodeResult {
  final String rle;
  final int width;
  final int height;
  final int cellCount;
  final bool truncated;

  const RleEncodeResult({
    required this.rle,
    required this.width,
    required this.height,
    required this.cellCount,
    required this.truncated,
  });
}

/// Codec for Conway Run-Length Encoded (RLE) and plaintext `.cells` patterns.
class RleCodec {
  const RleCodec._();

  static final RegExp _headerRegex = RegExp(
    r'^\s*x\s*=\s*(\d+)\s*,\s*y\s*=\s*(\d+)(?:\s*,\s*rule\s*=\s*([^\r\n]+))?',
    caseSensitive: false,
  );

  /// Decodes standard Conway RLE or plaintext `.cells` text into normalized
  /// `(0, 0)`-based coordinates.
  static DecodedPattern decode(String text) {
    final List<String> lines = text.split(RegExp(r'\r?\n'));
    String? name;
    String? rule;
    int headerLineIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#N') || line.startsWith('#n')) {
        final String candidate = line.substring(2).trim();
        if (candidate.isNotEmpty) name = candidate;
        continue;
      }
      if (line.startsWith('!Name:')) {
        final String candidate = line.substring(6).trim();
        if (candidate.isNotEmpty) name ??= candidate;
        continue;
      }
      if (line.startsWith('#')) {
        continue;
      }
      final RegExpMatch? match = _headerRegex.firstMatch(line);
      if (match != null) {
        headerLineIndex = i;
        final String? rawRule = match.group(3)?.trim();
        if (rawRule != null && rawRule.isNotEmpty) {
          rule = rawRule;
        }
        break;
      }
    }

    final List<(int, int)> rawCells = <(int, int)>[];
    if (headerLineIndex != -1) {
      _parseRleBody(lines.sublist(headerLineIndex + 1), rawCells);
    } else {
      _parsePlainCells(lines, rawCells);
    }

    final ({List<(int, int)> cells, int width, int height}) normalized =
        _normalizeCells(rawCells);

    return DecodedPattern(
      cells: normalized.cells,
      width: normalized.width,
      height: normalized.height,
      name: name,
      rule: rule,
    );
  }

  static void _parseRleBody(List<String> bodyLines, List<(int, int)> out) {
    int x = 0;
    int y = 0;
    int runCount = 0;
    bool done = false;

    for (final String line in bodyLines) {
      if (done) break;
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      for (int i = 0; i < trimmed.length; i++) {
        final int code = trimmed.codeUnitAt(i);
        if (code >= 48 && code <= 57) {
          runCount = runCount * 10 + (code - 48);
          continue;
        }
        final int count = runCount == 0 ? 1 : runCount;
        runCount = 0;

        if (code == 98 || code == 46) {
          // 'b' or '.' -> dead cells
          x += count;
        } else if (code == 111 || code == 79 || code == 42) {
          // 'o', 'O', '*' -> live cells
          for (int k = 0; k < count; k++) {
            out.add((x + k, y));
          }
          x += count;
        } else if (code == 36) {
          // '$' -> end of line(s)
          y += count;
          x = 0;
        } else if (code == 33) {
          // '!' -> end of pattern
          done = true;
          break;
        }
      }
    }
  }

  static void _parsePlainCells(List<String> lines, List<(int, int)> out) {
    int y = 0;
    for (final String rawLine in lines) {
      final String line = rawLine.trimRight();
      final String trimmedLeft = line.trimLeft();
      if (trimmedLeft.isEmpty) {
        if (out.isNotEmpty) y++;
        continue;
      }
      if (trimmedLeft.startsWith('!') || trimmedLeft.startsWith('#')) {
        continue;
      }
      for (int x = 0; x < line.length; x++) {
        final String ch = line[x];
        if (ch == 'O' || ch == 'o' || ch == '*') {
          out.add((x, y));
        }
      }
      y++;
    }
  }

  /// Encodes [cells] into standard Conway RLE format with line wrapping <= 70
  /// characters. Normalizes to `(0, 0)` and caps at [maxCells] and [maxSpan].
  static RleEncodeResult encode(
    Iterable<(int, int)> cells, {
    String? name,
    String? rule,
    int maxCells = 16384,
    int maxSpan = 512,
  }) {
    final ({List<(int, int)> cells, int width, int height}) normalized =
        _normalizeCells(cells);

    if (normalized.cells.isEmpty) {
      final StringBuffer emptyBuf = StringBuffer();
      if (name != null && name.trim().isNotEmpty) {
        emptyBuf.writeln('#N ${name.trim()}');
      }
      if (rule != null && rule.trim().isNotEmpty) {
        emptyBuf.writeln('x = 0, y = 0, rule = ${rule.trim()}');
      } else {
        emptyBuf.writeln('x = 0, y = 0');
      }
      emptyBuf.write('!');
      return RleEncodeResult(
        rle: emptyBuf.toString(),
        width: 0,
        height: 0,
        cellCount: 0,
        truncated: false,
      );
    }

    bool truncated = false;
    final List<(int, int)> kept = <(int, int)>[];
    for (final (int x, int y) in normalized.cells) {
      if (x >= maxSpan || y >= maxSpan) {
        truncated = true;
        continue;
      }
      if (kept.length >= maxCells) {
        truncated = true;
        break;
      }
      kept.add((x, y));
    }

    if (kept.isEmpty) {
      return encode(
        const <(int, int)>[],
        name: name,
        rule: rule,
        maxCells: maxCells,
        maxSpan: maxSpan,
      );
    }

    int width = 0;
    int height = 0;
    for (final (int x, int y) in kept) {
      if (x + 1 > width) width = x + 1;
      if (y + 1 > height) height = y + 1;
    }

    // Sort by y ascending, then x ascending.
    kept.sort(((int, int) a, (int, int) b) {
      final int cmpY = a.$2.compareTo(b.$2);
      return cmpY != 0 ? cmpY : a.$1.compareTo(b.$1);
    });

    final StringBuffer header = StringBuffer();
    if (name != null && name.trim().isNotEmpty) {
      header.writeln('#N ${name.trim()}');
    }
    if (rule != null && rule.trim().isNotEmpty) {
      header.writeln('x = $width, y = $height, rule = ${rule.trim()}');
    } else {
      header.writeln('x = $width, y = $height');
    }

    final List<String> tokens = <String>[];
    int currentY = 0;
    int currentX = 0;
    int idx = 0;

    while (idx < kept.length) {
      final int rowY = kept[idx].$2;
      if (rowY > currentY) {
        final int rowDiff = rowY - currentY;
        tokens.add(rowDiff == 1 ? r'$' : '$rowDiff\$');
        currentY = rowY;
        currentX = 0;
      }

      // Collect contiguous live run on this row.
      final int startX = kept[idx].$1;
      if (startX > currentX) {
        final int deadRun = startX - currentX;
        tokens.add(deadRun == 1 ? 'b' : '${deadRun}b');
      }

      int endX = startX + 1;
      idx++;
      while (idx < kept.length && kept[idx].$2 == rowY && kept[idx].$1 == endX) {
        endX++;
        idx++;
      }

      final int liveRun = endX - startX;
      tokens.add(liveRun == 1 ? 'o' : '${liveRun}o');
      currentX = endX;
    }
    tokens.add('!');

    final StringBuffer body = StringBuffer();
    int lineLen = 0;
    for (final String token in tokens) {
      if (lineLen + token.length > 70 && lineLen > 0) {
        body.write('\n');
        lineLen = 0;
      }
      body.write(token);
      lineLen += token.length;
    }

    return RleEncodeResult(
      rle: '${header.toString()}${body.toString()}',
      width: width,
      height: height,
      cellCount: kept.length,
      truncated: truncated,
    );
  }
}

/// Rotates [cells] clockwise by [times] * 90 degrees and normalizes to `(0, 0)`.
({List<(int, int)> cells, int width, int height}) rotateCellsCW(
  List<(int, int)> cells,
  int times,
) {
  if (cells.isEmpty) {
    return (cells: const <(int, int)>[], width: 0, height: 0);
  }
  final int steps = ((times % 4) + 4) % 4;
  if (steps == 0) {
    return _normalizeCells(cells);
  }

  final List<(int, int)> rotated = cells.map(((int, int) p) {
    final int x = p.$1;
    final int y = p.$2;
    return switch (steps) {
      1 => (-y, x),
      2 => (-x, -y),
      3 => (y, -x),
      _ => (x, y),
    };
  }).toList();

  return _normalizeCells(rotated);
}

/// Flips [cells] horizontally and normalizes to `(0, 0)`.
({List<(int, int)> cells, int width, int height}) flipCellsHorizontal(
  List<(int, int)> cells,
) {
  if (cells.isEmpty) {
    return (cells: const <(int, int)>[], width: 0, height: 0);
  }
  final List<(int, int)> flipped =
      cells.map(((int, int) p) => (-p.$1, p.$2)).toList();
  return _normalizeCells(flipped);
}

({List<(int, int)> cells, int width, int height}) _normalizeCells(
  Iterable<(int, int)> raw,
) {
  final Set<(int, int)> unique = <(int, int)>{};
  int minX = 0x7fffffff;
  int minY = 0x7fffffff;
  int maxX = -0x7fffffff;
  int maxY = -0x7fffffff;

  for (final (int x, int y) in raw) {
    if (unique.add((x, y))) {
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }

  if (unique.isEmpty) {
    return (cells: const <(int, int)>[], width: 0, height: 0);
  }

  final List<(int, int)> normalized = unique
      .map(((int, int) p) => (p.$1 - minX, p.$2 - minY))
      .toList(growable: false);

  return (
    cells: normalized,
    width: (maxX - minX) + 1,
    height: (maxY - minY) + 1,
  );
}
