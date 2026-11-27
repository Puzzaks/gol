import 'dart:async';
import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:provider/provider.dart';

import 'engine/gol_engine.dart';
import 'engine/gol_models.dart';
import 'engine/gol_share_link.dart';
import 'engine/rle_codec.dart';
import 'widgets/app_toast.dart';
import 'widgets/gol_canvas.dart';
import 'widgets/hud_overlay.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/patterns_sheet.dart';
import 'widgets/share_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GolApp());
}

/// Root Material 3 eXtended application widget for Golr.
///
/// Accepts an optional pre-configured [engine] for deterministic widget tests;
/// in production, creates, initializes, and disposes its own [GolEngine].
class GolApp extends StatefulWidget {
  final GolEngine? engine;

  const GolApp({
    super.key,
    this.engine,
  });

  @override
  State<GolApp> createState() => _GolAppState();
}

class _GolAppState extends State<GolApp> {
  static final ColorScheme _fallbackLightScheme =
      ColorScheme.fromSeed(seedColor: Colors.teal);
  static final ColorScheme _fallbackDarkScheme = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  GolEngine? _ownedEngine;
  int _localeRevision = 0;

  GolEngine get _activeEngine => widget.engine ?? _ownedEngine!;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    if (widget.engine == null) {
      _ownedEngine = GolEngine();
      unawaited(_ownedEngine!.init());
    }
  }

  @override
  void didUpdateWidget(covariant GolApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      if (widget.engine != null) {
        _ownedEngine?.dispose();
        _ownedEngine = null;
      } else if (_ownedEngine == null) {
        _ownedEngine = GolEngine();
        unawaited(_ownedEngine!.init());
      }
    }
  }

  @override
  void dispose() {
    _ownedEngine?.dispose();
    _ownedEngine = null;
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (!mounted) return;
    setState(() {
      _localeRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = _activeEngine;

    return ChangeNotifierProvider<GolEngine>.value(
      value: engine,
      child: DynamicColorBuilder(
        builder: (
          ColorScheme? lightDynamic,
          ColorScheme? darkDynamic,
        ) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (BuildContext ctx) {
              final GolEngine eng = ctx.read<GolEngine>();
              if (!eng.initialized) return 'Game of Life';
              final String raw = eng.tr('app_title');
              return (raw.isEmpty || raw == 'app_title' || raw.startsWith('!'))
                  ? 'Game of Life'
                  : raw;
            },
            themeMode: ThemeMode.system,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: lightDynamic ?? _fallbackLightScheme,
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: darkDynamic ?? _fallbackDarkScheme,
            ),
            home: GolExplorerPage(
              localeRevision: _localeRevision,
              onLocaleChanged: _handleLocaleChanged,
            ),
          );
        },
      ),
    );
  }
}

/// Adaptive 3-state framed Game of Life workspace:
/// - State 0 (Fullscreen): edge-to-edge canvas.
/// - State 1 (Framed Card HUD): rounded simulation card with two non-overlapping
///   Material 3 stadium HUD rows below the card.
/// - State 2 (Split Inspector): in-place animated split layout (35%/65% vertical
///   draggable sheet on compact phones, 50%/50% horizontal on medium, 67%/33%
///   docked panel on expanded screens).
class GolExplorerPage extends StatefulWidget {
  final int localeRevision;
  final VoidCallback? onLocaleChanged;

  const GolExplorerPage({
    super.key,
    this.localeRevision = 0,
    this.onLocaleChanged,
  });

  @override
  State<GolExplorerPage> createState() => _GolExplorerPageState();
}

class _GolExplorerPageState extends State<GolExplorerPage> {
  static const Duration _layoutAnimDuration = Duration(milliseconds: 280);
  static const Curve _layoutAnimCurve = Curves.easeOutCubic;
  static const MethodChannel _displayChannel =
      MethodChannel('page.puzzak.gol/display');

  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey<NavigatorState> _inspectorNavKey = GlobalKey<NavigatorState>();
  final ValueNotifier<Size> _viewportNotifier = ValueNotifier<Size>(Size.zero);

  late final GolEngine _engine;
  bool _showHud = true;
  bool _inspectorOpen = false;
  double _compactInspectorFraction = 0.65;
  bool _isDraggingInspector = false;
  double _dragStartGlobalY = 0.0;
  double _dragStartFraction = 0.65;
  Size _latestViewport = Size.zero;
  bool _startupHintScheduled = false;
  bool _initialDeepLinkChecked = false;
  SharedGolPayload? _pendingSharedPayload;

  @override
  void initState() {
    super.initState();
    _engine = context.read<GolEngine>();
    _displayChannel.setMethodCallHandler(_handleDisplayChannelCall);
    if (_engine.initialized) {
      _scheduleStartupHint();
    } else {
      _engine.addListener(_onEngineInitForHint);
    }
  }

  void _onEngineInitForHint() {
    if (!_engine.initialized) return;
    _engine.removeListener(_onEngineInitForHint);
    _scheduleStartupHint();
  }

  void _scheduleStartupHint() {
    if (_startupHintScheduled) return;
    _startupHintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_checkInitialDeepLink());
      showAppToast(
        context,
        _trOr(_engine, 'hud_long_press_hint', 'Long-press Clear to reset board'),
      );
    });
  }

  Future<dynamic> _handleDisplayChannelCall(MethodCall call) async {
    if (call.method == 'onDeepLink') {
      _handleIncomingDeepLink(call.arguments as String?);
    }
    return null;
  }

  Future<void> _checkInitialDeepLink() async {
    if (!mounted || _initialDeepLinkChecked) return;
    _initialDeepLinkChecked = true;
    if (kIsWeb) {
      _handleIncomingDeepLink(Uri.base.toString());
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final String? initialLink =
            await _displayChannel.invokeMethod<String>('getInitialDeepLink');
        if (!mounted) return;
        if (initialLink != null && initialLink.trim().isNotEmpty) {
          _handleIncomingDeepLink(initialLink);
        }
      } catch (_) {
        // Ignore platform channel errors on unsupported hosts or tests.
      }
    }
  }

  void _handleIncomingDeepLink(String? raw) {
    final SharedGolPayload? payload = GolShareLink.tryParse(raw);
    if (payload == null || !mounted) return;
    _engine.pause();
    _engine.setTopology(payload.topology);
    _engine.setRule(payload.rule);
    _engine.setPalette(payload.palette);
    _engine.clear();
    final int cx = _engine.topology == GridTopology.infinite
        ? 0
        : _engine.finiteWidth ~/ 2;
    final int cy = _engine.topology == GridTopology.infinite
        ? 0
        : _engine.finiteHeight ~/ 2;
    _engine.grid.stamp(
      payload.cells,
      cx - (payload.width ~/ 2),
      cy - (payload.height ~/ 2),
    );
    if (_latestViewport.isEmpty) {
      _engine.resetCamera();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_latestViewport.isEmpty) {
          _engine.fitToContent(_latestViewport);
        }
      });
    } else {
      _engine.fitToContent(_latestViewport);
    }
    setState(() {
      _pendingSharedPayload = payload;
    });
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineInitForHint);
    _displayChannel.setMethodCallHandler(null);
    _viewportNotifier.dispose();
    super.dispose();
  }

  String _trOr(GolEngine engine, String key, String fallback) {
    final String raw = engine.tr(key);
    if (raw.isEmpty || raw == key || raw.startsWith('!')) {
      return fallback;
    }
    return raw;
  }

  void _toggleFullscreen() {
    setState(() {
      if (_inspectorOpen) {
        _inspectorOpen = false;
        _compactInspectorFraction = 0.65;
        _showHud = false;
      } else {
        _showHud = !_showHud;
      }
    });
  }

  void _toggleInspector() {
    setState(() {
      _inspectorOpen = !_inspectorOpen;
      _compactInspectorFraction = 0.65;
      if (_inspectorOpen) {
        _showHud = true;
      }
    });
  }

  void _closeInspector() {
    if (!_inspectorOpen) return;
    setState(() {
      _inspectorOpen = false;
      _compactInspectorFraction = 0.65;
    });
  }

  List<(int, int)> _extractCropCells(GolEngine engine) {
    final (int, int)? start = engine.cropStart;
    final (int, int)? end = engine.cropEnd;
    if (start == null || end == null) {
      return const <(int, int)>[];
    }
    final int minX = math.min(start.$1, end.$1);
    final int maxX = math.max(start.$1, end.$1);
    final int minY = math.min(start.$2, end.$2);
    final int maxY = math.max(start.$2, end.$2);
    return engine.grid.extractRegion(minX, minY, maxX, maxY, maxCells: 16384);
  }

  Future<void> _handleSaveCrop() async {
    final List<(int, int)> cells = _extractCropCells(_engine);
    if (cells.isEmpty) {
      showAppToast(
        context,
        _trOr(_engine, 'crop_empty', 'No live cells in selection'),
      );
      return;
    }
    await showSavePatternDialog(
      context,
      cells: cells,
      truncated: cells.length >= 16384,
    );
  }

  Future<void> _handleCopyCropRle() async {
    final List<(int, int)> cells = _extractCropCells(_engine);
    if (cells.isEmpty) {
      showAppToast(
        context,
        _trOr(_engine, 'crop_empty', 'No live cells in selection'),
      );
      return;
    }
    final RleEncodeResult encoded = RleCodec.encode(
      cells,
      rule: _engine.rule.notation,
    );
    await Clipboard.setData(ClipboardData(text: encoded.rle));
    if (!mounted) return;
    showAppToast(
      context,
      _trOr(_engine, 'copied_rle', 'RLE copied to clipboard'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EdgeInsets mediaPadding = MediaQuery.paddingOf(context);
    final bool isFullscreen = !_showHud && !_inspectorOpen;
    final bool showHudChrome = _showHud && !_inspectorOpen;
    final Color canvasBg = engine.palette.resolveColors(scheme).background;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_inspectorOpen &&
            (_inspectorNavKey.currentState?.canPop() ?? false)) {
          _inspectorNavKey.currentState!.pop();
        } else if (_inspectorOpen) {
          _closeInspector();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final M3xWindowSizeClass sizeClass =
                M3xWindowSizeClass.fromWidth(constraints.maxWidth);
            final EdgeInsets outerPadding = isFullscreen
                ? EdgeInsets.zero
                : EdgeInsets.fromLTRB(
                    mediaPadding.left + 12,
                    mediaPadding.top + 8,
                    mediaPadding.right + 12,
                    mediaPadding.bottom + 10,
                  );
            final double innerWidth =
                (constraints.maxWidth - outerPadding.horizontal)
                    .clamp(120.0, double.infinity);
            final double innerHeight =
                (constraints.maxHeight - outerPadding.vertical)
                    .clamp(120.0, double.infinity);

            final Widget canvasCard = TweenAnimationBuilder<double>(
              tween: Tween<double>(end: isFullscreen ? 0.0 : 24.0),
              duration: _layoutAnimDuration,
              curve: _layoutAnimCurve,
              builder: (BuildContext context, double radius, Widget? child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(color: canvasBg),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    GolCanvas(
                      key: _canvasKey,
                      onToggleFullscreen: _toggleFullscreen,
                      onViewportChanged: (Size size) {
                        _latestViewport = size;
                        _viewportNotifier.value = size;
                      },
                      onTapWhenInspectorOpen:
                          _inspectorOpen ? _closeInspector : null,
                      inspectorOpen: _inspectorOpen,
                      onSaveCropRequested: _handleSaveCrop,
                    ),
                    if (_pendingSharedPayload != null)
                      Positioned(
                        top: (isFullscreen ? mediaPadding.top : 0.0) + 12.0,
                        left: 12,
                        right: 12,
                        child: Center(
                          child: _SharedPatternPreviewPill(
                            payload: _pendingSharedPayload!,
                            onSave: () {
                              final SharedGolPayload payload =
                                  _pendingSharedPayload!;
                              final String fallbackName =
                                  '${payload.width}×${payload.height} Pattern';
                              final String? rawName = payload.name?.trim();
                              engine.saveCustomPattern(
                                name: (rawName != null && rawName.isNotEmpty)
                                    ? rawName
                                    : fallbackName,
                                cells: payload.cells,
                              );
                              showAppToast(
                                context,
                                _trOr(
                                  engine,
                                  'shared_preview_saved',
                                  'Pattern saved to library',
                                ),
                              );
                            },
                            onDismiss: () {
                              setState(() {
                                _pendingSharedPayload = null;
                              });
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );

            final Widget bottomBarSlot = AnimatedContainer(
              duration: _layoutAnimDuration,
              curve: _layoutAnimCurve,
              height: showHudChrome ? 132.0 : 0.0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: 122.0,
                maxHeight: 132.0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AnimatedOpacity(
                    opacity: showHudChrome ? 1.0 : 0.0,
                    duration: _layoutAnimDuration,
                    curve: _layoutAnimCurve,
                    child: IgnorePointer(
                      ignoring: !showHudChrome,
                      child: ExcludeSemantics(
                        excluding: !showHudChrome,
                        child: ExcludeFocus(
                          excluding: !showHudChrome,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              HudStatusRow(
                                onOpenPatterns: () => showPatternsSheet(
                                  context,
                                  viewportSize: _latestViewport,
                                ),
                                onFitToContent: () => showShareGolSheet(
                                  context,
                                  engine,
                                  onStartCrop: () =>
                                      engine.setActiveTool(CanvasTool.crop),
                                ),
                              ),
                              const SizedBox(height: 8),
                              HudBottomBar(
                                onOpenPatterns: () => showPatternsSheet(
                                  context,
                                  viewportSize: _latestViewport,
                                ),
                                onOpenPalette: () =>
                                    showPaletteSelectorSheet(context),
                                onOpenInspector: _toggleInspector,
                                onSaveCrop: _handleSaveCrop,
                                onCopyCropRle: _handleCopyCropRle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            final Widget inspectorCard = InspectorSheetDragScope(
              onDragStart: sizeClass.isCompact
                  ? (DragStartDetails details) {
                      _dragStartGlobalY = details.globalPosition.dy;
                      _dragStartFraction = _compactInspectorFraction;
                      setState(() => _isDraggingInspector = true);
                    }
                  : null,
              onDragUpdate: sizeClass.isCompact
                  ? (DragUpdateDetails details) {
                      final double dy =
                          details.globalPosition.dy - _dragStartGlobalY;
                      setState(() {
                        _compactInspectorFraction =
                            (_dragStartFraction -
                                    dy / math.max(1.0, innerHeight))
                                .clamp(0.20, 1.0);
                      });
                    }
                  : null,
              onDragEnd: sizeClass.isCompact
                  ? (DragEndDetails details) {
                      final double velocity = details.primaryVelocity ?? 0.0;
                      setState(() {
                        _isDraggingInspector = false;
                        if (velocity < -450 ||
                            _compactInspectorFraction >= 0.80) {
                          _compactInspectorFraction = 1.0;
                        } else if (velocity > 450) {
                          if (_compactInspectorFraction >= 0.72) {
                            _compactInspectorFraction = 0.65;
                          } else {
                            _inspectorOpen = false;
                            _compactInspectorFraction = 0.65;
                          }
                        } else if (_compactInspectorFraction < 0.38) {
                          _inspectorOpen = false;
                          _compactInspectorFraction = 0.65;
                        } else {
                          _compactInspectorFraction = 0.65;
                        }
                      });
                    }
                  : null,
              onDragCancel: sizeClass.isCompact
                  ? () {
                      setState(() => _isDraggingInspector = false);
                    }
                  : null,
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InspectorPanel(
                  navigatorKey: _inspectorNavKey,
                  viewportNotifier: _viewportNotifier,
                  onClose: _closeInspector,
                  isSheet: sizeClass.isCompact,
                  onLocaleChanged: widget.onLocaleChanged,
                ),
              ),
            );

            final Widget layoutBody;
            if (sizeClass.isCompact) {
              final double openInspectorHeight = innerHeight <= 0
                  ? 0.0
                  : (innerHeight * _compactInspectorFraction)
                      .clamp(0.0, innerHeight);
              final double topGap =
                  (_inspectorOpen && _compactInspectorFraction >= 0.98)
                      ? 0.0
                      : 10.0;
              layoutBody = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: canvasCard),
                  bottomBarSlot,
                  AnimatedContainer(
                    duration: _isDraggingInspector
                        ? Duration.zero
                        : _layoutAnimDuration,
                    curve: _layoutAnimCurve,
                    height: _inspectorOpen ? openInspectorHeight : 0.0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: openInspectorHeight,
                      maxHeight: openInspectorHeight,
                      child: SizedBox(
                        height: openInspectorHeight,
                        child: Padding(
                          padding: EdgeInsets.only(top: topGap),
                          child: AnimatedOpacity(
                            opacity: _inspectorOpen ? 1.0 : 0.0,
                            duration: _layoutAnimDuration,
                            curve: _layoutAnimCurve,
                            child: IgnorePointer(
                              ignoring: !_inspectorOpen,
                              child: ExcludeSemantics(
                                excluding: !_inspectorOpen,
                                child: ExcludeFocus(
                                  excluding: !_inspectorOpen,
                                  child: inspectorCard,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              final double minWidth = math.min(280.0, innerWidth);
              final double openInspectorWidth = innerWidth <= 0
                  ? 0.0
                  : (sizeClass.isExpanded
                      ? (innerWidth / 3.0).clamp(minWidth, innerWidth)
                      : (innerWidth * 0.5).clamp(minWidth, innerWidth));
              layoutBody = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: canvasCard),
                        bottomBarSlot,
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: _layoutAnimDuration,
                    curve: _layoutAnimCurve,
                    width: _inspectorOpen ? openInspectorWidth : 0.0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: OverflowBox(
                      alignment: AlignmentDirectional.centerStart,
                      minWidth: openInspectorWidth,
                      maxWidth: openInspectorWidth,
                      child: SizedBox(
                        width: openInspectorWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: AnimatedOpacity(
                            opacity: _inspectorOpen ? 1.0 : 0.0,
                            duration: _layoutAnimDuration,
                            curve: _layoutAnimCurve,
                            child: IgnorePointer(
                              ignoring: !_inspectorOpen,
                              child: ExcludeSemantics(
                                excluding: !_inspectorOpen,
                                child: ExcludeFocus(
                                  excluding: !_inspectorOpen,
                                  child: inspectorCard,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return AnimatedPadding(
              duration: _layoutAnimDuration,
              curve: _layoutAnimCurve,
              padding: outerPadding,
              child: layoutBody,
            );
          },
        ),
      ),
    );
  }
}

class _SharedPatternPreviewPill extends StatefulWidget {
  final SharedGolPayload payload;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const _SharedPatternPreviewPill({
    required this.payload,
    required this.onSave,
    required this.onDismiss,
  });

  @override
  State<_SharedPatternPreviewPill> createState() =>
      _SharedPatternPreviewPillState();
}

class _SharedPatternPreviewPillState extends State<_SharedPatternPreviewPill> {
  bool _saved = false;

  @override
  void didUpdateWidget(covariant _SharedPatternPreviewPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      _saved = false;
    }
  }

  String _trOr(GolEngine engine, String key, String fallback) {
    final String raw = engine.tr(key);
    if (raw.isEmpty || raw == key || raw.startsWith('!')) {
      return fallback;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = context.watch<GolEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final String? trimmedName = widget.payload.name?.trim();
    final String title = (trimmedName != null && trimmedName.isNotEmpty)
        ? trimmedName
        : _trOr(engine, 'shared_preview_loaded', 'Shared pattern loaded');
    final String cellsLabel =
        _trOr(engine, 'cells_label', 'cells').toLowerCase();
    final String stats =
        '${widget.payload.width}×${widget.payload.height} · ${widget.payload.cells.length} $cellsLabel · ${widget.payload.rule.notation}';

    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
      elevation: 2,
      shape: StadiumBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.link_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    stats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              constraints: const BoxConstraints.tightFor(
                width: 48,
                height: 48,
              ),
              onPressed: _saved
                  ? null
                  : () {
                      setState(() {
                        _saved = true;
                      });
                      widget.onSave();
                    },
              tooltip: _saved
                  ? _trOr(engine, 'shared_preview_saved', 'Pattern saved')
                  : _trOr(engine, 'shared_preview_save', 'Save'),
              icon: Icon(
                _saved
                    ? Icons.bookmark_added_rounded
                    : Icons.bookmark_add_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(
                width: 48,
                height: 48,
              ),
              onPressed: widget.onDismiss,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
