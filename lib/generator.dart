import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'package:flutter/material.dart';

class GameOfLifeProvider with ChangeNotifier {
  List<List<bool>> grid = [];
  bool isPlaying = false;
  bool useSystemColors = true;
  int rows = 50;
  int cols = 50;
  int animationSpeed = 100; // milliseconds
  double scale = 1.0;
  Color liveColor = Colors.green;
  Color deadColor = Colors.black;
  double borderRadius = 0.0;
  double borderThickness = 0.0;
  int frameTime = 0;
  int drawTime = 0;
  List fpss = [];

  Timer? _timer;

  GameOfLifeProvider() {
    randomizeGrid();
  }

  void updateGridSize(int newRows, int newCols) {
    if (newRows != rows || newCols != cols) {
      rows = newRows;
      cols = newCols;
      randomizeGrid();
    }
  }

  void updateAnimationSpeed(int newSpeed) {
    animationSpeed = newSpeed;
    if (isPlaying) {
      startGameOfLife();
    }
    notifyListeners();
  }

  void updateScale(double newScale) {
    scale = newScale;
    final newRows = (50 * (1 / scale)).floor();
    final newCols = (50 * (1 / scale)).floor();
    updateGridSize(newRows, newCols);
    notifyListeners();
  }

  void updateLiveColor(Color newColor) {
    liveColor = newColor;
    notifyListeners();
  }

  void updateDeadColor(Color newColor) {
    deadColor = newColor;
    notifyListeners();
  }

  void updateBorderRadius(double newRadius) {
    borderRadius = newRadius;
    notifyListeners();
  }

  void updateBorderThickness(double newThickness) {
    borderThickness = newThickness;
    notifyListeners();
  }

  void toggleCell(int row, int col) {
    if (row >= 0 && row < rows && col >= 0 && col < cols) {
      grid[row][col] = !grid[row][col];
      notifyListeners();
    }
  }

  void randomizeGrid() {
    final random = Random();
    grid = List.generate(
      rows,
          (_) => List.generate(
        cols,
            (_) => random.nextBool(),
      ),
    );
    notifyListeners();
  }

  void startGameOfLife() {
    stopGameOfLife();
    isPlaying = true;
    _timer = Timer.periodic(Duration(milliseconds: animationSpeed), (timer) {
      final stopwatch = Stopwatch()..start();
      updateGameOfLife();
      stopwatch.stop();
      frameTime = stopwatch.elapsedMilliseconds;
      notifyListeners();
    });
  }

  void stopGameOfLife() {
    _timer?.cancel();
    isPlaying = false;
    notifyListeners();
  }

  void updateGameOfLife() {
    List<List<bool>> newGrid = List.generate(
      rows,
          (y) => List.generate(
        cols,
            (x) => _calculateNextState(y, x),
      ),
    );
    grid = newGrid;
    notifyListeners();
  }

  bool _calculateNextState(int y, int x) {
    int liveNeighbors = 0;
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        if (i == 0 && j == 0) continue;
        int newY = y + i;
        int newX = x + j;
        if (newY >= 0 && newY < rows && newX >= 0 && newX < cols && grid[newY][newX]) {
          liveNeighbors++;
        }
      }
    }
    if (grid[y][x]) {
      return liveNeighbors == 2 || liveNeighbors == 3;
    } else {
      return liveNeighbors == 3;
    }
  }
}
