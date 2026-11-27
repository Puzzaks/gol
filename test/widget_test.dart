import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gol/engine/gol_engine.dart';
import 'package:gol/engine/gol_models.dart';
import 'package:gol/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GolEngine> _pumpGolApp(
  WidgetTester tester, {
  required Size viewportSize,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final GolEngine engine = GolEngine();
  addTearDown(engine.dispose);

  await tester.runAsync(() async {
    await engine.init();
  });

  await tester.pumpWidget(GolApp(engine: engine));
  await tester.pumpAndSettle();
  return engine;
}

Finder _findControl(
  List<String> labels, {
  List<IconData> icons = const <IconData>[],
}) {
  for (final String label in labels) {
    final Finder byTooltip = find.byTooltip(label);
    if (byTooltip.evaluate().isNotEmpty) return byTooltip;
    final Finder byText = find.text(label);
    if (byText.evaluate().isNotEmpty) return byText;
  }
  for (final IconData icon in icons) {
    final Finder byIcon = find.byIcon(icon);
    if (byIcon.evaluate().isNotEmpty) return byIcon;
  }
  return find.byTooltip(labels.first);
}

void _assertMinTouchTargetHeights(WidgetTester tester, String widgetTypeName) {
  final Finder hudFinder = find.byWidgetPredicate(
    (Widget w) => w.runtimeType.toString() == widgetTypeName,
  );
  expect(
    hudFinder,
    findsOneWidget,
    reason: 'Expected $widgetTypeName to be mounted in the HUD',
  );

  final Finder interactiveFinder = find.descendant(
    of: hudFinder,
    matching: find.byWidgetPredicate(
      (Widget w) =>
          w is IconButton ||
          w is ButtonStyleButton ||
          w is FloatingActionButton ||
          w is SegmentedButton ||
          w is InkWell,
    ),
  );

  final Iterable<Element> elements = interactiveFinder.evaluate();
  expect(
    elements,
    isNotEmpty,
    reason: 'Expected interactive controls inside $widgetTypeName',
  );

  for (final Element element in elements) {
    final RenderBox? box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    expect(
      box.size.height,
      greaterThanOrEqualTo(48.0),
      reason:
          'Interactive widget ${element.widget.runtimeType} inside '
          '$widgetTypeName had height ${box.size.height} (< 48.0 dp)',
    );
  }
}

void main() {
  testWidgets('Renders GolApp cleanly without errors on compact viewport',
      (WidgetTester tester) async {
    final GolEngine engine = await _pumpGolApp(
      tester,
      viewportSize: const Size(400, 840),
    );

    expect(tester.takeException(), isNull);
    expect(engine.initialized, isTrue);
    expect(engine.population, greaterThan(0));
  });

  testWidgets(
      'All interactive HUD buttons/pills in HudStatusRow and HudBottomBar '
      'meet >= 48.0 dp height accessibility requirement',
      (WidgetTester tester) async {
    await _pumpGolApp(
      tester,
      viewportSize: const Size(400, 840),
    );

    _assertMinTouchTargetHeights(tester, 'HudStatusRow');
    _assertMinTouchTargetHeights(tester, 'HudBottomBar');
  });

  testWidgets(
      'Draw/Pan toggle, Play/Pause, Step, and Inspector work on compact phone (400x840)',
      (WidgetTester tester) async {
    final GolEngine engine = await _pumpGolApp(
      tester,
      viewportSize: const Size(400, 840),
    );

    // 1. Draw / Pan toggle
    expect(engine.activeTool, CanvasTool.draw);
    final Finder panControl = _findControl(
      const <String>['Pan', 'pan_tool'],
      icons: const <IconData>[
        Icons.pan_tool_rounded,
        Icons.pan_tool_outlined,
        Icons.open_with_rounded,
        Icons.back_hand_rounded,
      ],
    );
    await tester.tap(panControl.first);
    await tester.pumpAndSettle();
    expect(engine.activeTool, CanvasTool.pan);

    final Finder drawControl = _findControl(
      const <String>['Draw', 'draw_tool'],
      icons: const <IconData>[
        Icons.edit_rounded,
        Icons.draw_rounded,
        Icons.brush_rounded,
      ],
    );
    await tester.tap(drawControl.first);
    await tester.pumpAndSettle();
    expect(engine.activeTool, CanvasTool.draw);

    // 2. Step advances generation by 1
    final int genBefore = engine.generation;
    final Finder stepControl = _findControl(
      const <String>['Step', 'step'],
      icons: const <IconData>[
        Icons.skip_next_rounded,
        Icons.redo_rounded,
      ],
    );
    await tester.tap(stepControl.first);
    await tester.pumpAndSettle();
    expect(engine.generation, genBefore + 1);

    // 3. Play / Pause
    expect(engine.isPlaying, isFalse);
    final Finder playControl = _findControl(
      const <String>['Play', 'play'],
      icons: const <IconData>[
        Icons.play_arrow_rounded,
        Icons.play_arrow,
      ],
    );
    await tester.tap(playControl.first);
    await tester.pump(const Duration(milliseconds: 120));
    expect(engine.isPlaying, isTrue);

    final Finder pauseControl = _findControl(
      const <String>['Pause', 'pause'],
      icons: const <IconData>[
        Icons.pause_rounded,
        Icons.pause,
      ],
    );
    await tester.tap(pauseControl.first);
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isFalse);

    // 4. Open & close Inspector sheet on compact phone
    final Finder inspectorControl = _findControl(
      const <String>['Inspector', 'inspector_title', 'Settings'],
      icons: const <IconData>[
        Icons.tune_rounded,
        Icons.view_sidebar_rounded,
        Icons.dock_rounded,
      ],
    );
    await tester.tap(inspectorControl.first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Simulation').evaluate().isNotEmpty ||
          find.textContaining('Inspector').evaluate().isNotEmpty ||
          find.textContaining('Speed').evaluate().isNotEmpty,
      isTrue,
      reason: 'Expected Inspector panel/sheet to be visible after tapping toggle',
    );

    // Close modal sheet / inspector
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Draw/Pan toggle, Play/Pause, Step, and Inspector dock toggle work on '
      'expanded desktop (1280x800)', (WidgetTester tester) async {
    final GolEngine engine = await _pumpGolApp(
      tester,
      viewportSize: const Size(1280, 800),
    );

    expect(tester.takeException(), isNull);
    _assertMinTouchTargetHeights(tester, 'HudStatusRow');
    _assertMinTouchTargetHeights(tester, 'HudBottomBar');

    // Toggle Pan -> Draw
    final Finder panControl = _findControl(
      const <String>['Pan', 'pan_tool'],
      icons: const <IconData>[
        Icons.pan_tool_rounded,
        Icons.pan_tool_outlined,
        Icons.open_with_rounded,
        Icons.back_hand_rounded,
      ],
    );
    await tester.tap(panControl.first);
    await tester.pumpAndSettle();
    expect(engine.activeTool, CanvasTool.pan);

    final Finder drawControl = _findControl(
      const <String>['Draw', 'draw_tool'],
      icons: const <IconData>[
        Icons.edit_rounded,
        Icons.draw_rounded,
        Icons.brush_rounded,
      ],
    );
    await tester.tap(drawControl.first);
    await tester.pumpAndSettle();
    expect(engine.activeTool, CanvasTool.draw);

    // Step
    final int genBefore = engine.generation;
    final Finder stepControl = _findControl(
      const <String>['Step', 'step'],
      icons: const <IconData>[
        Icons.skip_next_rounded,
      ],
    );
    await tester.tap(stepControl.first);
    await tester.pumpAndSettle();
    expect(engine.generation, genBefore + 1);

    // Play / Pause
    final Finder playControl = _findControl(
      const <String>['Play', 'play'],
      icons: const <IconData>[
        Icons.play_arrow_rounded,
        Icons.play_arrow,
      ],
    );
    await tester.tap(playControl.first);
    await tester.pump(const Duration(milliseconds: 120));
    expect(engine.isPlaying, isTrue);

    final Finder pauseControl = _findControl(
      const <String>['Pause', 'pause'],
      icons: const <IconData>[
        Icons.pause_rounded,
        Icons.pause,
      ],
    );
    await tester.tap(pauseControl.first);
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isFalse);

    // Toggle docked Inspector closed and back open
    final Finder inspectorControl = _findControl(
      const <String>['Inspector', 'inspector_title', 'Settings'],
      icons: const <IconData>[
        Icons.tune_rounded,
        Icons.view_sidebar_rounded,
        Icons.dock_rounded,
      ],
    );
    await tester.tap(inspectorControl.first);
    await tester.pumpAndSettle();
    final Finder closeButton = find.byIcon(Icons.close_rounded);
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
