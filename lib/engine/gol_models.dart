import 'package:flutter/material.dart';

/// Simulation grid boundary behavior.
enum GridTopology {
  infinite(
    translationKey: 'topology_infinite',
    shortLabel: '∞',
  ),
  toroidal(
    translationKey: 'topology_toroidal',
    shortLabel: 'Toroid',
  ),
  bounded(
    translationKey: 'topology_bounded',
    shortLabel: 'Bound',
  );

  final String translationKey;
  final String shortLabel;

  const GridTopology({
    required this.translationKey,
    required this.shortLabel,
  });
}

/// Interactive tool active on the simulation canvas.
enum CanvasTool {
  draw(translationKey: 'tool_draw'),
  pan(translationKey: 'tool_pan'),
  stamp(translationKey: 'tool_stamp'),
  crop(translationKey: 'tool_crop');

  final String translationKey;

  const CanvasTool({required this.translationKey});
}

/// Visual color palette for live cells, aged cells, background, and grid lines.
enum GolPalette {
  system(translationKey: 'palette_system'),
  classic(translationKey: 'palette_classic'),
  emerald(translationKey: 'palette_emerald'),
  amber(translationKey: 'palette_amber'),
  neon(translationKey: 'palette_neon'),
  sunset(translationKey: 'palette_sunset'),
  ukraine(translationKey: 'palette_ukraine');

  final String translationKey;

  const GolPalette({required this.translationKey});

  /// Returns swatch colors for palette picker previews.
  List<Color> previewColors(ColorScheme scheme) {
    final ({Color alive, Color aged, Color background, Color gridLine})
        resolved = resolveColors(scheme);
    return <Color>[
      resolved.background,
      resolved.alive,
      resolved.aged,
    ];
  }

  /// Resolves concrete colors for the given Material [ColorScheme].
  ({Color alive, Color aged, Color background, Color gridLine}) resolveColors(
    ColorScheme scheme,
  ) {
    switch (this) {
      case GolPalette.system:
        final bool isDark = scheme.brightness == Brightness.dark;
        return (
          alive: scheme.primary,
          aged: scheme.tertiary,
          background: scheme.surface,
          gridLine: isDark
              ? scheme.outlineVariant.withValues(alpha: 0.25)
              : scheme.outlineVariant.withValues(alpha: 0.35),
        );
      case GolPalette.classic:
        final bool isDark = scheme.brightness == Brightness.dark;
        return isDark
            ? (
                alive: const Color(0xFFF5F5F5),
                aged: const Color(0xFF9E9E9E),
                background: const Color(0xFF0E0E10),
                gridLine: const Color(0xFF26262B),
              )
            : (
                alive: const Color(0xFF141416),
                aged: const Color(0xFF616166),
                background: const Color(0xFFFAFAFC),
                gridLine: const Color(0xFFE0E0E6),
              );
      case GolPalette.emerald:
        return (
          alive: const Color(0xFF34D399),
          aged: const Color(0xFF059669),
          background: const Color(0xFF061410),
          gridLine: const Color(0xFF123026),
        );
      case GolPalette.amber:
        return (
          alive: const Color(0xFFFBBF24),
          aged: const Color(0xFFD97706),
          background: const Color(0xFF141008),
          gridLine: const Color(0xFF2E2412),
        );
      case GolPalette.neon:
        return (
          alive: const Color(0xFF22D3EE),
          aged: const Color(0xFFE879F9),
          background: const Color(0xFF08091A),
          gridLine: const Color(0xFF1B1F3B),
        );
      case GolPalette.sunset:
        return (
          alive: const Color(0xFFFB7185),
          aged: const Color(0xFFF59E0B),
          background: const Color(0xFF160B14),
          gridLine: const Color(0xFF33192C),
        );
      case GolPalette.ukraine:
        return (
          alive: const Color(0xFFFFD700),
          aged: const Color(0xFF0057B7),
          background: const Color(0xFF091224),
          gridLine: const Color(0xFF17284A),
        );
    }
  }
}

/// Outer-totalistic cellular automaton rule in B/S notation.
class GolRule {
  final String id;
  final String name;
  final int birthMask;
  final int survivalMask;
  final String notation;

  const GolRule({
    required this.id,
    required this.name,
    required this.birthMask,
    required this.survivalMask,
    required this.notation,
  });

  static const GolRule conway = GolRule(
    id: 'conway',
    name: 'Conway',
    birthMask: 1 << 3,
    survivalMask: (1 << 2) | (1 << 3),
    notation: 'B3/S23',
  );

  static const GolRule highLife = GolRule(
    id: 'highlife',
    name: 'HighLife',
    birthMask: (1 << 3) | (1 << 6),
    survivalMask: (1 << 2) | (1 << 3),
    notation: 'B36/S23',
  );

  static const GolRule dayAndNight = GolRule(
    id: 'day_and_night',
    name: 'Day & Night',
    birthMask: (1 << 3) | (1 << 6) | (1 << 7) | (1 << 8),
    survivalMask: (1 << 3) | (1 << 4) | (1 << 6) | (1 << 7) | (1 << 8),
    notation: 'B3678/S34678',
  );

  static const GolRule seeds = GolRule(
    id: 'seeds',
    name: 'Seeds',
    birthMask: 1 << 2,
    survivalMask: 0,
    notation: 'B2/S',
  );

  static const GolRule lifeWithoutDeath = GolRule(
    id: 'life_without_death',
    name: 'Life Without Death',
    birthMask: 1 << 3,
    survivalMask: 0x1FF,
    notation: 'B3/S012345678',
  );

  static const GolRule maze = GolRule(
    id: 'maze',
    name: 'Maze',
    birthMask: 1 << 3,
    survivalMask: (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5),
    notation: 'B3/S12345',
  );

  static const GolRule anneal = GolRule(
    id: 'anneal',
    name: 'Anneal',
    birthMask: (1 << 4) | (1 << 6) | (1 << 7) | (1 << 8),
    survivalMask: (1 << 3) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8),
    notation: 'B4678/S35678',
  );

  static const List<GolRule> presets = <GolRule>[
    conway,
    highLife,
    dayAndNight,
    seeds,
    lifeWithoutDeath,
    maze,
    anneal,
  ];

  /// Computes the next boolean state of a cell given [alive] and [neighbors].
  @pragma('vm:prefer-inline')
  bool nextState(bool alive, int neighbors) {
    final int bit = 1 << neighbors;
    return alive ? (survivalMask & bit) != 0 : (birthMask & bit) != 0;
  }

  /// Parses B/S rule notation (e.g. `B3/S23`, `B2/S`, `23/3`).
  ///
  /// Returns `null` if [notation] is invalid.
  static GolRule? tryParse(String notation) {
    final String trimmed = notation.trim().toUpperCase();
    if (trimmed.isEmpty) return null;

    final List<String> parts = trimmed.split('/');
    if (parts.length != 2) return null;

    String? bDigits;
    String? sDigits;

    final String p0 = parts[0].trim();
    final String p1 = parts[1].trim();

    if (p0.startsWith('B') && p1.startsWith('S')) {
      bDigits = p0.substring(1);
      sDigits = p1.substring(1);
    } else if (p0.startsWith('S') && p1.startsWith('B')) {
      sDigits = p0.substring(1);
      bDigits = p1.substring(1);
    } else if (!p0.contains('B') &&
        !p0.contains('S') &&
        !p1.contains('B') &&
        !p1.contains('S')) {
      // Standard S/B shorthand like "23/3".
      sDigits = p0;
      bDigits = p1;
    } else {
      return null;
    }

    final int? birthMask = _parseDigitMask(bDigits);
    final int? survivalMask = _parseDigitMask(sDigits);
    if (birthMask == null || survivalMask == null) return null;

    final String canonical =
        'B${_maskToDigits(birthMask)}/S${_maskToDigits(survivalMask)}';

    for (final GolRule preset in presets) {
      if (preset.birthMask == birthMask && preset.survivalMask == survivalMask) {
        return preset;
      }
    }

    return GolRule(
      id: canonical,
      name: canonical,
      birthMask: birthMask,
      survivalMask: survivalMask,
      notation: canonical,
    );
  }

  static int? _parseDigitMask(String digits) {
    int mask = 0;
    for (int i = 0; i < digits.length; i++) {
      final int code = digits.codeUnitAt(i);
      if (code < 48 || code > 56) {
        return null;
      }
      mask |= 1 << (code - 48);
    }
    return mask;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GolRule &&
          birthMask == other.birthMask &&
          survivalMask == other.survivalMask;

  @override
  int get hashCode => Object.hash(birthMask, survivalMask);
}

/// Taxonomy category for Game of Life patterns.
enum PatternCategory {
  stillLife(translationKey: 'category_still_life'),
  oscillator(translationKey: 'category_oscillator'),
  spaceship(translationKey: 'category_spaceship'),
  methuselah(translationKey: 'category_methuselah'),
  gun(translationKey: 'category_gun'),
  puffer(translationKey: 'cat_puffer'),
  custom(translationKey: 'category_custom');

  final String translationKey;

  const PatternCategory({required this.translationKey});
}

/// Named Game of Life pattern stored in RLE format.
class GolPattern {
  final String id;
  final String name;
  final PatternCategory category;
  final String rle;
  final int width;
  final int height;
  final int? period;
  final String description;
  final bool isBuiltIn;
  final String? author;
  final String? wikiUrl;

  const GolPattern({
    required this.id,
    required this.name,
    required this.category,
    required this.rle,
    required this.width,
    required this.height,
    this.period,
    this.description = '',
    this.isBuiltIn = false,
    this.author,
    this.wikiUrl,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category.name,
        'rle': rle,
        'width': width,
        'height': height,
        if (period != null) 'period': period,
        'description': description,
        'isBuiltIn': isBuiltIn,
        if (author != null) 'author': author,
        if (wikiUrl != null) 'wikiUrl': wikiUrl,
      };

  factory GolPattern.fromJson(Map<String, dynamic> json) {
    final String catName = json['category'] as String? ?? 'custom';
    final PatternCategory category = PatternCategory.values.firstWhere(
      (PatternCategory c) => c.name == catName,
      orElse: () => PatternCategory.custom,
    );
    return GolPattern(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Pattern',
      category: category,
      rle: json['rle'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      period: (json['period'] as num?)?.toInt(),
      description: json['description'] as String? ?? '',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      author: json['author'] as String?,
      wikiUrl: json['wikiUrl'] as String?,
    );
  }
}
