import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invert_colors/invert_colors.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Ensure you have this package in your pubspec.yaml
import 'generator.dart';
import 'package:collection/collection.dart' as c;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => GameOfLifeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HomeScreen();
  }
}

class HomeScreen extends StatelessWidget {
  bool firstBoot = true;
  bool systemColor = true;
  bool userDrawn = false;
  static final _defaultLightColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal);
  static final _defaultDarkColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal, brightness: Brightness.dark);
  final MaterialStateProperty<Icon?> playicon =
  MaterialStateProperty.resolveWith<Icon?>(
        (Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return const Icon(Icons.play_arrow_rounded);
      }
      return const Icon(Icons.pause_rounded);
    },
  );
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: lightColorScheme ?? _defaultLightColorScheme,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: Consumer<GameOfLifeProvider>(
          builder: (context, gameProvider, child) {
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                // backgroundColor: Theme.of(context).colorScheme.background,
                enableDrag: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (BuildContext context) {
                  return mainSettings();
                },
              );
            },
            tooltip: "Settings",
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            isExtended: true,
            child: const Icon(Icons.tune_rounded),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final cellSize = constraints.maxWidth / gameProvider.cols;
              final rows = (constraints.maxHeight / cellSize).floor();
              final cols = (constraints.maxWidth / cellSize).floor();
              final ColorScheme colorScheme = Theme.of(context).colorScheme;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                gameProvider.updateGridSize(rows, cols);
                if(firstBoot){
                  if (Platform.isAndroid) {
                    var androidInfo = await DeviceInfoPlugin().androidInfo;
                    var sdkInt = androidInfo.version.sdkInt;
                    if(sdkInt < 31){
                      SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.manual, overlays: [
                            SystemUiOverlay.top, SystemUiOverlay.bottom
                      ]);
                    }else{
                      SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.manual, overlays: [
                        SystemUiOverlay.top
                      ]);
                    }
                    SystemChrome.setSystemUIOverlayStyle(
                      SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarIconBrightness: Brightness.light,
                        systemNavigationBarColor: Colors.transparent,
                      ),
                    );
                  }
                  gameProvider.updateLiveColor(colorScheme.primary);
                  print(colorScheme.primary);
                  print(colorScheme.primary == colorScheme.primaryContainer);
                  if(colorScheme.primary == colorScheme.primaryContainer){
                    gameProvider.updateDeadColor(Colors.black);
                  }else{
                    gameProvider.updateDeadColor(colorScheme.primaryContainer);
                  }
                  await Future.delayed(const Duration(milliseconds: 200)).then((value){
                    gameProvider.updateLiveColor(colorScheme.primary);
                    print(colorScheme.primary);
                    print(colorScheme.primary == colorScheme.primaryContainer);
                    if(colorScheme.primary == colorScheme.primaryContainer){
                      gameProvider.updateLiveColor(Color(0xff00bfb0));
                      gameProvider.updateDeadColor(Color(0xff005850));
                    }else{
                      gameProvider.updateDeadColor(colorScheme.primaryContainer);
                    }
                    firstBoot = false;
                  });
                }
              });
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    color: gameProvider.deadColor,
                  ),
                  GestureDetector(
                    onTapDown: (details) {
                      if(!userDrawn){
                        userDrawn = true;
                      }
                      final cellSize = constraints.maxWidth / gameProvider.cols;
                      final row = (details.localPosition.dy / cellSize).floor();
                      final col = (details.localPosition.dx / cellSize).floor();
                      gameProvider.toggleCell(row, col);
                    },
                    onPanUpdate: (details) {
                      if(!userDrawn){
                        userDrawn = true;
                      }
                      final cellSize = constraints.maxWidth / gameProvider.cols;
                      final row = (details.localPosition.dy / cellSize).floor();
                      final col = (details.localPosition.dx / cellSize).floor();
                      gameProvider.toggleCell(row, col);
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: GridPainter(gameProvider.grid, gameProvider),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    child: Switch(
                      thumbIcon: playicon,
                      trackOutlineColor: gameProvider.isPlaying?MaterialStateProperty.all(Theme.of(context).colorScheme.onPrimary):null,
                      value: gameProvider.isPlaying,
                      onChanged: (value) {
                        if (value) {
                          gameProvider.startGameOfLife();
                        } else {
                          gameProvider.stopGameOfLife();
                        }
                      },
                    ),
                  ),
                  userDrawn?Container():Positioned(
                    top: 45,
                    left: 15,
                    right: 15,
                    child: Container(
                      width: constraints.maxWidth,
                      child: const Card(
                        elevation: 2,
                        child: Padding(
                          padding: EdgeInsets.all(15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Draw on the grid",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                  Text(
                                    "You can interact with cells, try it!",
                                  )
                                ],
                              ),
                              Icon(Icons.info_outline_rounded),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      ),
      );
    });
  }
}

Future<Color?> _selectColor(BuildContext context, Color currentColor) async {
  Color selectedColor = currentColor;

  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      actionsPadding: const EdgeInsets.only(bottom: 15,right: 15),
      scrollable: true,
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: currentColor,
          onColorChanged: (color) => selectedColor = color,
          enableAlpha: false,
          portraitOnly: false,
          pickerAreaHeightPercent: 0.75,
          hexInputBar: true,
          displayThumbColor: true,
          pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(15)),
        ),
      ),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: const Text("Save"),
          onPressed: () => Navigator.of(context).pop(selectedColor),
        ),
      ],
    ),
  );
}

class GridPainter extends CustomPainter {
  final List<List<bool>> grid;
  final GameOfLifeProvider provider;

  GridPainter(this.grid, this.provider);

  @override
  void paint(Canvas canvas, Size size) {
    DateTime startDrawTime = DateTime.now();
    final paint = Paint()
      ..strokeWidth = provider.borderThickness * provider.scale
      ..color = provider.deadColor
      ..style = PaintingStyle.stroke;

    final cellWidth = size.width / provider.cols;
    final cellHeight = size.height / provider.rows;
    final radius = provider.borderRadius * provider.scale;

    for (int y = 0; y < provider.rows; y++) {
      for (int x = 0; x < provider.cols; x++) {
        final rect = Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight);
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

        final fillPaint = Paint()
          ..color = grid[y][x] ? provider.liveColor : provider.deadColor
          ..style = PaintingStyle.fill;

        if (provider.borderRadius > 0) {
          canvas.drawRRect(rrect, fillPaint);
        } else {
          canvas.drawRect(rect, fillPaint);
        }

        if (provider.borderThickness > 0) {
          paint.strokeWidth = provider.borderThickness * provider.scale;
          canvas.drawRect(rect, paint);
        }
      }
    }
    provider.drawTime = DateTime.now().difference(startDrawTime).inMilliseconds;
    if(provider.drawTime == 0 || provider.frameTime == 0 || provider.animationSpeed == 0){
      //skipframe
    }{
      provider.fpss.insert(0, provider.drawTime + provider.frameTime + provider.animationSpeed);
      if(provider.fpss.length > 50){
        provider.fpss.removeLast();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}


class mainSettings extends StatefulWidget {

  @override
  _mainSettingsState createState() => _mainSettingsState();
}

class _mainSettingsState extends State<mainSettings> {
  @override
  void initState() {
    super.initState();
  }

  String formatDouble(String stringValue) {
    int lastZero = 0;
    int dotIndex = stringValue.indexOf('.') + 1;
    if (double.parse(stringValue) >= 1) {
      return (double.parse(stringValue).toInt().toString());
    }
    if (double.parse(stringValue) >= 0.1) {
      return (stringValue.substring(0, 3));
    }
    for (int i = dotIndex; i < stringValue.length; i++) {
      if (stringValue[i] == "0") {
        lastZero = i;
      } else {
        break;
      }
    }

    return stringValue.substring(0, dotIndex + lastZero);
  }
  final MaterialStateProperty<Icon?> thumbIcon =
  MaterialStateProperty.resolveWith<Icon?>(
        (Set<MaterialState> states) {
      if (states.contains(MaterialState.selected)) {
        return const Icon(Icons.check);
      }
      return const Icon(Icons.close);
    },
  );

  bool systemColor = true;
  static final _defaultLightColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal);
  static final _defaultDarkColorScheme = ColorScheme.fromSwatch(primarySwatch: Colors.teal, brightness: Brightness.dark);
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: lightColorScheme ?? _defaultLightColorScheme,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: darkColorScheme ?? _defaultDarkColorScheme,
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: Consumer<GameOfLifeProvider>(
          builder: (context, gameProvider, child) {
            final MaterialStateProperty<Icon?> playicon =
            MaterialStateProperty.resolveWith<Icon?>(
                  (Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) {
                  return const Icon(Icons.play_arrow_rounded);
                }
                return const Icon(Icons.pause_rounded);
              },
            );
            final MaterialStateProperty<Icon?> themeicon =
            MaterialStateProperty.resolveWith<Icon?>(
                  (Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) {
                  return const Icon(Icons.android_rounded);
                }
                return const Icon(Icons.palette_rounded);
              },
            );
            return Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Generate GoL",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18
                                        ),
                                      ),
                                      Text(
                                        "Play/Pause Game of Life",
                                      )
                                    ],
                                  ),
                                  Switch(
                                    thumbIcon: playicon,
                                    value: gameProvider.isPlaying,
                                    onChanged: (value) {
                                      if (value) {
                                        gameProvider.startGameOfLife();
                                      } else {
                                        gameProvider.stopGameOfLife();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Column(
                              children: [
                                Padding(
                                  padding: gameProvider.useSystemColors? const EdgeInsets.all(15):const EdgeInsets.only(
                                    top:15,left: 15,right: 15
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Use system colors",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18
                                            ),
                                          ),
                                          Text(
                                            "Disable to choose cell colors",
                                          )
                                        ],
                                      ),
                                      Switch(
                                        thumbIcon: themeicon,
                                        value: gameProvider.useSystemColors,
                                        onChanged: (value) {
                                          setState(() {
                                            gameProvider.useSystemColors = value;
                                          });
                                          if (value) {
                                            if(Theme.of(context).colorScheme.primary == Theme.of(context).colorScheme.primaryContainer){
                                              gameProvider.updateLiveColor(Color(0xff00bfb0));
                                              gameProvider.updateDeadColor(Color(0xff005850));
                                            }else{
                                              gameProvider.updateLiveColor(Theme.of(context).colorScheme.primary);
                                              gameProvider.updateDeadColor(Theme.of(context).colorScheme.primaryContainer);
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                gameProvider.useSystemColors?Container():Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(15),
                                      child: GestureDetector(
                                        onTap: () async {
                                          final color = await _selectColor(context, gameProvider.liveColor);
                                          if (color != null) {
                                            setState(() {
                                              gameProvider.updateLiveColor(color);
                                            });
                                          }
                                        },
                                        child: ColorCard(
                                          label: 'Live Color',
                                          color: gameProvider.liveColor,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 15,bottom: 15,right: 15),
                                      child: GestureDetector(
                                        onTap: () async {
                                          final color = await _selectColor(context, gameProvider.deadColor);
                                          if (color != null) {
                                            gameProvider.updateDeadColor(color);
                                          }
                                        },
                                        child: ColorCard(
                                          label: 'Dead Color',
                                          color: gameProvider.deadColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(
                                      left: 15, top: 15, right: 15
                                  ),
                                  child: Text(
                                    "Speed",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                ),
                                Slider(
                                  value: (1000 - gameProvider.animationSpeed).toDouble(),
                                  min: 0,
                                  max: 999,
                                  divisions: 25,
                                  label: "${(1000/(gameProvider.animationSpeed).clamp(1, 1000)).floor() } Max FPS",
                                  onChangeEnd: (value) {
                                    gameProvider.updateAnimationSpeed((1000 - value).toInt());
                                  }, onChanged: (double value) {  },
                                ),

                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(
                                      left: 15, top: 15, right: 15
                                  ),
                                  child: Text(
                                    "Border radius",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                ),
                                Slider(
                                  value: gameProvider.borderRadius,
                                  min: 0,
                                  max: 4,
                                  divisions: 4,
                                  label: "${(gameProvider.borderRadius*25).toInt().toString()}%",
                                  onChanged: (value) {
                                    gameProvider.updateBorderRadius(value);
                                  },
                                ),

                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(
                                      left: 15, top: 15, right: 15
                                  ),
                                  child: Text(
                                    "Border thickness",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                ),
                                Slider(
                                  value: gameProvider.borderThickness,
                                  min: 0,
                                  max: 5,
                                  label: "${gameProvider.borderThickness.toString()}px",
                                  divisions: 10,
                                  onChanged: (value) {
                                    gameProvider.updateBorderThickness(value);
                                  },
                                ),

                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(
                                      left: 15, top: 15, right: 15
                                  ),
                                  child: Text(
                                    "Scale",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                ),
                                Slider(
                                  value: gameProvider.scale,
                                  min: 0.5,
                                  max: 5.0,
                                  label: "${gameProvider.scale.toString()}x",
                                  divisions: 9,
                                  onChanged: (value) {
                                    gameProvider.updateScale(value);
                                  },
                                ),

                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Randomize Grid",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18
                                        ),
                                      ),
                                      Text(
                                        "Get random cells on a grid",
                                      )
                                    ],
                                  ),
                                  FilledButton(
                                      onPressed: gameProvider.randomizeGrid,
                                      child: const Text('Randomize')
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    gameProvider.isPlaying?
                                    "${(1000/(gameProvider.fpss.reduce((a,b) => a + b) / gameProvider.fpss.length)).toInt()} FPS"
                                        :"Paused",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18
                                    ),
                                  ),
                                  Text(
                                    gameProvider.isPlaying
                                        ?"Generation/Frame/Wait: ${gameProvider.frameTime}/${gameProvider.drawTime}/${gameProvider.animationSpeed} ms"
                                        : "Unpause the game to see frame times",
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),

                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }
}
class ColorCard extends StatelessWidget {
  const ColorCard({
    super.key,
    required this.label,
    required this.color,
    this.size,
  });

  final String label;
  final Color color;
  final Size? size;

  @override
  Widget build(BuildContext context) {
    const double fontSize = 14;
    const Size effectiveSize = Size(125, 50);

    return SizedBox(
      width: effectiveSize.width,
      height: effectiveSize.height,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: color,
        child: Center(
          child: InvertColors(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: fontSize,fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}