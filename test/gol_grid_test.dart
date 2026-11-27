import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gol/engine/gol_grid.dart';
import 'package:gol/engine/gol_models.dart';
import 'package:gol/engine/pattern_library.dart';
import 'package:gol/engine/rle_codec.dart';

void main() {
  group('GolGrid topologies & rules', () {
    test('Blinker oscillates with period 2 in Infinite mode', () {
      final GolGrid grid = GolGrid(topology: GridTopology.infinite);
      // Horizontal blinker at y = 0: (-1, 0), (0, 0), (1, 0)
      grid.setCell(-1, 0, true);
      grid.setCell(0, 0, true);
      grid.setCell(1, 0, true);
      expect(grid.population, 3);
      expect(grid.generation, 0);

      // Generation 1: vertical blinker at x = 0: (0, -1), (0, 0), (0, 1)
      grid.step(GolRule.conway);
      expect(grid.generation, 1);
      expect(grid.population, 3);
      expect(grid.getCell(0, -1), isTrue);
      expect(grid.getCell(0, 0), isTrue);
      expect(grid.getCell(0, 1), isTrue);
      expect(grid.getCell(-1, 0), isFalse);
      expect(grid.getCell(1, 0), isFalse);

      // Generation 2: returns to horizontal blinker
      grid.step(GolRule.conway);
      expect(grid.generation, 2);
      expect(grid.population, 3);
      expect(grid.getCell(-1, 0), isTrue);
      expect(grid.getCell(0, 0), isTrue);
      expect(grid.getCell(1, 0), isTrue);
      expect(grid.getCell(0, -1), isFalse);
      expect(grid.getCell(0, 1), isFalse);
    });

    test('Glider crosses 16x16 chunk boundaries including negative coordinates',
        () {
      final GolGrid grid = GolGrid(topology: GridTopology.infinite);
      final DecodedPattern glider = RleCodec.decode(PatternLibrary.glider.rle);

      // Start at (-2, -2) so the glider begins in chunk (-1, -1) and crosses
      // into (0, 0) and then past (16, 16) into chunk (1, 1).
      const int startX = -2;
      const int startY = -2;
      grid.stamp(glider.cells, startX, startY);
      expect(grid.population, 5);

      // A Conway glider translates by (+1, +1) every 4 generations.
      // After 80 generations (20 periods), it shifts by (+20, +20) to (18, 18),
      // crossing both the negative->positive 0 boundary and the 15->16 chunk boundary.
      const int periods = 20;
      for (int i = 0; i < periods * 4; i++) {
        grid.step(GolRule.conway);
      }

      expect(grid.generation, periods * 4);
      expect(grid.population, 5);

      for (final (int dx, int dy) in glider.cells) {
        expect(
          grid.getCell(startX + periods + dx, startY + periods + dy),
          isTrue,
          reason:
              'Expected glider cell at (${startX + periods + dx}, ${startY + periods + dy})',
        );
      }
    });

    test('Toroidal grid wraps cells seamlessly across edges', () {
      final GolGrid grid = GolGrid(
        topology: GridTopology.toroidal,
        width: 8,
        height: 8,
      );
      final DecodedPattern glider = RleCodec.decode(PatternLibrary.glider.rle);
      // Place glider near bottom-right corner so it wraps immediately.
      grid.stamp(glider.cells, 6, 6);
      expect(grid.population, 5);

      // After 8 periods (32 generations), a glider shifts by (+8, +8),
      // returning to the exact same coordinates on an 8x8 torus!
      for (int i = 0; i < 32; i++) {
        grid.step(GolRule.conway);
      }

      expect(grid.population, 5);
      for (final (int dx, int dy) in glider.cells) {
        final int wx = (6 + dx) % 8;
        final int wy = (6 + dy) % 8;
        expect(
          grid.getCell(wx, wy),
          isTrue,
          reason: 'Expected wrapped glider cell at ($wx, $wy)',
        );
      }
    });

    test('Bounded grid clips edges and ignores out-of-bounds cells', () {
      final GolGrid grid = GolGrid(
        topology: GridTopology.bounded,
        width: 8,
        height: 8,
      );

      // Out-of-bounds writes are ignored.
      grid.setCell(-1, 0, true);
      grid.setCell(8, 8, true);
      expect(grid.population, 0);

      // Vertical blinker along the right edge (x = 7, y = 2..4):
      // In infinite/toroidal mode, (8, 3) would be born; in bounded mode it is
      // clipped so only (6, 3) and (7, 3) survive on step 1, then die on step 2.
      grid.setCell(7, 2, true);
      grid.setCell(7, 3, true);
      grid.setCell(7, 4, true);
      expect(grid.population, 3);

      grid.step(GolRule.conway);
      expect(grid.getCell(6, 3), isTrue);
      expect(grid.getCell(7, 3), isTrue);
      expect(grid.getCell(0, 3), isFalse); // Must NOT wrap to x = 0.
      expect(grid.population, 2);

      grid.step(GolRule.conway);
      expect(grid.population, 0);
    });

    test('HighLife (B36/S23) births a dead cell with exactly 6 neighbors', () {
      final GolGrid conwayGrid = GolGrid(topology: GridTopology.infinite);
      final GolGrid highLifeGrid = GolGrid(topology: GridTopology.infinite);

      // Surround (0, 0) with 6 live neighbors.
      const List<(int, int)> sixNeighbors = <(int, int)>[
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (1, 0),
        (-1, 1),
      ];
      for (final (int x, int y) in sixNeighbors) {
        conwayGrid.setCell(x, y, true);
        highLifeGrid.setCell(x, y, true);
      }

      expect(conwayGrid.getCell(0, 0), isFalse);
      expect(highLifeGrid.getCell(0, 0), isFalse);

      conwayGrid.step(GolRule.conway);
      highLifeGrid.step(GolRule.highLife);

      expect(conwayGrid.getCell(0, 0), isFalse);
      expect(highLifeGrid.getCell(0, 0), isTrue);
    });
  });

  group('RleCodec & PatternLibrary', () {
    test('RleCodec encode/decode round-trip preserves normalized cells', () {
      const List<(int, int)> original = <(int, int)>[
        (10, 20),
        (11, 20),
        (12, 21),
        (10, 22),
        (14, 24),
      ];

      final RleEncodeResult encoded = RleCodec.encode(
        original,
        name: 'RoundTrip',
        rule: GolRule.conway.notation,
      );
      expect(encoded.truncated, isFalse);
      expect(encoded.cellCount, original.length);
      expect(encoded.width, 5);
      expect(encoded.height, 5);

      final DecodedPattern decoded = RleCodec.decode(encoded.rle);
      expect(decoded.name, 'RoundTrip');
      expect(decoded.rule, 'B3/S23');
      expect(decoded.width, 5);
      expect(decoded.height, 5);
      expect(
        decoded.cells.toSet(),
        equals(<(int, int)>{
          (0, 0),
          (1, 0),
          (2, 1),
          (0, 2),
          (4, 4),
        }),
      );
    });

    test('rotateCellsCW and flipCellsHorizontal transform accurately', () {
      // L-tromino: (0,0), (0,1), (1,1) -> width 2, height 2
      const List<(int, int)> lShape = <(int, int)>[(0, 0), (0, 1), (1, 1)];

      final ({List<(int, int)> cells, int width, int height}) rot90 =
          rotateCellsCW(lShape, 1);
      expect(rot90.width, 2);
      expect(rot90.height, 2);
      expect(rot90.cells.toSet(), equals(<(int, int)>{(1, 0), (0, 0), (0, 1)}));

      // Rotating 4 times returns to original normalized cells.
      final ({List<(int, int)> cells, int width, int height}) rot360 =
          rotateCellsCW(lShape, 4);
      expect(rot360.cells.toSet(), equals(lShape.toSet()));

      // Horizontal flip mirrors X: (0,0)->(1,0), (0,1)->(1,1), (1,1)->(0,1)
      final ({List<(int, int)> cells, int width, int height}) flipped =
          flipCellsHorizontal(lShape);
      expect(
          flipped.cells.toSet(), equals(<(int, int)>{(1, 0), (1, 1), (0, 1)}));
    });

    test('RleCodec.encode enforces maxCells and maxSpan truncation safely', () {
      // Exceed maxCells
      final List<(int, int)> manyCells = <(int, int)>[
        for (int i = 0; i < 50; i++) (i % 10, i ~/ 10),
      ];
      final RleEncodeResult cappedCells = RleCodec.encode(
        manyCells,
        maxCells: 12,
        maxSpan: 100,
      );
      expect(cappedCells.truncated, isTrue);
      expect(cappedCells.cellCount, 12);

      // Exceed maxSpan
      final List<(int, int)> wideCells = <(int, int)>[
        (0, 0),
        (1, 0),
        (25, 0),
        (0, 30),
      ];
      final RleEncodeResult cappedSpan = RleCodec.encode(
        wideCells,
        maxCells: 100,
        maxSpan: 10,
      );
      expect(cappedSpan.truncated, isTrue);
      expect(cappedSpan.cellCount, 2);
      expect(cappedSpan.width, lessThanOrEqualTo(10));
      expect(cappedSpan.height, lessThanOrEqualTo(10));
    });

    test('All PatternLibrary.builtInPatterns decode cleanly with live cells',
        () {
      expect(PatternLibrary.builtInPatterns, isNotEmpty);
      for (final GolPattern pattern in PatternLibrary.builtInPatterns) {
        final DecodedPattern decoded = RleCodec.decode(pattern.rle);
        expect(
          decoded.cells,
          isNotEmpty,
          reason: 'Built-in pattern "${pattern.id}" decoded to 0 cells',
        );
        expect(
          decoded.width,
          greaterThan(0),
          reason: 'Built-in pattern "${pattern.id}" has invalid width',
        );
        expect(
          decoded.height,
          greaterThan(0),
          reason: 'Built-in pattern "${pattern.id}" has invalid height',
        );
        expect(
          decoded.width,
          lessThanOrEqualTo(pattern.width),
          reason: 'Built-in pattern "${pattern.id}" width exceeds metadata',
        );
        expect(
          decoded.height,
          lessThanOrEqualTo(pattern.height),
          reason: 'Built-in pattern "${pattern.id}" height exceeds metadata',
        );
      }
    });

    test(
        'LifeWiki catalog.json has >= 30 valid patterns and heavy pattern steps cleanly',
        () {
      final File catalogFile = File('assets/patterns/catalog.json');
      expect(catalogFile.existsSync(), isTrue);

      final List<dynamic> rawList =
          jsonDecode(catalogFile.readAsStringSync()) as List<dynamic>;
      expect(rawList.length, greaterThanOrEqualTo(30));

      Map<String, dynamic>? heavyPatternJson;
      for (final dynamic item in rawList) {
        final Map<String, dynamic> entry = item as Map<String, dynamic>;
        final String name = (entry['name'] as String? ?? '').trim();
        final String author = (entry['author'] as String? ?? '').trim();
        final String wikiUrl = (entry['wikiUrl'] as String? ?? '').trim();
        final String rle = entry['rle'] as String? ?? '';
        final String category = entry['category'] as String? ?? '';

        expect(name, isNotEmpty, reason: 'Catalog entry missing name');
        expect(author, isNotEmpty, reason: 'Catalog entry "$name" missing author');
        expect(
          wikiUrl,
          isNotEmpty,
          reason: 'Catalog entry "$name" missing wikiUrl',
        );

        final DecodedPattern decoded = RleCodec.decode(rle);
        expect(
          decoded.cells,
          isNotEmpty,
          reason: 'Catalog entry "$name" decoded to 0 cells',
        );

        if (heavyPatternJson == null &&
            (category == 'gun' || category == 'puffer')) {
          heavyPatternJson = entry;
        }
      }

      expect(
        heavyPatternJson,
        isNotNull,
        reason: 'Expected at least one gun or puffer in catalog.json',
      );
      final DecodedPattern heavyDecoded =
          RleCodec.decode(heavyPatternJson!['rle'] as String);
      final GolGrid grid = GolGrid(topology: GridTopology.infinite);
      grid.stamp(heavyDecoded.cells, 0, 0);
      expect(grid.population, greaterThan(0));

      for (int i = 0; i < 30; i++) {
        grid.step(GolRule.conway);
      }
      expect(grid.generation, 30);
      expect(grid.population, greaterThan(0));
    });
  });

  group('GolGrid extractRegion & snapshot undo/restore', () {
    test('extractRegion returns only live cells within the requested bounds',
        () {
      final GolGrid grid = GolGrid(topology: GridTopology.infinite);
      grid.setCell(-5, -5, true);
      grid.setCell(0, 0, true);
      grid.setCell(2, 3, true);
      grid.setCell(10, 10, true);

      final List<(int, int)> region = grid.extractRegion(-1, -1, 4, 4);
      expect(region.toSet(), equals(<(int, int)>{(0, 0), (2, 3)}));

      final List<(int, int)> capped =
          grid.extractRegion(-10, -10, 20, 20, maxCells: 2);
      expect(capped.length, 2);
    });

    test('takeSnapshot and restoreSnapshot preserve grid state across mutations',
        () {
      final GolGrid grid = GolGrid(topology: GridTopology.infinite);
      grid.setCell(-3, 4, true);
      grid.setCell(-2, 4, true);
      grid.setCell(-1, 4, true);
      grid.step(GolRule.conway);

      final GolGridSnapshot snapshot = grid.takeSnapshot();
      expect(snapshot.generation, 1);
      expect(snapshot.population, 3);

      // Mutate and advance further
      grid.setCell(20, 20, true);
      grid.step(GolRule.conway);
      grid.step(GolRule.conway);
      expect(grid.generation, 3);

      // Restore snapshot
      grid.restoreSnapshot(snapshot);
      expect(grid.generation, 1);
      expect(grid.population, 3);
      expect(grid.getCell(-2, 3), isTrue);
      expect(grid.getCell(-2, 4), isTrue);
      expect(grid.getCell(-2, 5), isTrue);
      expect(grid.getCell(20, 20), isFalse);
    });
  });
}
