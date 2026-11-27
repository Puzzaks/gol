import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x/m3x.dart' show M3x;
import 'package:m3x_gh/m3x_gh.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/gol_engine.dart';
import '../engine/gol_models.dart';
import 'app_toast.dart';

String _trOr(GolEngine engine, String key, String fallback) {
  final String raw = engine.tr(key);
  if (raw.isEmpty || raw == key || raw.startsWith('!')) {
    return fallback;
  }
  return raw;
}

void _triggerHaptic(GolEngine engine) {
  if (engine.hapticsEnabled) {
    HapticFeedback.lightImpact();
  }
}

/// Inherited drag-callback scope connecting compact split-sheet headers to the
/// parent 1:1 vertical drag controller in [GolExplorerPage].
class InspectorSheetDragScope extends InheritedWidget {
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  final GestureDragCancelCallback? onDragCancel;

  const InspectorSheetDragScope({
    super.key,
    required super.child,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
  });

  bool get hasCallbacks =>
      onDragStart != null ||
      onDragUpdate != null ||
      onDragEnd != null ||
      onDragCancel != null;

  Widget wrap(Widget child) {
    return InspectorSheetDragScope(
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCancel: onDragCancel,
      child: child,
    );
  }

  static InspectorSheetDragScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InspectorSheetDragScope>();
  }

  @override
  bool updateShouldNotify(InspectorSheetDragScope oldWidget) {
    return onDragStart != oldWidget.onDragStart ||
        onDragUpdate != oldWidget.onDragUpdate ||
        onDragEnd != oldWidget.onDragEnd ||
        onDragCancel != oldWidget.onDragCancel;
  }
}

/// Material 3 eXtended settings & simulation inspector with a nested
/// [Navigator], frosted sticky header, and velocity-gated scroll blur.
class InspectorPanel extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<Size> viewportNotifier;
  final VoidCallback onClose;
  final bool isSheet;
  final VoidCallback? onLocaleChanged;

  const InspectorPanel({
    super.key,
    required this.navigatorKey,
    required this.viewportNotifier,
    required this.onClose,
    this.isSheet = false,
    this.onLocaleChanged,
  });

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  @override
  Widget build(BuildContext context) {
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);
    final bool effectiveIsSheet =
        widget.isSheet || (dragScope?.hasCallbacks ?? false);

    return Navigator(
      key: widget.navigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (BuildContext navContext) {
            final Widget hub = _InspectorHubPage(
              viewportNotifier: widget.viewportNotifier,
              isSheet: effectiveIsSheet,
              onClose: widget.onClose,
              onLocaleChanged: widget.onLocaleChanged,
            );
            return dragScope != null ? dragScope.wrap(hub) : hub;
          },
        );
      },
    );
  }
}

class _InspectorHubPage extends StatelessWidget {
  final ValueListenable<Size> viewportNotifier;
  final bool isSheet;
  final VoidCallback onClose;
  final VoidCallback? onLocaleChanged;

  const _InspectorHubPage({
    required this.viewportNotifier,
    required this.isSheet,
    required this.onClose,
    this.onLocaleChanged,
  });

  void _pushSubPage(BuildContext context, Widget page) {
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            dragScope != null ? dragScope.wrap(page) : page,
      ),
    );
  }

  Future<void> _showLanguagePicker(
    BuildContext context,
    GolEngine engine,
  ) async {
    final List<dynamic> rawLanguages = engine.dict.languages.isNotEmpty
        ? engine.dict.languages
        : const <Map<String, String>>[
            <String, String>{
              'id': 'en',
              'origin': 'English',
              'name': 'English',
            },
            <String, String>{
              'id': 'uk',
              'origin': 'Українська',
              'name': 'Ukrainian',
            },
          ];

    final List<OptionPickerItem<String>> items = <OptionPickerItem<String>>[
      OptionPickerItem<String>(
        value: '__system__',
        title: _trOr(engine, 'language_system', 'System default'),
      ),
      for (final dynamic entry in rawLanguages)
        if (entry is Map && entry['id'] != null)
          OptionPickerItem<String>(
            value: entry['id'].toString(),
            title: (entry['origin'] ?? entry['name'] ?? entry['id']).toString(),
            subtitle: (entry['name'] != null &&
                    entry['name'].toString() !=
                        (entry['origin'] ?? '').toString())
                ? entry['name'].toString()
                : '',
          ),
    ];

    final String current =
        engine.dict.isSystemLanguage ? '__system__' : engine.dict.locale;

    await OptionPickerDialog.show<String>(
      context: context,
      title: _trOr(engine, 'language_label', 'Language'),
      options: items,
      currentValue: current,
      onSelected: (String value) async {
        _triggerHaptic(engine);
        if (value == '__system__') {
          await engine.dict.setSystemLanguage();
        } else {
          await engine.dict.setLanguage(value);
        }
        onLocaleChanged?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);

    final String languageSubtitle = engine.dict.isSystemLanguage
        ? _trOr(engine, 'language_system', 'System default')
        : engine.dict.currentLanguageName;

    final String simSummary =
        '${engine.targetTps.round()} ${_trOr(engine, 'tps_label', 'TPS')} · '
        '${_trOr(engine, engine.topology.translationKey, engine.topology.shortLabel)} · '
        '${engine.rule.notation}';

    final Widget headerContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isSheet) const _SheetHandle(),
        _PanelHeader(
          title: _trOr(engine, 'inspector_title', 'Inspector'),
          onClose: onClose,
        ),
      ],
    );

    return _InspectorHeaderScrollScaffold(
      isSheet: isSheet,
      enableScrollBlur: engine.enableScrollBlur,
      headerContent: headerContent,
      hasHeaderDrag: dragScope?.hasCallbacks ?? false,
      onHeaderDragStart: dragScope?.onDragStart,
      onHeaderDragUpdate: dragScope?.onDragUpdate,
      onHeaderDragEnd: dragScope?.onDragEnd,
      onHeaderDragCancel: dragScope?.onDragCancel,
      listTopPadding: 14,
      listBottomPadding: 24,
      children: <Widget>[
        SettingsBentoHeader(
          appName: M3x.appName.isNotEmpty
              ? M3x.appName
              : _trOr(engine, 'app_title', 'Game of Life'),
          subtitle: M3x.appDescription.isNotEmpty
              ? M3x.appDescription
              : "Conway's Game of Life",
          icon: Icons.grid_on_rounded,
          versionDisplay:
              M3x.versionDisplay.isNotEmpty ? M3x.versionDisplay : '1.2.0',
          onHeaderTap: () => launchUrl(
            Uri.parse('https://puzzak.page'),
            mode: LaunchMode.externalApplication,
          ),
          onVersionTap: () => SettingsBentoHeader.showChangelogDialog(context),
          onModulesTap: () =>
              SettingsBentoHeader.showDependenciesDialog(context),
        ),
        Category.settings(
          title: _trOr(engine, 'settings_title', 'Settings'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.tapIcon(
              title: _trOr(engine, 'sim_section', 'Simulation'),
              subtitle: simSummary,
              icon: Icons.tune_rounded,
              color: scheme.onPrimaryFixed,
              colorBG: scheme.primaryFixedDim,
              trailing: const Icon(Icons.chevron_right_rounded),
              action: () => _pushSubPage(
                context,
                _SimulationSubPage(
                  viewportNotifier: viewportNotifier,
                  isSheet: isSheet,
                  onClose: onClose,
                ),
              ),
            ),
            CardContents.tapIcon(
              title: _trOr(engine, 'appearance_section', 'Appearance'),
              subtitle: _trOr(
                engine,
                engine.palette.translationKey,
                engine.palette.name,
              ),
              icon: Icons.palette_rounded,
              color: scheme.onPrimaryFixed,
              colorBG: scheme.primaryFixedDim,
              trailing: const Icon(Icons.chevron_right_rounded),
              action: () => _pushSubPage(
                context,
                _AppearanceSubPage(
                  isSheet: isSheet,
                  onClose: onClose,
                ),
              ),
            ),
            CardContents.tapIcon(
              title: _trOr(engine, 'controls_section', 'Controls & Shortcuts'),
              subtitle: _trOr(
                engine,
                'keyboard_shortcuts',
                'Keyboard Shortcuts',
              ),
              icon: Icons.keyboard_rounded,
              color: scheme.onPrimaryFixed,
              colorBG: scheme.primaryFixedDim,
              trailing: const Icon(Icons.chevron_right_rounded),
              action: () => _pushSubPage(
                context,
                _ControlsSubPage(
                  viewportNotifier: viewportNotifier,
                  isSheet: isSheet,
                  onClose: onClose,
                ),
              ),
            ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'app_links_section', 'App & Links'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.tap(
              title: _trOr(engine, 'language_label', 'Language'),
              subtitle: languageSubtitle,
              trailing: const Icon(Icons.translate_rounded, size: 20),
              action: () => _showLanguagePicker(context, engine),
            ),
            CardContents.turn(
              title: _trOr(engine, 'scroll_blur', 'Blur on Scroll'),
              subtitle: _trOr(
                engine,
                'scroll_blur_sub',
                'Frosted header and motion blur while scrolling',
              ),
              value: engine.enableScrollBlur,
              action: () {
                _triggerHaptic(engine);
                engine.setEnableScrollBlur(!engine.enableScrollBlur);
              },
              switcher: (bool v) {
                _triggerHaptic(engine);
                engine.setEnableScrollBlur(v);
              },
            ),
            CardContents.tap(
              title: _trOr(engine, 'github_repo', 'GitHub Repository'),
              subtitle: 'Puzzaks/gol',
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              action: () => M3xGitHub.openExplorer(
                context,
                owner: 'Puzzaks',
                repo: 'gol',
              ),
            ),
            CardContents.tapIcon(
              title: _trOr(
                engine,
                'lifewiki_link_title',
                'LifeWiki (conwaylife.com)',
              ),
              subtitle: _trOr(
                engine,
                'lifewiki_link_sub',
                'Pattern catalog & discoverer credits · Visit conwaylife.com',
              ),
              icon: Icons.public_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              action: () => launchUrl(
                Uri.parse('https://conwaylife.com/wiki/Main_Page'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            GestureDetector(
              onLongPress: () async {
                if (engine.hapticsEnabled) {
                  HapticFeedback.heavyImpact();
                }
                await engine.resetAllSettings();
                if (context.mounted) {
                  showAppToast(
                    context,
                    _trOr(
                      engine,
                      'settings_reset_done',
                      'All settings reset to defaults',
                    ),
                  );
                }
              },
              child: CardContents.tap(
                title: _trOr(engine, 'reset_all_settings', 'Reset All Settings'),
                subtitle: _trOr(engine, 'hold_to_reset', 'Hold to reset'),
                trailing: Icon(
                  Icons.restore_rounded,
                  size: 20,
                  color: scheme.error,
                ),
                action: () {
                  showAppToast(
                    context,
                    _trOr(engine, 'hold_to_reset', 'Hold to reset'),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-page: Simulation
// ---------------------------------------------------------------------------

class _SimulationSubPage extends StatelessWidget {
  static const List<int> _finiteSizes = <int>[64, 128, 256, 512];

  final ValueListenable<Size> viewportNotifier;
  final bool isSheet;
  final VoidCallback onClose;

  const _SimulationSubPage({
    required this.viewportNotifier,
    required this.isSheet,
    required this.onClose,
  });

  static double _tpsToLogSlider(double tps) {
    final double clamped = tps.clamp(GolEngine.minTps, GolEngine.maxTps);
    return math.log(clamped / GolEngine.minTps) /
        math.log(GolEngine.maxTps / GolEngine.minTps);
  }

  static double _logSliderToTps(double t) {
    final double clamped = t.clamp(0.0, 1.0);
    return GolEngine.minTps *
        math.pow(GolEngine.maxTps / GolEngine.minTps, clamped);
  }

  static String _maskToDigits(int mask) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i <= 8; i++) {
      if ((mask & (1 << i)) != 0) sb.write(i);
    }
    return sb.toString();
  }

  void _toggleRuleBit(
    GolEngine engine, {
    required bool isBirth,
    required int digit,
  }) {
    _triggerHaptic(engine);
    final int bit = 1 << digit;
    final int nextBirth =
        isBirth ? (engine.rule.birthMask ^ bit) : engine.rule.birthMask;
    final int nextSurvival =
        isBirth ? engine.rule.survivalMask : (engine.rule.survivalMask ^ bit);
    final String notation =
        'B${_maskToDigits(nextBirth)}/S${_maskToDigits(nextSurvival)}';
    final GolRule? parsed = GolRule.tryParse(notation);
    if (parsed != null) {
      engine.setRule(parsed);
    }
  }

  Future<void> _showTopologyPicker(
    BuildContext context,
    GolEngine engine,
  ) async {
    await OptionPickerDialog.show<GridTopology>(
      context: context,
      title: _trOr(engine, 'topology_label', 'Topology'),
      options: GridTopology.values
          .map(
            (GridTopology t) => OptionPickerItem<GridTopology>(
              value: t,
              title: _trOr(engine, t.translationKey, t.shortLabel),
            ),
          )
          .toList(),
      currentValue: engine.topology,
      onSelected: (GridTopology next) {
        _triggerHaptic(engine);
        engine.setTopology(next);
      },
    );
  }

  Future<void> _showFiniteSizePicker(
    BuildContext context,
    GolEngine engine,
  ) async {
    await OptionPickerDialog.show<int>(
      context: context,
      title: _trOr(engine, 'grid_size_label', 'Grid Size'),
      options: _finiteSizes
          .map(
            (int size) => OptionPickerItem<int>(
              value: size,
              title: '$size × $size',
            ),
          )
          .toList(),
      currentValue: engine.finiteWidth,
      onSelected: (int next) {
        _triggerHaptic(engine);
        engine.setFiniteSize(next, next);
      },
    );
  }

  Future<void> _showRulePresetPicker(
    BuildContext context,
    GolEngine engine,
  ) async {
    await OptionPickerDialog.show<GolRule>(
      context: context,
      title: _trOr(engine, 'ruleset_label', 'Ruleset'),
      options: GolRule.presets
          .map(
            (GolRule r) => OptionPickerItem<GolRule>(
              value: r,
              title: r.name,
              subtitle: r.notation,
            ),
          )
          .toList(),
      currentValue: engine.rule,
      onSelected: (GolRule next) {
        _triggerHaptic(engine);
        engine.setRule(next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double logTps = _tpsToLogSlider(engine.targetTps);

    return _SubPageScaffold(
      title: _trOr(engine, 'sim_section', 'Simulation'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: _trOr(engine, 'speed_tps', 'Speed (TPS)'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.slider(
              title: _trOr(engine, 'speed_tps', 'Speed (TPS)'),
              value: logTps,
              min: 0.0,
              max: 1.0,
              trailing: Text(
                '${engine.targetTps.round()} ${_trOr(engine, 'tps_label', 'TPS')}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: (double v) {
                engine.setTargetTps(_logSliderToTps(v));
              },
            ),
            CardContents.tap(
              title: _trOr(engine, 'topology_label', 'Topology'),
              subtitle: _trOr(
                engine,
                engine.topology.translationKey,
                engine.topology.shortLabel,
              ),
              trailing: const Icon(Icons.grid_4x4_rounded, size: 20),
              action: () => _showTopologyPicker(context, engine),
            ),
            if (engine.topology != GridTopology.infinite)
              CardContents.tap(
                title: _trOr(engine, 'grid_size_label', 'Grid Size'),
                subtitle: '${engine.finiteWidth} × ${engine.finiteHeight}',
                trailing: const Icon(Icons.aspect_ratio_rounded, size: 20),
                action: () => _showFiniteSizePicker(context, engine),
              ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'ruleset_label', 'Ruleset'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.tap(
              title: engine.rule.name,
              subtitle: engine.rule.notation,
              trailing: const Icon(Icons.auto_fix_high_rounded, size: 20),
              action: () => _showRulePresetPicker(context, engine),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Birth (B)',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _RuleDigitChipsRow(
                    prefix: 'B',
                    mask: engine.rule.birthMask,
                    onToggle: (int digit) => _toggleRuleBit(
                      engine,
                      isBirth: true,
                      digit: digit,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Survival (S)',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _RuleDigitChipsRow(
                    prefix: 'S',
                    mask: engine.rule.survivalMask,
                    onToggle: (int digit) => _toggleRuleBit(
                      engine,
                      isBirth: false,
                      digit: digit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'board_actions', 'Board Actions'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.tapIcon(
              title: _trOr(engine, 'randomize_viewport', 'Randomize Viewport'),
              subtitle: '25% density',
              icon: Icons.casino_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              action: () {
                _triggerHaptic(engine);
                engine.randomizeViewport(viewportNotifier.value);
              },
            ),
            Opacity(
              opacity: engine.canUndo ? 1.0 : 0.45,
              child: CardContents.tapIcon(
                title: _trOr(engine, 'undo', 'Undo'),
                subtitle: engine.canUndo ? '' : '—',
                icon: Icons.undo_rounded,
                color: scheme.onSecondaryContainer,
                colorBG: scheme.secondaryContainer,
                action: () {
                  if (!engine.canUndo) return;
                  _triggerHaptic(engine);
                  engine.undo();
                },
              ),
            ),
            Opacity(
              opacity: engine.canRedo ? 1.0 : 0.45,
              child: CardContents.tapIcon(
                title: _trOr(engine, 'redo', 'Redo'),
                subtitle: engine.canRedo ? '' : '—',
                icon: Icons.redo_rounded,
                color: scheme.onSecondaryContainer,
                colorBG: scheme.secondaryContainer,
                action: () {
                  if (!engine.canRedo) return;
                  _triggerHaptic(engine);
                  engine.redo();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RuleDigitChipsRow extends StatelessWidget {
  final String prefix;
  final int mask;
  final ValueChanged<int> onToggle;

  const _RuleDigitChipsRow({
    required this.prefix,
    required this.mask,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List<Widget>.generate(9, (int digit) {
        final bool active = (mask & (1 << digit)) != 0;
        return Semantics(
          button: true,
          toggled: active,
          label: '$prefix$digit',
          child: Material(
            color: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: active
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.6),
                width: active ? 1.5 : 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onToggle(digit),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                child: Center(
                  child: Text(
                    '$digit',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: active
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-page: Appearance
// ---------------------------------------------------------------------------

class _AppearanceSubPage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback onClose;

  const _AppearanceSubPage({
    required this.isSheet,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return _SubPageScaffold(
      title: _trOr(engine, 'appearance_section', 'Appearance'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: _trOr(engine, 'palette_label', 'Palette'),
          context: context,
        ),
        CardGroup(
          children: GolPalette.values.map((GolPalette palette) {
            final bool selected = engine.palette == palette;
            final List<Color> swatches = palette.previewColors(scheme);
            return CardContents.tap(
              title: _trOr(engine, palette.translationKey, palette.name),
              subtitle: selected ? 'Active' : '',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final Color color in swatches)
                    Container(
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
                    ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 20, color: scheme.primary),
                  ],
                ],
              ),
              action: () {
                _triggerHaptic(engine);
                engine.setPalette(palette);
              },
            );
          }).toList(),
        ),
        Category.settings(
          title: _trOr(engine, 'cells_display', 'Cells & Grid'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.turn(
              title: _trOr(engine, 'grid_lines', 'Grid Lines'),
              subtitle: '',
              value: engine.showGridLines,
              action: () {
                _triggerHaptic(engine);
                engine.setShowGridLines(!engine.showGridLines);
              },
              switcher: (bool v) {
                _triggerHaptic(engine);
                engine.setShowGridLines(v);
              },
            ),
            CardContents.turn(
              title: _trOr(engine, 'cell_age_trails', 'Cell Age Trails'),
              subtitle: '',
              value: engine.showCellAge,
              action: () {
                _triggerHaptic(engine);
                engine.setShowCellAge(!engine.showCellAge);
              },
              switcher: (bool v) {
                _triggerHaptic(engine);
                engine.setShowCellAge(v);
              },
            ),
            CardContents.slider(
              title: _trOr(engine, 'cell_radius', 'Cell Corner Radius'),
              value: engine.cellCornerRadius.clamp(0.0, 0.5),
              min: 0.0,
              max: 0.5,
              trailing: Text(
                '${(engine.cellCornerRadius * 200).round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: (double v) {
                engine.setCellCornerRadius(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-page: Controls & Shortcuts
// ---------------------------------------------------------------------------

class _ControlsSubPage extends StatelessWidget {
  final ValueListenable<Size> viewportNotifier;
  final bool isSheet;
  final VoidCallback onClose;

  const _ControlsSubPage({
    required this.viewportNotifier,
    required this.isSheet,
    required this.onClose,
  });

  static const List<(String, String)> _shortcuts = <(String, String)>[
    ('Space', 'Play / Pause'),
    ('N / .', 'Step one generation'),
    ('R', 'Randomize viewport'),
    ('F', 'Fit to content'),
    ('1 / 2 / 3 / 4', 'Draw / Pan / Stamp / Crop'),
    ('Ctrl + Z / Y', 'Undo / Redo'),
    ('Arrows / WASD', 'Pan camera'),
    ('+ / -', 'Zoom in / out'),
    ('H', 'Toggle fullscreen'),
  ];

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return _SubPageScaffold(
      title: _trOr(engine, 'controls_section', 'Controls & Shortcuts'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        CardGroup(
          children: <Widget>[
            CardContents.turn(
              title: _trOr(engine, 'haptics_enabled', 'Haptic Feedback'),
              subtitle: '',
              value: engine.hapticsEnabled,
              action: () {
                engine.setHapticsEnabled(!engine.hapticsEnabled);
                _triggerHaptic(engine);
              },
              switcher: (bool v) {
                engine.setHapticsEnabled(v);
                _triggerHaptic(engine);
              },
            ),
            CardContents.tapIcon(
              title: _trOr(engine, 'fit_to_content', 'Fit to Content'),
              subtitle: '',
              icon: Icons.fit_screen_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              action: () {
                _triggerHaptic(engine);
                engine.fitToContent(viewportNotifier.value);
              },
            ),
            CardContents.tapIcon(
              title: _trOr(engine, 'reset_camera', 'Reset Camera'),
              subtitle: '',
              icon: Icons.center_focus_strong_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              action: () {
                _triggerHaptic(engine);
                engine.resetCamera();
              },
            ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'keyboard_shortcuts', 'Keyboard Shortcuts'),
          context: context,
        ),
        CardGroup(
          children: _shortcuts.map(((String, String) entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      entry.$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      entry.$1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: scheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Frosted Header + Velocity-Gated Scroll Motion Blur Scaffold
// ---------------------------------------------------------------------------

class _SubPageScaffold extends StatelessWidget {
  final String title;
  final bool isSheet;
  final VoidCallback onClose;
  final List<Widget> children;

  const _SubPageScaffold({
    required this.title,
    required this.isSheet,
    required this.onClose,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final bool enableScrollBlur =
        context.select<GolEngine, bool>((GolEngine e) => e.enableScrollBlur);
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);
    final Widget headerContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isSheet) const _SheetHandle(),
        _PanelHeader(
          title: title,
          onBack: () => Navigator.of(context).pop(),
          onClose: onClose,
        ),
      ],
    );

    return _InspectorHeaderScrollScaffold(
      isSheet: isSheet,
      enableScrollBlur: enableScrollBlur,
      headerContent: headerContent,
      hasHeaderDrag: dragScope?.hasCallbacks ?? false,
      onHeaderDragStart: dragScope?.onDragStart,
      onHeaderDragUpdate: dragScope?.onDragUpdate,
      onHeaderDragEnd: dragScope?.onDragEnd,
      onHeaderDragCancel: dragScope?.onDragCancel,
      listTopPadding: 10,
      listBottomPadding: 28,
      children: children,
    );
  }
}

class _InspectorHeaderScrollScaffold extends StatefulWidget {
  final bool isSheet;
  final bool enableScrollBlur;
  final Widget headerContent;
  final bool hasHeaderDrag;
  final GestureDragStartCallback? onHeaderDragStart;
  final GestureDragUpdateCallback? onHeaderDragUpdate;
  final GestureDragEndCallback? onHeaderDragEnd;
  final GestureDragCancelCallback? onHeaderDragCancel;
  final double listTopPadding;
  final double listBottomPadding;
  final List<Widget> children;

  const _InspectorHeaderScrollScaffold({
    required this.isSheet,
    required this.enableScrollBlur,
    required this.headerContent,
    required this.hasHeaderDrag,
    this.onHeaderDragStart,
    this.onHeaderDragUpdate,
    this.onHeaderDragEnd,
    this.onHeaderDragCancel,
    required this.listTopPadding,
    required this.listBottomPadding,
    required this.children,
  });

  @override
  State<_InspectorHeaderScrollScaffold> createState() =>
      _InspectorHeaderScrollScaffoldState();
}

class _InspectorHeaderScrollScaffoldState
    extends State<_InspectorHeaderScrollScaffold>
    with SingleTickerProviderStateMixin {
  static const double _maxMotionBlurSigma = 2.6;
  static const double _minActiveBlurSigma = 0.05;

  late final AnimationController _decayController;
  Timer? _idleTimer;
  int _lastUpdateMicros = 0;
  double _decayStartSigma = 0.0;
  double _motionBlurSigma = 0.0;

  @override
  void initState() {
    super.initState();
    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onDecayTick);
  }

  @override
  void didUpdateWidget(covariant _InspectorHeaderScrollScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enableScrollBlur && _motionBlurSigma != 0.0) {
      _idleTimer?.cancel();
      _decayController.stop();
      _motionBlurSigma = 0.0;
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _decayController.dispose();
    super.dispose();
  }

  void _onDecayTick() {
    final double t = Curves.easeOutCubic.transform(_decayController.value);
    final double next = _decayStartSigma * (1.0 - t);
    final double clamped = next < _minActiveBlurSigma ? 0.0 : next;
    if (clamped != _motionBlurSigma && mounted) {
      setState(() => _motionBlurSigma = clamped);
    }
  }

  void _startDecay() {
    _idleTimer?.cancel();
    if (!mounted) return;
    if (_motionBlurSigma <= _minActiveBlurSigma) {
      if (_motionBlurSigma != 0.0) {
        setState(() => _motionBlurSigma = 0.0);
      }
      return;
    }
    _decayStartSigma = _motionBlurSigma;
    _decayController.forward(from: 0.0);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.enableScrollBlur ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final int nowMicros = DateTime.now().microsecondsSinceEpoch;
      final double dt = _lastUpdateMicros == 0
          ? 0.016
          : ((nowMicros - _lastUpdateMicros) / 1e6).clamp(0.008, 0.1);
      _lastUpdateMicros = nowMicros;

      final double delta = (notification.scrollDelta ?? 0.0).abs();
      final double velocityPxPerSec = delta / dt;
      final double target = velocityPxPerSec <= 450.0
          ? 0.0
          : ((velocityPxPerSec - 450.0) / 1800.0).clamp(0.0, 1.0) *
              _maxMotionBlurSigma;

      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(milliseconds: 64), _startDecay);

      if (target > _motionBlurSigma) {
        _decayController.stop();
        final double next = target < _minActiveBlurSigma ? 0.0 : target;
        if ((next - _motionBlurSigma).abs() > 0.02) {
          setState(() => _motionBlurSigma = next);
        }
      }
    } else if (notification is ScrollEndNotification) {
      _lastUpdateMicros = 0;
      _startDecay();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget draggableHeader = widget.hasHeaderDrag
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: widget.onHeaderDragStart,
            onVerticalDragUpdate: widget.onHeaderDragUpdate,
            onVerticalDragEnd: widget.onHeaderDragEnd,
            onVerticalDragCancel: widget.onHeaderDragCancel,
            child: widget.headerContent,
          )
        : widget.headerContent;

    if (!widget.enableScrollBlur) {
      return Material(
        color: scheme.surface,
        child: Column(
          children: <Widget>[
            draggableHeader,
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  top: widget.listTopPadding,
                  bottom: widget.listBottomPadding,
                ),
                children: widget.children,
              ),
            ),
          ],
        ),
      );
    }

    final double headerHeight = (widget.isSheet ? 18.0 : 0.0) + 68.0 + 1.0;

    final Widget listView = ImageFiltered(
      enabled: _motionBlurSigma > _minActiveBlurSigma,
      imageFilter: ui.ImageFilter.blur(
        sigmaX: 0.0,
        sigmaY: _motionBlurSigma,
      ),
      child: ListView(
        padding: EdgeInsets.only(
          top: headerHeight + widget.listTopPadding,
          bottom: widget.listBottomPadding,
        ),
        children: widget.children,
      ),
    );

    return Material(
      color: scheme.surface,
      child: Stack(
        children: <Widget>[
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: listView,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: scheme.surface.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      draggableHeader,
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _PanelHeader({
    required this.title,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, 10, 10, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: <Widget>[
            if (onBack != null) ...<Widget>[
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (onClose != null)
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}
