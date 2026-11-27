import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'gol_models.dart';
import 'rle_codec.dart';

/// Decoded payload from a `gol.puzzak.page` or `gol://` share link.
class SharedGolPayload {
  final List<(int, int)> cells;
  final int width;
  final int height;
  final GolRule rule;
  final GridTopology topology;
  final GolPalette palette;
  final String? name;
  final String encodingMode;

  const SharedGolPayload({
    required this.cells,
    required this.width,
    required this.height,
    required this.rule,
    required this.topology,
    required this.palette,
    this.name,
    required this.encodingMode,
  });
}

/// Result of encoding a Game of Life board or pattern into a shareable URI.
class GolShareEncodeResult {
  final Uri uri;
  final int payloadBytes;
  final int urlLength;
  final String encodingMode;
  final bool qrReadable;
  final bool truncated;
  final int cellCount;
  final int width;
  final int height;

  const GolShareEncodeResult({
    required this.uri,
    required this.payloadBytes,
    required this.urlLength,
    required this.encodingMode,
    required this.qrReadable,
    required this.truncated,
    required this.cellCount,
    required this.width,
    required this.height,
  });
}

/// Compact binary v1 encoder/decoder for sharing Game of Life boards via URL
/// and QR code (`https://gol.puzzak.page/v?d=...` and `gol://v?d=...`).
class GolShareLink {
  const GolShareLink._();

  static const String shareHost = 'gol.puzzak.page';
  static const String sharePath = '/v';
  static const String customScheme = 'gol';
  static const int maxQrUrlLength = 900;
  static const int maxShareCells = 16384;
  static const int maxShareSpan = 512;

  static const int _maxNameBytes = 48;
  static const List<String> _modeNames = <String>['bitset', 'delta', 'rle'];

  /// Encodes an iterable of `(x, y)` cell coordinates into a compact share URI.
  static GolShareEncodeResult encodeCells(
    Iterable<(int, int)> cells, {
    GolRule? rule,
    GridTopology topology = GridTopology.infinite,
    GolPalette palette = GolPalette.system,
    String? name,
  }) {
    final GolRule effectiveRule = rule ?? GolRule.conway;
    final String? trimmedName =
        (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    final List<int>? nameBytes =
        trimmedName != null ? _encodeUtf8Clamped(trimmedName, _maxNameBytes) : null;
    final bool hasName = nameBytes != null && nameBytes.isNotEmpty;
    final bool hasCustomRule = effectiveRule.notation != GolRule.conway.notation;

    final _NormalizedCells normalized = _normalizeAndCap(cells);
    final int width = normalized.width;
    final int height = normalized.height;
    final List<int> indices = normalized.indices;

    final Uint8List bitsetBody = _encodeBitset(indices, width, height);
    final Uint8List deltaBody = _encodeDelta(indices);
    final Uint8List rleBody = _encodeRle(indices);

    int bestMode = 0;
    Uint8List bestBody = bitsetBody;
    if (deltaBody.length < bestBody.length) {
      bestMode = 1;
      bestBody = deltaBody;
    }
    if (rleBody.length < bestBody.length) {
      bestMode = 2;
      bestBody = rleBody;
    }

    final BytesBuilder out = BytesBuilder(copy: false);
    final int flags = (bestMode & 0x03) |
        (hasCustomRule ? 0x04 : 0) |
        (hasName ? 0x08 : 0) |
        ((topology.index & 0x03) << 4);
    out.addByte(flags);
    out.addByte(palette.index & 0x0F);

    if (hasCustomRule) {
      final int b = effectiveRule.birthMask & 0x1FF;
      final int s = effectiveRule.survivalMask & 0x1FF;
      out.addByte(b & 0xFF);
      out.addByte(((b >> 8) & 0x01) | ((s & 0x7F) << 1));
      out.addByte((s >> 7) & 0x03);
    }

    if (hasName) {
      _writeLeb128(out, nameBytes.length);
      out.add(nameBytes);
    }

    _writeLeb128(out, width);
    _writeLeb128(out, height);
    out.add(bestBody);

    final Uint8List payload = out.toBytes();
    final String token = base64Url.encode(payload).replaceAll('=', '');
    final Uri uri = Uri(
      scheme: 'https',
      host: shareHost,
      path: sharePath,
      queryParameters: <String, String>{'d': token},
    );
    final int urlLength = uri.toString().length;

    return GolShareEncodeResult(
      uri: uri,
      payloadBytes: payload.length,
      urlLength: urlLength,
      encodingMode: _modeNames[bestMode],
      qrReadable: urlLength <= maxQrUrlLength,
      truncated: normalized.truncated,
      cellCount: indices.length,
      width: width,
      height: height,
    );
  }

  /// Encodes a [GolPattern] by decoding its RLE into normalized cells.
  static GolShareEncodeResult encodePattern(
    GolPattern pattern, {
    GolRule? rule,
    GridTopology topology = GridTopology.infinite,
    GolPalette palette = GolPalette.system,
  }) {
    final DecodedPattern decoded = RleCodec.decode(pattern.rle);
    final GolRule effectiveRule = rule ??
        (decoded.rule != null ? GolRule.tryParse(decoded.rule!) : null) ??
        GolRule.conway;
    final String? effectiveName =
        pattern.name.trim().isNotEmpty ? pattern.name : decoded.name;

    return encodeCells(
      decoded.cells,
      rule: effectiveRule,
      topology: topology,
      palette: palette,
      name: effectiveName,
    );
  }

  /// Parses a share URL, custom scheme URI, or raw query string into a
  /// [SharedGolPayload]. Returns `null` if invalid, unsupported, or corrupted.
  static SharedGolPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final String? token = _extractToken(trimmed);
    if (token == null || token.isEmpty) return null;

    final Uint8List data;
    try {
      data = base64Url.decode(base64Url.normalize(token));
    } on FormatException {
      return null;
    }

    if (data.length < 4) return null;

    int offset = 0;
    final int flags = data[offset++];
    final int version = (flags >> 6) & 0x03;
    if (version != 0) return null;

    final int mode = flags & 0x03;
    if (mode > 2) return null;

    final bool hasCustomRule = (flags & 0x04) != 0;
    final bool hasName = (flags & 0x08) != 0;
    final int topologyIndex = (flags >> 4) & 0x03;
    if (topologyIndex >= GridTopology.values.length) return null;
    final GridTopology topology = GridTopology.values[topologyIndex];

    final int paletteIndex = data[offset++] & 0x0F;
    if (paletteIndex >= GolPalette.values.length) return null;
    final GolPalette palette = GolPalette.values[paletteIndex];

    GolRule rule = GolRule.conway;
    if (hasCustomRule) {
      if (offset + 3 > data.length) return null;
      final int b0 = data[offset++];
      final int b1 = data[offset++];
      final int b2 = data[offset++];
      final int birthMask = b0 | ((b1 & 0x01) << 8);
      final int survivalMask = ((b1 >> 1) & 0x7F) | ((b2 & 0x03) << 7);
      rule = _ruleFromMasks(birthMask, survivalMask);
    }

    String? name;
    if (hasName) {
      final _LebResult? nameLenRes = _readLeb128(data, offset);
      if (nameLenRes == null) return null;
      offset = nameLenRes.nextOffset;
      final int nameLen = nameLenRes.value;
      if (nameLen < 0 || nameLen > _maxNameBytes || offset + nameLen > data.length) {
        return null;
      }
      try {
        name = utf8.decode(
          data.sublist(offset, offset + nameLen),
          allowMalformed: false,
        );
      } on FormatException {
        return null;
      }
      offset += nameLen;
    }

    final _LebResult? widthRes = _readLeb128(data, offset);
    if (widthRes == null) return null;
    offset = widthRes.nextOffset;

    final _LebResult? heightRes = _readLeb128(data, offset);
    if (heightRes == null) return null;
    offset = heightRes.nextOffset;

    final int width = widthRes.value;
    final int height = heightRes.value;
    if (width < 0 || height < 0 || width > maxShareSpan || height > maxShareSpan) {
      return null;
    }
    if ((width == 0) != (height == 0)) return null;

    final List<(int, int)>? cells = switch (mode) {
      0 => _decodeBitset(data, offset, width, height),
      1 => _decodeDelta(data, offset, width, height),
      2 => _decodeRle(data, offset, width, height),
      _ => null,
    };
    if (cells == null) return null;

    return SharedGolPayload(
      cells: cells,
      width: width,
      height: height,
      rule: rule,
      topology: topology,
      palette: palette,
      name: name,
      encodingMode: _modeNames[mode],
    );
  }

  static String? _extractToken(String trimmed) {
    if (trimmed.startsWith('?')) {
      try {
        return Uri.splitQueryString(trimmed.substring(1))['d'];
      } on FormatException {
        return null;
      }
    }
    if (trimmed.startsWith('d=')) {
      try {
        return Uri.splitQueryString(trimmed)['d'];
      } on FormatException {
        return null;
      }
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;

    final String scheme = uri.scheme.toLowerCase();
    final String host = uri.host.toLowerCase();
    final String path = uri.path;

    if (scheme == customScheme) {
      if (host == 'v' || (host.isEmpty && (path == '/v' || path == '/v/'))) {
        return uri.queryParameters['d'];
      }
      return null;
    }

    if (scheme == 'https' || scheme == 'http') {
      if (host == shareHost && (path == sharePath || path == '$sharePath/')) {
        return uri.queryParameters['d'];
      }
      if (host == 'puzzak.page' && (path == '/gol/v' || path == '/gol/v/')) {
        return uri.queryParameters['d'];
      }
      return null;
    }

    return null;
  }

  static _NormalizedCells _normalizeAndCap(Iterable<(int, int)> rawCells) {
    final Set<(int, int)> unique = <(int, int)>{};
    int minX = 0;
    int minY = 0;
    bool first = true;

    for (final (int x, int y) in rawCells) {
      if (unique.add((x, y))) {
        if (first) {
          minX = x;
          minY = y;
          first = false;
        } else {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
        }
      }
    }

    if (unique.isEmpty) {
      return const _NormalizedCells(
        indices: <int>[],
        width: 0,
        height: 0,
        truncated: false,
      );
    }

    bool truncated = false;
    final List<(int, int)> shifted = <(int, int)>[];
    for (final (int x, int y) in unique) {
      final int nx = x - minX;
      final int ny = y - minY;
      if (nx >= maxShareSpan || ny >= maxShareSpan) {
        truncated = true;
        continue;
      }
      shifted.add((nx, ny));
    }

    shifted.sort(((int, int) a, (int, int) b) {
      final int cy = a.$2.compareTo(b.$2);
      return cy != 0 ? cy : a.$1.compareTo(b.$1);
    });

    if (shifted.length > maxShareCells) {
      shifted.length = maxShareCells;
      truncated = true;
    }

    if (shifted.isEmpty) {
      return _NormalizedCells(
        indices: const <int>[],
        width: 0,
        height: 0,
        truncated: truncated,
      );
    }

    int maxX = 0;
    int maxY = 0;
    for (final (int x, int y) in shifted) {
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    final int width = maxX + 1;
    final int height = maxY + 1;
    final List<int> indices = List<int>.generate(
      shifted.length,
      (int i) => shifted[i].$2 * width + shifted[i].$1,
      growable: false,
    );

    return _NormalizedCells(
      indices: indices,
      width: width,
      height: height,
      truncated: truncated,
    );
  }

  static Uint8List _encodeBitset(List<int> indices, int width, int height) {
    final int byteLen = (width * height + 7) >> 3;
    final Uint8List bytes = Uint8List(byteLen);
    for (final int idx in indices) {
      bytes[idx >> 3] |= 1 << (idx & 7);
    }
    return bytes;
  }

  static List<(int, int)>? _decodeBitset(
    Uint8List data,
    int offset,
    int width,
    int height,
  ) {
    final int total = width * height;
    final int expectedBytes = (total + 7) >> 3;
    if (data.length - offset != expectedBytes) return null;

    final List<(int, int)> cells = <(int, int)>[];
    for (int idx = 0; idx < total; idx++) {
      if ((data[offset + (idx >> 3)] & (1 << (idx & 7))) != 0) {
        if (cells.length >= maxShareCells) return null;
        cells.add((idx % width, idx ~/ width));
      }
    }
    return cells;
  }

  static Uint8List _encodeDelta(List<int> indices) {
    final BytesBuilder out = BytesBuilder(copy: false);
    _writeLeb128(out, indices.length);
    int prev = -1;
    for (final int idx in indices) {
      _writeLeb128(out, idx - prev - 1);
      prev = idx;
    }
    return out.toBytes();
  }

  static List<(int, int)>? _decodeDelta(
    Uint8List data,
    int offset,
    int width,
    int height,
  ) {
    final _LebResult? countRes = _readLeb128(data, offset);
    if (countRes == null) return null;
    offset = countRes.nextOffset;

    final int count = countRes.value;
    final int total = width * height;
    if (count < 0 || count > maxShareCells || count > total) return null;

    final List<(int, int)> cells = <(int, int)>[];
    int prev = -1;
    for (int i = 0; i < count; i++) {
      final _LebResult? deltaRes = _readLeb128(data, offset);
      if (deltaRes == null) return null;
      offset = deltaRes.nextOffset;

      final int idx = prev + 1 + deltaRes.value;
      if (idx < 0 || idx >= total) return null;
      cells.add((idx % width, idx ~/ width));
      prev = idx;
    }

    if (offset != data.length) return null;
    return cells;
  }

  static Uint8List _encodeRle(List<int> indices) {
    if (indices.isEmpty) return Uint8List(0);
    final BytesBuilder out = BytesBuilder(copy: false);
    int cursor = 0;
    int i = 0;

    while (i < indices.length) {
      final int startIdx = indices[i];
      final int deadRun = startIdx - cursor;
      int liveRun = 1;
      while (i + liveRun < indices.length &&
          indices[i + liveRun] == startIdx + liveRun) {
        liveRun++;
      }
      _writeLeb128(out, deadRun);
      _writeLeb128(out, liveRun);
      cursor = startIdx + liveRun;
      i += liveRun;
    }
    return out.toBytes();
  }

  static List<(int, int)>? _decodeRle(
    Uint8List data,
    int offset,
    int width,
    int height,
  ) {
    final int total = width * height;
    final List<(int, int)> cells = <(int, int)>[];
    int cursor = 0;

    while (offset < data.length) {
      final _LebResult? deadRes = _readLeb128(data, offset);
      if (deadRes == null) return null;
      offset = deadRes.nextOffset;

      if (deadRes.value < 0 || cursor + deadRes.value > total) return null;
      cursor += deadRes.value;

      if (offset >= data.length) {
        break;
      }

      final _LebResult? liveRes = _readLeb128(data, offset);
      if (liveRes == null) return null;
      offset = liveRes.nextOffset;

      final int liveRun = liveRes.value;
      if (liveRun == 0) break;
      if (liveRun < 0 ||
          cursor + liveRun > total ||
          cells.length + liveRun > maxShareCells) {
        return null;
      }

      for (int k = 0; k < liveRun; k++) {
        final int idx = cursor + k;
        cells.add((idx % width, idx ~/ width));
      }
      cursor += liveRun;
    }

    return cells;
  }

  static GolRule _ruleFromMasks(int birthMask, int survivalMask) {
    for (final GolRule preset in GolRule.presets) {
      if (preset.birthMask == birthMask && preset.survivalMask == survivalMask) {
        return preset;
      }
    }
    final String canonical =
        'B${_maskToDigits(birthMask)}/S${_maskToDigits(survivalMask)}';
    return GolRule(
      id: canonical,
      name: canonical,
      birthMask: birthMask,
      survivalMask: survivalMask,
      notation: canonical,
    );
  }

  static String _maskToDigits(int mask) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i <= 8; i++) {
      if ((mask & (1 << i)) != 0) {
        buffer.write(i);
      }
    }
    return buffer.toString();
  }

  static List<int> _encodeUtf8Clamped(String input, int maxBytes) {
    final List<int> out = <int>[];
    for (final int rune in input.runes) {
      final List<int> encoded = utf8.encode(String.fromCharCode(rune));
      if (out.length + encoded.length > maxBytes) break;
      out.addAll(encoded);
    }
    return out;
  }

  static void _writeLeb128(BytesBuilder out, int value) {
    int v = math.max(0, value);
    do {
      int byte = v & 0x7F;
      v >>= 7;
      if (v != 0) byte |= 0x80;
      out.addByte(byte);
    } while (v != 0);
  }

  static _LebResult? _readLeb128(Uint8List data, int offset) {
    int result = 0;
    int shift = 0;
    while (offset < data.length) {
      final int byte = data[offset++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        return _LebResult(value: result, nextOffset: offset);
      }
      shift += 7;
      if (shift >= 35) return null;
    }
    return null;
  }
}

class _NormalizedCells {
  final List<int> indices;
  final int width;
  final int height;
  final bool truncated;

  const _NormalizedCells({
    required this.indices,
    required this.width,
    required this.height,
    required this.truncated,
  });
}

class _LebResult {
  final int value;
  final int nextOffset;

  const _LebResult({
    required this.value,
    required this.nextOffset,
  });
}
