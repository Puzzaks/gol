import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/gol_engine.dart';
import '../engine/gol_models.dart';
import '../engine/rle_codec.dart';
import 'app_toast.dart';
import 'share_sheet.dart';

String _trOr(GolEngine engine, String key, String fallback) {
  final String value = engine.tr(key);
  if (value.isEmpty || value == key || value.startsWith('!')) {
    return fallback;
  }
  return value;
}

/// Cache of decoded RLE patterns for smooth scrolling thumbnails.
final Map<String, DecodedPattern> _decodedCache = <String, DecodedPattern>{};

DecodedPattern _getDecoded(String rle) {
  return _decodedCache.putIfAbsent(rle, () => RleCodec.decode(rle));
}

/// Opens the rounded 28px Patterns modal bottom sheet with quick-save actions,
/// category filter chips, live mini-grid thumbnails, RLE share/import, and
/// stamp selection.
Future<void> showPatternsSheet(
  BuildContext context, {
  required Size viewportSize,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return _PatternsSheetContent(viewportSize: viewportSize);
    },
  );
}

/// Prompts the user for a pattern name and saves [cells] as a custom pattern
/// via [GolEngine.saveCustomPattern].
Future<void> showSavePatternDialog(
  BuildContext context, {
  required List<(int, int)> cells,
  String? defaultName,
  bool truncated = false,
}) async {
  final GolEngine engine = context.read<GolEngine>();
  final TextEditingController controller = TextEditingController(
    text: defaultName ?? 'Custom Pattern',
  );

  final String? chosenName = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(_trOr(engine, 'pattern_name', 'Pattern name')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: _trOr(engine, 'pattern_name', 'Pattern name'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (String value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            if (truncated) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Selection was capped to fit the maximum RLE size.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_trOr(engine, 'cancel', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(_trOr(engine, 'done', 'Done')),
          ),
        ],
      );
    },
  );

  controller.dispose();

  if (chosenName == null || !context.mounted) return;
  engine.saveCustomPattern(
    name: chosenName.isEmpty ? (defaultName ?? 'Custom Pattern') : chosenName,
    cells: cells,
  );
  showAppToast(context, _trOr(engine, 'pattern_saved', 'Pattern saved'));
}

enum _PatternFilter {
  all,
  saved,
  stillLife,
  oscillator,
  spaceship,
  methuselah,
  gun,
  puffer,
}

class _PatternsSheetContent extends StatefulWidget {
  final Size viewportSize;

  const _PatternsSheetContent({required this.viewportSize});

  @override
  State<_PatternsSheetContent> createState() => _PatternsSheetContentState();
}

class _PatternsSheetContentState extends State<_PatternsSheetContent> {
  _PatternFilter _filter = _PatternFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GolPattern> _filteredPatterns(GolEngine engine) {
    final List<GolPattern> all = <GolPattern>[
      ...engine.customPatterns,
      ...engine.builtInPatterns,
    ];
    final List<GolPattern> byCategory = switch (_filter) {
      _PatternFilter.all => all,
      _PatternFilter.saved => engine.customPatterns,
      _PatternFilter.stillLife => all
          .where((GolPattern p) => p.category == PatternCategory.stillLife)
          .toList(),
      _PatternFilter.oscillator => all
          .where((GolPattern p) => p.category == PatternCategory.oscillator)
          .toList(),
      _PatternFilter.spaceship => all
          .where((GolPattern p) => p.category == PatternCategory.spaceship)
          .toList(),
      _PatternFilter.methuselah => all
          .where((GolPattern p) => p.category == PatternCategory.methuselah)
          .toList(),
      _PatternFilter.gun => all
          .where((GolPattern p) => p.category == PatternCategory.gun)
          .toList(),
      _PatternFilter.puffer => all
          .where((GolPattern p) => p.category == PatternCategory.puffer)
          .toList(),
    };

    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return byCategory;

    return byCategory.where((GolPattern p) {
      final bool matchesName = p.name.toLowerCase().contains(query);
      final bool matchesAuthor =
          p.author != null && p.author!.toLowerCase().contains(query);
      final bool matchesDesc = p.description.toLowerCase().contains(query);
      return matchesName || matchesAuthor || matchesDesc;
    }).toList();
  }

  String _filterLabel(GolEngine engine, _PatternFilter filter) {
    return switch (filter) {
      _PatternFilter.all => _trOr(engine, 'cat_all', 'All'),
      _PatternFilter.saved => _trOr(engine, 'cat_custom', 'Saved'),
      _PatternFilter.stillLife => _trOr(engine, 'cat_still_life', 'Still Lifes'),
      _PatternFilter.oscillator =>
        _trOr(engine, 'cat_oscillator', 'Oscillators'),
      _PatternFilter.spaceship => _trOr(engine, 'cat_spaceship', 'Spaceships'),
      _PatternFilter.methuselah =>
        _trOr(engine, 'cat_methuselah', 'Methuselahs'),
      _PatternFilter.gun => _trOr(engine, 'cat_gun', 'Guns'),
      _PatternFilter.puffer => _trOr(engine, 'cat_puffer', 'Puffers'),
    };
  }

  Future<void> _openWikiUrl(String rawUrl) async {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleSaveViewport(BuildContext context, GolEngine engine) async {
    final Size vp = widget.viewportSize;
    if (vp.isEmpty) {
      showAppToast(context, 'Viewport is empty');
      return;
    }
    final Offset topLeft = engine.screenToWorld(Offset.zero, vp);
    final Offset bottomRight =
        engine.screenToWorld(Offset(vp.width, vp.height), vp);
    final int minX = topLeft.dx.floor();
    final int minY = topLeft.dy.floor();
    final int maxX = bottomRight.dx.ceil();
    final int maxY = bottomRight.dy.ceil();

    const int maxCells = 16384;
    final List<(int, int)> cells = engine.grid.extractRegion(
      minX,
      minY,
      maxX,
      maxY,
      maxCells: maxCells + 1,
    );
    if (cells.isEmpty) {
      showAppToast(context, 'No live cells in viewport');
      return;
    }
    final bool truncated = cells.length > maxCells;
    final List<(int, int)> capped =
        truncated ? cells.sublist(0, maxCells) : cells;
    await showSavePatternDialog(
      context,
      cells: capped,
      defaultName: 'Viewport',
      truncated: truncated,
    );
  }

  Future<void> _handleSaveField(BuildContext context, GolEngine engine) async {
    final ({int minX, int minY, int maxX, int maxY})? box =
        engine.grid.boundingBox();
    if (box == null) {
      showAppToast(context, 'Board is empty');
      return;
    }
    const int maxCells = 16384;
    final List<(int, int)> cells = engine.grid.extractRegion(
      box.minX,
      box.minY,
      box.maxX,
      box.maxY,
      maxCells: maxCells + 1,
    );
    if (cells.isEmpty) {
      showAppToast(context, 'Board is empty');
      return;
    }
    final bool spanExceeded =
        (box.maxX - box.minX + 1) > 512 || (box.maxY - box.minY + 1) > 512;
    final bool truncated = cells.length > maxCells || spanExceeded;
    final List<(int, int)> capped =
        cells.length > maxCells ? cells.sublist(0, maxCells) : cells;
    await showSavePatternDialog(
      context,
      cells: capped,
      defaultName: 'Field',
      truncated: truncated,
    );
  }

  Future<void> _handleImportRle(BuildContext context, GolEngine engine) async {
    final TextEditingController controller = TextEditingController();
    final String? rawRle = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(_trOr(engine, 'import_rle', 'Import RLE')),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(
              hintText:
                  _trOr(engine, 'rle_input_hint', 'Paste RLE pattern here...'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_trOr(engine, 'cancel', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(_trOr(engine, 'done', 'Done')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (rawRle == null || !context.mounted) return;
    final DecodedPattern decoded = RleCodec.decode(rawRle);
    if (decoded.cells.isEmpty) {
      showAppToast(context, _trOr(engine, 'invalid_rle', 'Invalid RLE pattern'));
      return;
    }
    engine.saveCustomPattern(
      name: decoded.name ?? 'Imported Pattern',
      cells: decoded.cells,
    );
    setState(() => _filter = _PatternFilter.saved);
    showAppToast(context, _trOr(engine, 'pattern_saved', 'Pattern saved'));
  }

  Future<void> _sharePattern(
    BuildContext context,
    GolEngine engine,
    GolPattern pattern,
  ) async {
    final DecodedPattern decoded = _getDecoded(pattern.rle);
    await showShareGolSheet(
      context,
      engine,
      cellsOverride: decoded.cells,
      initialName: pattern.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<GolPattern> patterns = _filteredPatterns(engine);
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.96),
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _trOr(engine, 'patterns_title', 'Patterns'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Quick-save & import strip (all buttons >= 48dp high)
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: <Widget>[
                    _QuickActionChip(
                      icon: Icons.crop_free_rounded,
                      label: _trOr(engine, 'save_viewport', 'Save Viewport'),
                      onTap: () => _handleSaveViewport(context, engine),
                    ),
                    const SizedBox(width: 8),
                    _QuickActionChip(
                      icon: Icons.select_all_rounded,
                      label: _trOr(engine, 'save_field', 'Save Field'),
                      onTap: () => _handleSaveField(context, engine),
                    ),
                    const SizedBox(width: 8),
                    _QuickActionChip(
                      icon: Icons.crop_rounded,
                      label: _trOr(engine, 'crop_board', 'Crop Board'),
                      onTap: () {
                        engine.setActiveTool(CanvasTool.crop);
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 8),
                    _QuickActionChip(
                      icon: Icons.file_upload_outlined,
                      label: _trOr(engine, 'import_rle', 'Import RLE'),
                      onTap: () => _handleImportRle(context, engine),
                    ),
                  ],
                ),
              ),
              // Search bar (>= 48dp height, 48x48 clear button)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (String value) {
                      setState(() => _searchQuery = value);
                    },
                    decoration: InputDecoration(
                      hintText: _trOr(
                        engine,
                        'search_patterns',
                        'Search patterns...',
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              tooltip: _trOr(engine, 'clear', 'Clear'),
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              // Horizontal category filter chips (each >= 48dp high)
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _PatternFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final _PatternFilter filter = _PatternFilter.values[index];
                    final bool selected = _filter == filter;
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: ChoiceChip(
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          label: Text(_filterLabel(engine, filter)),
                          selected: selected,
                          onSelected: (_) {
                            if (engine.hapticsEnabled) {
                              HapticFeedback.selectionClick();
                            }
                            setState(() => _filter = filter);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: patterns.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No patterns in this category yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: patterns.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (BuildContext context, int index) {
                          final GolPattern pattern = patterns[index];
                          final String sizeMeta = pattern.period != null
                              ? '${pattern.width}×${pattern.height} · p${pattern.period}'
                              : '${pattern.width}×${pattern.height}';
                          final String? author = pattern.author?.trim();
                          final String meta = (author != null &&
                                  author.isNotEmpty)
                              ? '$sizeMeta · $author'
                              : sizeMeta;
                          final String? wikiUrl = pattern.wikiUrl?.trim();
                          final bool hasWiki =
                              wikiUrl != null && wikiUrl.isNotEmpty;
                          return ListTile(
                            minTileHeight: 64,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            leading: _PatternThumbnail(
                              rle: pattern.rle,
                              palette: engine.palette,
                              scheme: scheme,
                            ),
                            title: Text(
                              pattern.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              pattern.description.isNotEmpty
                                  ? '$meta · ${pattern.description}'
                                  : meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  tooltip: _trOr(
                                    engine,
                                    'load_centered',
                                    'Load centered',
                                  ),
                                  icon: const Icon(
                                    Icons.center_focus_strong_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    if (engine.hapticsEnabled) {
                                      HapticFeedback.lightImpact();
                                    }
                                    engine.loadPatternCentered(
                                      pattern,
                                      widget.viewportSize,
                                    );
                                    showAppToast(
                                      context,
                                      _trOr(
                                        engine,
                                        'pattern_loaded',
                                        'Pattern loaded',
                                      ),
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                if (hasWiki)
                                  IconButton(
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    tooltip: _trOr(
                                      engine,
                                      'open_lifewiki',
                                      'LifeWiki',
                                    ),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 20,
                                    ),
                                    onPressed: () => _openWikiUrl(wikiUrl),
                                  ),
                                IconButton(
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  tooltip: _trOr(
                                    engine,
                                    'share_title',
                                    'Share Pattern',
                                  ),
                                  icon: const Icon(Icons.share_rounded, size: 20),
                                  onPressed: () =>
                                      _sharePattern(context, engine, pattern),
                                ),
                                if (!pattern.isBuiltIn)
                                  IconButton(
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                    tooltip: 'Delete',
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: scheme.error,
                                    ),
                                    onPressed: () =>
                                        engine.deleteCustomPattern(pattern.id),
                                  ),
                              ],
                            ),
                            onTap: () {
                              if (engine.hapticsEnabled) {
                                HapticFeedback.lightImpact();
                              }
                              engine.selectPatternForStamp(pattern);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternThumbnail extends StatelessWidget {
  final String rle;
  final GolPalette palette;
  final ColorScheme scheme;

  const _PatternThumbnail({
    required this.rle,
    required this.palette,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final DecodedPattern decoded = _getDecoded(rle);
    final ({Color alive, Color aged, Color background, Color gridLine}) colors =
        palette.resolveColors(scheme);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _MiniGridPainter(
          cells: decoded.cells,
          width: decoded.width,
          height: decoded.height,
          aliveColor: colors.alive,
        ),
      ),
    );
  }
}

class _MiniGridPainter extends CustomPainter {
  final List<(int, int)> cells;
  final int width;
  final int height;
  final Color aliveColor;

  const _MiniGridPainter({
    required this.cells,
    required this.width,
    required this.height,
    required this.aliveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.isEmpty || width <= 0 || height <= 0) return;

    const double pad = 5.0;
    final double availW = math.max(1.0, size.width - pad * 2);
    final double availH = math.max(1.0, size.height - pad * 2);
    final double cellSize = math.min(availW / width, availH / height);
    final double offsetX = (size.width - width * cellSize) * 0.5;
    final double offsetY = (size.height - height * cellSize) * 0.5;
    final double inset = cellSize >= 4.0 ? 0.45 : 0.0;
    final double drawSize = math.max(1.0, cellSize - inset * 2);

    final Paint paint = Paint()
      ..color = aliveColor
      ..style = PaintingStyle.fill;

    for (final (int x, int y) in cells) {
      canvas.drawRect(
        Rect.fromLTWH(
          offsetX + x * cellSize + inset,
          offsetY + y * cellSize + inset,
          drawSize,
          drawSize,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniGridPainter oldDelegate) =>
      oldDelegate.cells != cells ||
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.aliveColor != aliveColor;
}
