import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'gol_models.dart';
import 'rle_codec.dart';

/// Curated built-in Game of Life patterns following the Wikipedia taxonomy.
class PatternLibrary {
  const PatternLibrary._();

  static const List<GolPattern> builtInPatterns = <GolPattern>[
    // ── Still lifes ──────────────────────────────────────────────────────────
    GolPattern(
      id: 'block',
      name: 'Block',
      category: PatternCategory.stillLife,
      width: 2,
      height: 2,
      description: '2×2 square still life.',
      isBuiltIn: true,
      rle: '#N Block\n'
          'x = 2, y = 2, rule = B3/S23\n'
          '2o\$2o!',
    ),
    GolPattern(
      id: 'beehive',
      name: 'Bee-hive',
      category: PatternCategory.stillLife,
      width: 4,
      height: 3,
      description: '6-cell hexagonal still life.',
      isBuiltIn: true,
      rle: '#N Bee-hive\n'
          'x = 4, y = 3, rule = B3/S23\n'
          'b2ob\$o2bo\$b2o!',
    ),
    GolPattern(
      id: 'loaf',
      name: 'Loaf',
      category: PatternCategory.stillLife,
      width: 4,
      height: 4,
      description: '7-cell asymmetric still life.',
      isBuiltIn: true,
      rle: '#N Loaf\n'
          'x = 4, y = 4, rule = B3/S23\n'
          'b2ob\$o2bo\$bobo\$2bo!',
    ),
    GolPattern(
      id: 'boat',
      name: 'Boat',
      category: PatternCategory.stillLife,
      width: 3,
      height: 3,
      description: '5-cell still life.',
      isBuiltIn: true,
      rle: '#N Boat\n'
          'x = 3, y = 3, rule = B3/S23\n'
          '2ob\$obo\$bo!',
    ),
    GolPattern(
      id: 'tub',
      name: 'Tub',
      category: PatternCategory.stillLife,
      width: 3,
      height: 3,
      description: '4-cell symmetric still life.',
      isBuiltIn: true,
      rle: '#N Tub\n'
          'x = 3, y = 3, rule = B3/S23\n'
          'bob\$obo\$bo!',
    ),

    // ── Oscillators ──────────────────────────────────────────────────────────
    GolPattern(
      id: 'blinker',
      name: 'Blinker',
      category: PatternCategory.oscillator,
      width: 3,
      height: 1,
      period: 2,
      description: 'Smallest and most common period-2 oscillator.',
      isBuiltIn: true,
      rle: '#N Blinker\n'
          'x = 3, y = 1, rule = B3/S23\n'
          '3o!',
    ),
    GolPattern(
      id: 'toad',
      name: 'Toad',
      category: PatternCategory.oscillator,
      width: 4,
      height: 2,
      period: 2,
      description: '6-cell period-2 oscillator.',
      isBuiltIn: true,
      rle: '#N Toad\n'
          'x = 4, y = 2, rule = B3/S23\n'
          'b3o\$3o!',
    ),
    GolPattern(
      id: 'beacon',
      name: 'Beacon',
      category: PatternCategory.oscillator,
      width: 4,
      height: 4,
      period: 2,
      description: 'Two diagonally touching blocks forming a period-2 oscillator.',
      isBuiltIn: true,
      rle: '#N Beacon\n'
          'x = 4, y = 4, rule = B3/S23\n'
          '2o2b\$2o2b\$2b2o\$2b2o!',
    ),
    GolPattern(
      id: 'pulsar',
      name: 'Pulsar',
      category: PatternCategory.oscillator,
      width: 13,
      height: 13,
      period: 3,
      description: 'Most common period-3 oscillator with 4-fold symmetry.',
      isBuiltIn: true,
      rle: '#N Pulsar\n'
          'x = 13, y = 13, rule = B3/S23\n'
          '2b3o3b3o2b2\$o4bobo4bo\$o4bobo4bo\$o4bobo4bo\$2b3o3b3o2b2\$'
          '2b3o3b3o2b\$o4bobo4bo\$o4bobo4bo\$o4bobo4bo2\$2b3o3b3o!',
    ),
    GolPattern(
      id: 'pentadecathlon',
      name: 'Penta-decathlon',
      category: PatternCategory.oscillator,
      width: 10,
      height: 3,
      period: 15,
      description: 'Classic period-15 oscillator.',
      isBuiltIn: true,
      rle: '#N Penta-decathlon\n'
          'x = 10, y = 3, rule = B3/S23\n'
          '2bo4bo2b\$2ob4ob2o\$2bo4bo!',
    ),

    // ── Spaceships ───────────────────────────────────────────────────────────
    GolPattern(
      id: 'glider',
      name: 'Glider',
      category: PatternCategory.spaceship,
      width: 3,
      height: 3,
      period: 4,
      description: 'Smallest diagonal spaceship, moving at c/4.',
      isBuiltIn: true,
      rle: '#N Glider\n'
          'x = 3, y = 3, rule = B3/S23\n'
          'bob\$2bo\$3o!',
    ),
    GolPattern(
      id: 'lwss',
      name: 'Lightweight Spaceship (LWSS)',
      category: PatternCategory.spaceship,
      width: 5,
      height: 4,
      period: 4,
      description: 'Smallest orthogonal spaceship, moving at c/2.',
      isBuiltIn: true,
      rle: '#N LWSS\n'
          'x = 5, y = 4, rule = B3/S23\n'
          'bo2bo\$o4b\$o3bo\$4o!',
    ),
    GolPattern(
      id: 'mwss',
      name: 'Middleweight Spaceship (MWSS)',
      category: PatternCategory.spaceship,
      width: 6,
      height: 5,
      period: 4,
      description: 'Medium orthogonal spaceship, moving at c/2.',
      isBuiltIn: true,
      rle: '#N MWSS\n'
          'x = 6, y = 5, rule = B3/S23\n'
          '2bo3b\$o3bob\$5bo\$o4bo\$b5o!',
    ),
    GolPattern(
      id: 'hwss',
      name: 'Heavyweight Spaceship (HWSS)',
      category: PatternCategory.spaceship,
      width: 7,
      height: 5,
      period: 4,
      description: 'Largest standard orthogonal spaceship, moving at c/2.',
      isBuiltIn: true,
      rle: '#N HWSS\n'
          'x = 7, y = 5, rule = B3/S23\n'
          '2b2o3b\$o4bob\$6bo\$o5bo\$b6o!',
    ),

    // ── Methuselahs ──────────────────────────────────────────────────────────
    GolPattern(
      id: 'r_pentomino',
      name: 'R-pentomino',
      category: PatternCategory.methuselah,
      width: 3,
      height: 3,
      description: 'Stabilizes after 1103 generations, leaving 6 gliders.',
      isBuiltIn: true,
      rle: '#N R-pentomino\n'
          'x = 3, y = 3, rule = B3/S23\n'
          'b2o\$2ob\$bo!',
    ),
    GolPattern(
      id: 'diehard',
      name: 'Diehard',
      category: PatternCategory.methuselah,
      width: 8,
      height: 3,
      description: '7-cell pattern that vanishes completely after 130 generations.',
      isBuiltIn: true,
      rle: '#N Diehard\n'
          'x = 8, y = 3, rule = B3/S23\n'
          '6bob\$2o6b\$bo3b3o!',
    ),
    GolPattern(
      id: 'acorn',
      name: 'Acorn',
      category: PatternCategory.methuselah,
      width: 7,
      height: 3,
      description: '7-cell methuselah that stabilizes after 5206 generations.',
      isBuiltIn: true,
      rle: '#N Acorn\n'
          'x = 7, y = 3, rule = B3/S23\n'
          'bo5b\$3bo3b\$2o2b3o!',
    ),

    // ── Guns & Infinite Growth ───────────────────────────────────────────────
    GolPattern(
      id: 'gosper_glider_gun',
      name: 'Gosper Glider Gun',
      category: PatternCategory.gun,
      width: 36,
      height: 9,
      period: 30,
      description: 'First known finite pattern with unbounded growth (period 30).',
      isBuiltIn: true,
      rle: '#N Gosper Glider Gun\n'
          'x = 36, y = 9, rule = B3/S23\n'
          '24bo11b\$22bobo11b\$12b2o6b2o12b2o\$11bo3bo4b2o12b2o\$'
          '2o8bo5bo3b2o14b\$2o8bo3bob2o4bobo11b\$10bo5bo7bo11b\$'
          '11bo3bo20b\$12b2o!',
    ),
    GolPattern(
      id: 'simkin_glider_gun',
      name: 'Simkin Glider Gun',
      category: PatternCategory.gun,
      width: 33,
      height: 21,
      period: 120,
      description: 'Compact period-120 glider gun discovered in 2015.',
      isBuiltIn: true,
      rle: '#N Simkin Glider Gun\n'
          'x = 33, y = 21, rule = B3/S23\n'
          '2o5b2o24b\$2o5b2o24b2\$4b2o27b\$4b2o27b5\$22b2ob2o6b\$'
          '21bo5bo5b\$21bo6bo2b2o\$21b3o3bo3b2o\$26bo6b4\$20b2o11b\$'
          '20bo12b\$21b3o9b\$23bo!',
    ),
    GolPattern(
      id: 'infinite_growth_10',
      name: '10-Cell Infinite Growth',
      category: PatternCategory.gun,
      width: 8,
      height: 6,
      description: 'Minimal 10-cell pattern that grows without bound.',
      isBuiltIn: true,
      rle: '#N 10-cell Infinite Growth\n'
          'x = 8, y = 6, rule = B3/S23\n'
          '6bo\$4bobo\$4b2o\$2bo\$o\$bo!',
    ),
    GolPattern(
      id: 'infinite_growth_5x5',
      name: '5×5 Infinite Growth',
      category: PatternCategory.gun,
      width: 5,
      height: 5,
      description: 'Smallest bounding box (5×5) for an infinite-growth pattern.',
      isBuiltIn: true,
      rle: '#N 5x5 Infinite Growth\n'
          'x = 5, y = 5, rule = B3/S23\n'
          '3obo\$o4b\$3b2o\$b2obo\$obobo!',
    ),
  ];

  static GolPattern get gosperGliderGun => builtInPatterns
      .firstWhere((GolPattern p) => p.id == 'gosper_glider_gun');

  static GolPattern get glider =>
      builtInPatterns.firstWhere((GolPattern p) => p.id == 'glider');

  static GolPattern get blinker =>
      builtInPatterns.firstWhere((GolPattern p) => p.id == 'blinker');

  /// Loads the bundled pattern catalog from `assets/patterns/catalog.json`,
  /// falling back to [builtInPatterns] on any error.
  static Future<List<GolPattern>> loadCatalog() async {
    try {
      final String raw =
          await rootBundle.loadString('assets/patterns/catalog.json');
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return builtInPatterns;

      final List<GolPattern> patterns = <GolPattern>[];
      for (final dynamic item in decoded) {
        if (item is! Map) continue;
        final GolPattern parsed =
            GolPattern.fromJson(Map<String, dynamic>.from(item));
        if (parsed.width <= 0 || parsed.height <= 0) {
          final DecodedPattern rleDecoded = RleCodec.decode(parsed.rle);
          patterns.add(
            GolPattern(
              id: parsed.id,
              name: parsed.name,
              category: parsed.category,
              rle: parsed.rle,
              width: parsed.width > 0 ? parsed.width : rleDecoded.width,
              height: parsed.height > 0 ? parsed.height : rleDecoded.height,
              period: parsed.period,
              description: parsed.description,
              isBuiltIn: parsed.isBuiltIn,
              author: parsed.author,
              wikiUrl: parsed.wikiUrl,
            ),
          );
        } else {
          patterns.add(parsed);
        }
      }
      return patterns.isEmpty ? builtInPatterns : patterns;
    } catch (_) {
      return builtInPatterns;
    }
  }
}
