import 'package:flutter_test/flutter_test.dart';
import 'package:gol/engine/gol_models.dart';
import 'package:gol/engine/gol_share_link.dart';
import 'package:gol/engine/pattern_library.dart';
import 'package:gol/engine/rle_codec.dart';

void main() {
  group('GolShareLink', () {
    test('bitset mode wins for dense checkerboard and round-trips', () {
      // 12x12 checkerboard (72 cells): bitset = 18B, delta = 73B, rle = 144B.
      final List<(int, int)> cells = <(int, int)>[];
      for (int y = 0; y < 12; y++) {
        for (int x = 0; x < 12; x++) {
          if ((x + y).isEven) {
            cells.add((x + 10, y + 20)); // non-zero origin to test normalization
          }
        }
      }

      final GolShareEncodeResult encoded = GolShareLink.encodeCells(cells);
      expect(encoded.encodingMode, 'bitset');
      expect(encoded.width, 12);
      expect(encoded.height, 12);
      expect(encoded.cellCount, 72);
      expect(encoded.truncated, isFalse);

      final SharedGolPayload? decoded =
          GolShareLink.tryParse(encoded.uri.toString());
      expect(decoded, isNotNull);
      expect(decoded!.encodingMode, 'bitset');
      expect(decoded.width, 12);
      expect(decoded.height, 12);
      expect(decoded.cells.length, 72);

      final Set<(int, int)> expected = <(int, int)>{
        for (final (int x, int y) in cells) (x - 10, y - 20),
      };
      expect(decoded.cells.toSet(), expected);
    });

    test('delta mode wins for sparse distant cells and round-trips', () {
      final List<(int, int)> cells = <(int, int)>[
        (0, 0),
        (120, 80),
        (250, 200),
      ];

      final GolShareEncodeResult encoded = GolShareLink.encodeCells(cells);
      expect(encoded.encodingMode, 'delta');
      expect(encoded.width, 251);
      expect(encoded.height, 201);
      expect(encoded.cellCount, 3);

      final SharedGolPayload? decoded =
          GolShareLink.tryParse(encoded.uri.toString());
      expect(decoded, isNotNull);
      expect(decoded!.encodingMode, 'delta');
      expect(decoded.cells, cells);
    });

    test('rle mode wins for long horizontal runs and round-trips', () {
      // 100x20 grid with 5 horizontal lines of length 80 -> 400 cells.
      final List<(int, int)> cells = <(int, int)>[];
      for (int row = 0; row < 5; row++) {
        final int y = row * 4;
        for (int x = 0; x < 80; x++) {
          cells.add((x, y));
        }
      }
      // Ensure bounding width is 100
      cells.add((99, 19));

      final GolShareEncodeResult encoded = GolShareLink.encodeCells(cells);
      expect(encoded.encodingMode, 'rle');
      expect(encoded.width, 100);
      expect(encoded.height, 20);
      expect(encoded.cellCount, 401);

      final SharedGolPayload? decoded =
          GolShareLink.tryParse(encoded.uri.toString());
      expect(decoded, isNotNull);
      expect(decoded!.encodingMode, 'rle');
      expect(decoded.cells.toSet(), cells.toSet());
    });

    test('Gosper Glider Gun encodes to compact QR-readable URL (< 250 chars)',
        () {
      final GolShareEncodeResult encoded =
          GolShareLink.encodePattern(PatternLibrary.gosperGliderGun);
      expect(encoded.qrReadable, isTrue);
      expect(encoded.urlLength, lessThan(250));
      expect(encoded.uri.host, GolShareLink.shareHost);
      expect(encoded.uri.path, GolShareLink.sharePath);

      final SharedGolPayload? decoded =
          GolShareLink.tryParse(encoded.uri.toString());
      expect(decoded, isNotNull);
      expect(decoded!.name, PatternLibrary.gosperGliderGun.name);
      final DecodedPattern gun =
          RleCodec.decode(PatternLibrary.gosperGliderGun.rle);
      expect(decoded.cells.toSet(), gun.cells.toSet());
    });

    test('custom rule, topology, palette, and Unicode name round-trip', () {
      final GolRule customRule = GolRule.tryParse('B36/S23')!;
      const String unicodeName = 'Глайдер ✨ Життя';
      final List<(int, int)> cells = <(int, int)>[
        (1, 0),
        (2, 1),
        (0, 2),
        (1, 2),
        (2, 2),
      ];

      final GolShareEncodeResult encoded = GolShareLink.encodeCells(
        cells,
        rule: customRule,
        topology: GridTopology.toroidal,
        palette: GolPalette.ukraine,
        name: unicodeName,
      );

      final SharedGolPayload? decoded =
          GolShareLink.tryParse(encoded.uri.toString());
      expect(decoded, isNotNull);
      expect(decoded!.rule, customRule);
      expect(decoded.rule.notation, 'B36/S23');
      expect(decoded.topology, GridTopology.toroidal);
      expect(decoded.palette, GolPalette.ukraine);
      expect(decoded.name, unicodeName);
      expect(decoded.cells.toSet(), cells.toSet());
    });

    test('parses all supported URL and query formats', () {
      final GolShareEncodeResult encoded =
          GolShareLink.encodeCells(<(int, int)>[(0, 0), (1, 1), (2, 0)]);
      final String token = encoded.uri.queryParameters['d']!;

      final List<String> variants = <String>[
        'https://gol.puzzak.page/v?d=$token',
        'https://puzzak.page/gol/v?d=$token',
        'gol://v?d=$token',
        '?d=$token',
        'd=$token',
      ];

      for (final String raw in variants) {
        final SharedGolPayload? parsed = GolShareLink.tryParse(raw);
        expect(parsed, isNotNull, reason: 'Failed to parse: $raw');
        expect(parsed!.cells, <(int, int)>[(0, 0), (2, 0), (1, 1)]);
      }
    });

    test('malformed, empty, and corrupted inputs return null safely', () {
      expect(GolShareLink.tryParse(null), isNull);
      expect(GolShareLink.tryParse(''), isNull);
      expect(GolShareLink.tryParse('   '), isNull);
      expect(GolShareLink.tryParse('https://example.com/v?d=AAAA'), isNull);
      expect(GolShareLink.tryParse('https://gol.puzzak.page/v'), isNull);
      expect(GolShareLink.tryParse('https://gol.puzzak.page/v?d='), isNull);
      expect(GolShareLink.tryParse('https://gol.puzzak.page/v?d=!!!'), isNull);
      expect(GolShareLink.tryParse('gol://v?d=AA'), isNull); // too short
      // Version != 0 (bits 6..7 set -> 0x40)
      expect(GolShareLink.tryParse('d=QAABAAE'), isNull);
      // Unsupported mode 3 (0x03)
      expect(GolShareLink.tryParse('d=AwABAAE'), isNull);
      // Truncated custom rule
      expect(GolShareLink.tryParse('d=BAAAAA'), isNull);
    });
  });
}
