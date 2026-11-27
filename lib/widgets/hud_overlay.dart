import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/gol_engine.dart';
import '../engine/gol_models.dart';
import 'app_toast.dart';

String _trOr(GolEngine engine, String key, String fallback) {
  final String value = engine.tr(key);
  if (value.isEmpty || value == key || value.startsWith('!')) {
    return fallback;
  }
  return value;
}

/// Top stadium status bar showing generation, population, topology/rule/TPS,
/// segmented Draw/Pan tool toggle, and hold-to-clear button.
///
/// Every interactive control enforces a >= 48dp touch target.
class HudStatusRow extends StatelessWidget {
  final VoidCallback onOpenPatterns;
  final VoidCallback onFitToContent;

  const HudStatusRow({
    super.key,
    required this.onOpenPatterns,
    required this.onFitToContent,
  });

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final String genLabel = _trOr(engine, 'gen_label', 'Gen');
    final String cellsLabel = _trOr(engine, 'cells_label', 'cells');
    final String tpsLabel = _trOr(engine, 'tps_label', 'TPS');
    final String line1 =
        '$genLabel ${engine.generation} · ${engine.population} $cellsLabel';
    final String line2 =
        '${engine.topology.shortLabel} · ${engine.rule.notation} · ${engine.targetTps.round()} $tpsLabel';

    final bool isDraw = engine.activeTool == CanvasTool.draw;
    final bool isPan = engine.activeTool == CanvasTool.pan;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: StadiumBorder(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Tooltip(
                  message: _trOr(engine, 'fit_to_content', 'Fit to Content'),
                  child: Material(
                    color: scheme.secondaryContainer.withValues(alpha: 0.72),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (engine.hapticsEnabled) {
                          HapticFeedback.lightImpact();
                        }
                        onFitToContent();
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                line1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSecondaryContainer,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                line2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSecondaryContainer
                                      .withValues(alpha: 0.8),
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SegmentedDrawPanToggle(
                    isDrawSelected: isDraw,
                    isPanSelected: isPan,
                    drawTooltip: _trOr(engine, 'draw_tool', 'Draw'),
                    panTooltip: _trOr(engine, 'pan_tool', 'Pan'),
                    hapticsEnabled: engine.hapticsEnabled,
                    onSelectDraw: () => engine.setActiveTool(CanvasTool.draw),
                    onSelectPan: () => engine.setActiveTool(CanvasTool.pan),
                  ),
                  const SizedBox(width: 4),
                  _BarIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: _trOr(engine, 'hold_to_clear', 'Hold to clear'),
                    hapticsEnabled: engine.hapticsEnabled,
                    onTap: () => showAppToast(
                      context,
                      _trOr(engine, 'hold_to_clear', 'Hold to clear'),
                    ),
                    onLongPress: () {
                      engine.clear();
                      showAppToast(
                        context,
                        _trOr(engine, 'cleared_board', 'Board cleared'),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom stadium action bar that adapts to normal (`draw`/`pan`), `stamp`,
/// and `crop` tool modes. Every interactive button is >= 48dp high.
class HudBottomBar extends StatelessWidget {
  final VoidCallback onOpenPatterns;
  final VoidCallback onOpenPalette;
  final VoidCallback onOpenInspector;
  final VoidCallback onSaveCrop;
  final VoidCallback onCopyCropRle;

  const HudBottomBar({
    super.key,
    required this.onOpenPatterns,
    required this.onOpenPalette,
    required this.onOpenInspector,
    required this.onSaveCrop,
    required this.onCopyCropRle,
  });

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: StadiumBorder(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: switch (engine.activeTool) {
            CanvasTool.stamp => _buildStampBar(context, engine, scheme),
            CanvasTool.crop => _buildCropBar(context, engine, scheme),
            CanvasTool.draw || CanvasTool.pan =>
              _buildNormalBar(context, engine, scheme),
          },
        ),
      ),
    );
  }

  Widget _buildNormalBar(
    BuildContext context,
    GolEngine engine,
    ColorScheme scheme,
  ) {
    final bool playing = engine.isPlaying;
    return Row(
      children: <Widget>[
        _BarTonalIconButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: playing
              ? _trOr(engine, 'pause', 'Pause')
              : _trOr(engine, 'play', 'Play'),
          minWidth: 52,
          minHeight: 48,
          backgroundColor:
              playing ? scheme.primaryContainer : scheme.secondaryContainer,
          iconColor:
              playing ? scheme.onPrimaryContainer : scheme.onSecondaryContainer,
          hapticsEnabled: engine.hapticsEnabled,
          onTap: engine.togglePlay,
        ),
        const SizedBox(width: 4),
        _BarIconButton(
          icon: Icons.skip_next_rounded,
          tooltip: _trOr(engine, 'step', 'Step'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: engine.stepOnce,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _BarPillButton(
            icon: Icons.grid_view_rounded,
            label: _trOr(engine, 'patterns_title', 'Patterns'),
            tooltip: _trOr(engine, 'patterns_title', 'Patterns'),
            hapticsEnabled: engine.hapticsEnabled,
            onTap: onOpenPatterns,
          ),
        ),
        const SizedBox(width: 4),
        _BarIconButton(
          icon: Icons.palette_rounded,
          tooltip: _trOr(engine, 'palette_label', 'Palette'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: onOpenPalette,
        ),
        _BarIconButton(
          icon: Icons.tune_rounded,
          tooltip: _trOr(engine, 'inspector_title', 'Inspector'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: onOpenInspector,
        ),
      ],
    );
  }

  Widget _buildStampBar(
    BuildContext context,
    GolEngine engine,
    ColorScheme scheme,
  ) {
    return Row(
      children: <Widget>[
        _BarIconButton(
          icon: Icons.rotate_right_rounded,
          tooltip: _trOr(engine, 'stamp_rotate', 'Rotate'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: engine.rotateStamp,
        ),
        _BarIconButton(
          icon: Icons.flip_rounded,
          tooltip: _trOr(engine, 'stamp_flip', 'Flip'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: engine.flipStamp,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _BarPillButton(
            icon: Icons.add_box_rounded,
            label: _trOr(engine, 'stamp_place', 'Place'),
            tooltip: _trOr(engine, 'stamp_place', 'Place'),
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            hapticsEnabled: engine.hapticsEnabled,
            onTap: () => engine.stampAt(
              engine.cameraX.floor(),
              engine.cameraY.floor(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _BarIconButton(
          icon: Icons.check_rounded,
          tooltip: _trOr(engine, 'done', 'Done'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: () => engine.setActiveTool(CanvasTool.draw),
        ),
      ],
    );
  }

  Widget _buildCropBar(
    BuildContext context,
    GolEngine engine,
    ColorScheme scheme,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _BarPillButton(
            icon: Icons.save_rounded,
            label: _trOr(engine, 'save_crop', 'Save Crop'),
            tooltip: _trOr(engine, 'save_crop', 'Save Crop'),
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            hapticsEnabled: engine.hapticsEnabled,
            onTap: onSaveCrop,
          ),
        ),
        const SizedBox(width: 4),
        _BarIconButton(
          icon: Icons.copy_rounded,
          tooltip: _trOr(engine, 'copy_rle', 'Copy RLE'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: onCopyCropRle,
        ),
        _BarIconButton(
          icon: Icons.close_rounded,
          tooltip: _trOr(engine, 'cancel', 'Cancel'),
          hapticsEnabled: engine.hapticsEnabled,
          onTap: () => engine.setActiveTool(CanvasTool.draw),
        ),
      ],
    );
  }
}

/// Presents a rounded 28px modal bottom sheet selector for all [GolPalette]s.
Future<void> showPaletteSelectorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      final GolEngine engine = sheetContext.watch<GolEngine>();

      return Material(
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
                        _trOr(engine, 'palette_label', 'Palette'),
                        style: Theme.of(sheetContext)
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
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: GolPalette.values.map((GolPalette palette) {
                      final bool selected = engine.palette == palette;
                      final List<Color> swatch = palette.previewColors(scheme);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        child: ListTile(
                          minTileHeight: 52,
                          selected: selected,
                          selectedTileColor:
                              scheme.primaryContainer.withValues(alpha: 0.45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: swatch.map((Color color) {
                              return Container(
                                width: 14,
                                height: 14,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                  border: Border.all(
                                    color: scheme.outline.withValues(alpha: 0.45),
                                    width: 0.8,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          title: Text(
                            _trOr(engine, palette.translationKey, palette.name),
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          trailing: selected
                              ? Icon(Icons.check_rounded, color: scheme.primary)
                              : null,
                          onTap: () {
                            if (engine.hapticsEnabled) {
                              HapticFeedback.lightImpact();
                            }
                            engine.setPalette(palette);
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SegmentedDrawPanToggle extends StatelessWidget {
  final bool isDrawSelected;
  final bool isPanSelected;
  final String drawTooltip;
  final String panTooltip;
  final bool hapticsEnabled;
  final VoidCallback onSelectDraw;
  final VoidCallback onSelectPan;

  const _SegmentedDrawPanToggle({
    required this.isDrawSelected,
    required this.isPanSelected,
    required this.drawTooltip,
    required this.panTooltip,
    required this.hapticsEnabled,
    required this.onSelectDraw,
    required this.onSelectPan,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SegmentButton(
            icon: Icons.brush_rounded,
            tooltip: drawTooltip,
            selected: isDrawSelected,
            hapticsEnabled: hapticsEnabled,
            onTap: onSelectDraw,
          ),
          _SegmentButton(
            icon: Icons.open_with_rounded,
            tooltip: panTooltip,
            selected: isPanSelected,
            hapticsEnabled: hapticsEnabled,
            onTap: onSelectPan,
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool hapticsEnabled;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.hapticsEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (hapticsEnabled) {
              HapticFeedback.selectionClick();
            }
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: Icon(
                icon,
                size: 22,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarTonalIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double minWidth;
  final double minHeight;
  final Color backgroundColor;
  final Color iconColor;
  final bool hapticsEnabled;
  final VoidCallback onTap;

  const _BarTonalIconButton({
    required this.icon,
    required this.tooltip,
    required this.minWidth,
    required this.minHeight,
    required this.backgroundColor,
    required this.iconColor,
    required this.hapticsEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (hapticsEnabled) {
              HapticFeedback.lightImpact();
            }
            onTap();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: minHeight,
            ),
            child: Center(
              child: Icon(icon, size: 24, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool hapticsEnabled;
  final VoidCallback? onTap;

  const _BarPillButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    required this.hapticsEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = foregroundColor ?? scheme.onSecondaryContainer;
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            backgroundColor ?? scheme.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  if (hapticsEnabled) {
                    HapticFeedback.lightImpact();
                  }
                  onTap!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
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

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool hapticsEnabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.hapticsEnabled,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  if (hapticsEnabled) {
                    HapticFeedback.lightImpact();
                  }
                  onTap!();
                },
          onLongPress: onLongPress == null
              ? null
              : () {
                  if (hapticsEnabled) {
                    HapticFeedback.mediumImpact();
                  }
                  onLongPress!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: Icon(icon, size: 24, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
