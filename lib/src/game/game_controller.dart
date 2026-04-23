import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'word_dictionary.dart';

const int boardColumns = 7;
const int boardRows = 14;
const int minimumWordLength = 3;
const String highScoreKey = 'wordis_high_score';

class LetterTile {
  const LetterTile({
    required this.letter,
    required this.points,
    this.isBlank = false,
  });

  final String letter;
  final int points;
  final bool isBlank;

  BoardScanTile toBoardScanTile() {
    return BoardScanTile(letter: letter, points: points);
  }
}

class FallingTile extends LetterTile {
  const FallingTile({
    required super.letter,
    required super.points,
    required this.row,
    required this.column,
    super.isBlank,
  });

  final int row;
  final int column;

  FallingTile copyWith({int? row, int? column}) {
    return FallingTile(
      letter: letter,
      points: points,
      row: row ?? this.row,
      column: column ?? this.column,
      isBlank: isBlank,
    );
  }
}

class ClearedWordSummary {
  const ClearedWordSummary({required this.word, required this.score});

  final String word;
  final int score;
}

/// Describes a tile that should animate from one row to another.
class TileDropAnimation {
  const TileDropAnimation({
    required this.letter,
    required this.points,
    required this.column,
    required this.fromRow,
    required this.toRow,
    this.isBlank = false,
  });

  final String letter;
  final int points;
  final int column;
  final int fromRow;
  final int toRow;
  final bool isBlank;

  int get distance => toRow - fromRow;
}

/// A cell that should briefly flash when a word is cleared.
class FlashCell {
  const FlashCell({required this.row, required this.column});

  final int row;
  final int column;
}

class GameController extends ChangeNotifier {
  GameController({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<List<LetterTile?>> _board = List<List<LetterTile?>>.generate(
    boardRows,
    (_) => List<LetterTile?>.filled(boardColumns, null),
  );

  late WordDictionary _dictionary;
  SharedPreferences? _preferences;
  Timer? _tickTimer;

  FallingTile? _activeTile;
  LetterTile? _nextTile;
  bool _isReady = false;
  bool _isRunning = false;
  bool _isGameOver = false;
  int _score = 0;
  int _highScore = 0;
  int _lockedTileCount = 0;
  String _statusMessage = 'Loading dictionary...';
  List<ClearedWordSummary> _recentWords = const <ClearedWordSummary>[];
  List<TileDropAnimation> _pendingAnimations = const <TileDropAnimation>[];
  List<FlashCell> _pendingFlashCells = const <FlashCell>[];
  bool _waitingForFlash = false;
  Set<String> _pendingClearCells = <String>{};

  bool get isReady => _isReady;
  bool get isRunning => _isRunning;
  bool get isGameOver => _isGameOver;
  int get score => _score;
  int get highScore => _highScore;
  int get tickMilliseconds => _currentTickDuration.inMilliseconds;
  String get statusMessage => _statusMessage;
  FallingTile? get activeTile => _activeTile;
  LetterTile? get nextTile => _nextTile;
  List<ClearedWordSummary> get recentWords => _recentWords;
  List<List<LetterTile?>> get board => _board;
  List<TileDropAnimation> get pendingAnimations => _pendingAnimations;
  List<FlashCell> get pendingFlashCells => _pendingFlashCells;

  bool _waitingForDropAnimation = false;

  /// Called by the UI after it has started playing the animations.
  void consumeAnimations() {
    _pendingAnimations = const <TileDropAnimation>[];
  }

  /// Called by the UI after it has started playing flash animations.
  void consumeFlashCells() {
    _pendingFlashCells = const <FlashCell>[];
  }

  /// Called by the UI when the word-flash animation finishes.
  /// Clears the word tiles, applies gravity, and spawns the next tile.
  void completeFlashPhase() {
    if (!_waitingForFlash) {
      return;
    }
    _waitingForFlash = false;
    for (final String cell in _pendingClearCells) {
      final List<String> parts = cell.split(':');
      _board[int.parse(parts[0])][int.parse(parts[1])] = null;
    }
    _pendingClearCells = <String>{};
    _applyGravity();
    _spawnNextTile();
    _scheduleTick();
    notifyListeners();
  }

  /// Called by the UI when the hard-drop animation finishes.
  /// Completes the lock, word check, gravity, and spawns next tile.
  void completePendingLock() {
    if (!_waitingForDropAnimation) {
      return;
    }
    _waitingForDropAnimation = false;
    _lockActiveTile();
    if (!_waitingForFlash) {
      _scheduleTick();
    }
  }

  Future<void> initialize() async {
    _dictionary = await WordDictionary.load();
    _preferences = await SharedPreferences.getInstance();
    _highScore = _preferences?.getInt(highScoreKey) ?? 0;
    _isReady = true;
    _statusMessage = 'Ready';
    notifyListeners();
  }

  void startNewGame() {
    _tickTimer?.cancel();
    for (final List<LetterTile?> row in _board) {
      row.fillRange(0, row.length, null);
    }
    _score = 0;
    _lockedTileCount = 0;
    _recentWords = const <ClearedWordSummary>[];
    _pendingFlashCells = const <FlashCell>[];
    _pendingClearCells = <String>{};
    _waitingForFlash = false;
    _waitingForDropAnimation = false;
    _isGameOver = false;
    _isRunning = true;
    _statusMessage = 'Build the longest word you can.';
    _spawnNextTile();
    _scheduleTick();
    notifyListeners();
  }

  void togglePause() {
    if (!_isReady || _isGameOver) {
      return;
    }

    _isRunning = !_isRunning;
    if (_isRunning) {
      _statusMessage = 'Back in play.';
      _scheduleTick();
    } else {
      _tickTimer?.cancel();
      _statusMessage = 'Paused';
    }
    notifyListeners();
  }

  void moveLeft() {
    _moveActiveTileBy(columnDelta: -1);
  }

  void moveRight() {
    _moveActiveTileBy(columnDelta: 1);
  }

  void hardDrop() {
    if (!_isRunning || _activeTile == null) {
      return;
    }
    final int startRow = _activeTile!.row;
    while (_activeTile != null &&
        _canOccupy(_activeTile!.row + 1, _activeTile!.column)) {
      _activeTile = _activeTile!.copyWith(row: _activeTile!.row + 1);
    }
    final int endRow = _activeTile!.row;
    if (endRow > startRow + 1) {
      // Animate first, lock later when the UI calls completePendingLock().
      _tickTimer?.cancel();
      _waitingForDropAnimation = true;
      _pendingAnimations = <TileDropAnimation>[
        TileDropAnimation(
          letter: _activeTile!.letter,
          points: _activeTile!.points,
          column: _activeTile!.column,
          fromRow: startRow,
          toRow: endRow,
          isBlank: _activeTile!.isBlank,
        ),
      ];
      notifyListeners();
      return;
    }
    _lockActiveTile();
  }

  void disposeController() {
    _tickTimer?.cancel();
  }

  void _scheduleTick() {
    _tickTimer?.cancel();
    if (!_isRunning || _isGameOver || _waitingForFlash) {
      return;
    }

    _tickTimer = Timer(_currentTickDuration, () {
      _tick();
      _scheduleTick();
    });
  }

  Duration get _currentTickDuration {
    final int milliseconds = max(220, 900 - (_lockedTileCount * 12));
    return Duration(milliseconds: milliseconds);
  }

  void _tick() {
    if (!_isRunning || _activeTile == null) {
      return;
    }

    final FallingTile currentTile = _activeTile!;
    final int nextRow = currentTile.row + 1;
    if (_canOccupy(nextRow, currentTile.column)) {
      _activeTile = currentTile.copyWith(row: nextRow);
      notifyListeners();
      return;
    }

    _lockActiveTile();
  }

  void _moveActiveTileBy({required int columnDelta}) {
    if (!_isRunning || _activeTile == null) {
      return;
    }

    final FallingTile currentTile = _activeTile!;
    final int nextColumn = currentTile.column + columnDelta;
    if (!_canOccupy(currentTile.row, nextColumn)) {
      return;
    }

    _activeTile = currentTile.copyWith(column: nextColumn);
    notifyListeners();
  }

  bool _canOccupy(int row, int column) {
    if (row < 0 || row >= boardRows) {
      return false;
    }
    if (column < 0 || column >= boardColumns) {
      return false;
    }
    return _board[row][column] == null;
  }

  void _lockActiveTile() {
    final FallingTile lockedTile = _activeTile!;

    if (lockedTile.isBlank) {
      // Try all 26 letters, pick the one forming the highest-scoring word.
      String bestLetter = 'E';
      int bestScore = 0;
      for (final String letter in letterPoints.keys) {
        _board[lockedTile.row][lockedTile.column] = LetterTile(
          letter: letter,
          points: 0,
          isBlank: true,
        );
        final List<ResolvedWord> candidates = _dictionary.findLongestWords(
          board: _snapshotBoard(),
          row: lockedTile.row,
          column: lockedTile.column,
          minimumLength: minimumWordLength,
        );
        final int totalScore = candidates.fold<int>(
          0,
          (int s, ResolvedWord w) => s + w.score,
        );
        if (totalScore > bestScore) {
          bestScore = totalScore;
          bestLetter = letter;
        }
      }
      _board[lockedTile.row][lockedTile.column] = LetterTile(
        letter: bestLetter,
        points: 0,
        isBlank: true,
      );
    } else {
      _board[lockedTile.row][lockedTile.column] = LetterTile(
        letter: lockedTile.letter,
        points: lockedTile.points,
      );
    }

    _activeTile = null;
    _lockedTileCount += 1;

    final List<ResolvedWord> resolvedWords = _dictionary.findLongestWords(
      board: _snapshotBoard(),
      row: lockedTile.row,
      column: lockedTile.column,
      minimumLength: minimumWordLength,
    );

    final List<List<IndexedCell>> matchingRuns = _findMatchingRuns(
      lockedTile.row,
      lockedTile.column,
    );

    final bool hasWords = resolvedWords.isNotEmpty;
    final bool hasMatches = matchingRuns.isNotEmpty;

    if (hasWords || hasMatches) {
      final List<ClearedWordSummary> summaries = <ClearedWordSummary>[];
      int earnedScore = 0;
      final Set<String> cellsToClear = <String>{};

      if (hasWords) {
        for (final ResolvedWord word in resolvedWords) {
          summaries.add(
            ClearedWordSummary(
              word: word.word.toUpperCase(),
              score: word.score,
            ),
          );
          earnedScore += word.score;
          for (final IndexedCell cell in word.cells) {
            cellsToClear.add('${cell.row}:${cell.column}');
          }
        }
      }

      if (hasMatches) {
        for (final List<IndexedCell> run in matchingRuns) {
          int runPoints = 0;
          for (final IndexedCell cell in run) {
            cellsToClear.add('${cell.row}:${cell.column}');
            runPoints += cell.points;
          }
          final int halfScore = max(1, runPoints ~/ 2);
          summaries.add(
            ClearedWordSummary(
              word: '${run.first.letter.toUpperCase()}×${run.length}',
              score: halfScore,
            ),
          );
          earnedScore += halfScore;
        }
      }

      _recentWords = summaries;
      _score += earnedScore;
      _statusMessage = _recentWords
          .map((ClearedWordSummary word) => '${word.word} +${word.score}')
          .join('  •  ');

      if (_score > _highScore) {
        _highScore = _score;
        unawaited(_preferences?.setInt(highScoreKey, _highScore));
      }

      _pendingFlashCells = <FlashCell>[
        for (final String cell in cellsToClear)
          FlashCell(
            row: int.parse(cell.split(':')[0]),
            column: int.parse(cell.split(':')[1]),
          ),
      ];
      _pendingClearCells = cellsToClear;
      _waitingForFlash = true;
      notifyListeners();
      return;
    }

    _recentWords = const <ClearedWordSummary>[];
    _statusMessage = 'Keep building across and down.';
    _spawnNextTile();
    notifyListeners();
  }

  void _spawnNextTile() {
    final LetterTile tile = _nextTile ?? _drawLetterTile();
    _nextTile = _drawLetterTile();
    const int spawnColumn = boardColumns ~/ 2;
    if (!_canOccupy(0, spawnColumn)) {
      _isGameOver = true;
      _isRunning = false;
      _statusMessage = 'Board full. Tap New Run to go again.';
      _tickTimer?.cancel();
      _nextTile = null;
      return;
    }

    _activeTile = FallingTile(
      letter: tile.letter,
      points: tile.points,
      row: 0,
      column: spawnColumn,
      isBlank: tile.isBlank,
    );
  }

  BoardSnapshot _snapshotBoard() {
    return List<List<BoardScanTile?>>.generate(
      boardRows,
      (int rowIndex) => List<BoardScanTile?>.generate(
        boardColumns,
        (int columnIndex) => _board[rowIndex][columnIndex]?.toBoardScanTile(),
      ),
    );
  }

  /// Finds runs of 3+ identical letters passing through [row],[column].
  List<List<IndexedCell>> _findMatchingRuns(int row, int column) {
    final LetterTile? tile = _board[row][column];
    if (tile == null) {
      return const <List<IndexedCell>>[];
    }
    final String letter = tile.letter;
    final List<List<IndexedCell>> runs = <List<IndexedCell>>[];

    // Horizontal scan.
    int startCol = column;
    while (startCol > 0 && _board[row][startCol - 1]?.letter == letter) {
      startCol -= 1;
    }
    int endCol = column;
    while (endCol < boardColumns - 1 &&
        _board[row][endCol + 1]?.letter == letter) {
      endCol += 1;
    }
    if (endCol - startCol + 1 >= 3) {
      runs.add(<IndexedCell>[
        for (int c = startCol; c <= endCol; c += 1)
          IndexedCell(
            row: row,
            column: c,
            letter: _board[row][c]!.letter,
            points: _board[row][c]!.points,
          ),
      ]);
    }

    // Vertical scan.
    int startRow = row;
    while (startRow > 0 && _board[startRow - 1][column]?.letter == letter) {
      startRow -= 1;
    }
    int endRow = row;
    while (endRow < boardRows - 1 &&
        _board[endRow + 1][column]?.letter == letter) {
      endRow += 1;
    }
    if (endRow - startRow + 1 >= 3) {
      runs.add(<IndexedCell>[
        for (int r = startRow; r <= endRow; r += 1)
          IndexedCell(
            row: r,
            column: column,
            letter: _board[r][column]!.letter,
            points: _board[r][column]!.points,
          ),
      ]);
    }

    return runs;
  }

  void _applyGravity() {
    final List<TileDropAnimation> gravityAnimations = <TileDropAnimation>[];

    for (int column = 0; column < boardColumns; column += 1) {
      int writeRow = boardRows - 1;
      for (int row = boardRows - 1; row >= 0; row -= 1) {
        final LetterTile? tile = _board[row][column];
        if (tile == null) {
          continue;
        }
        _board[row][column] = null;
        _board[writeRow][column] = tile;
        if (writeRow != row) {
          gravityAnimations.add(
            TileDropAnimation(
              letter: tile.letter,
              points: tile.points,
              column: column,
              fromRow: row,
              toRow: writeRow,
              isBlank: tile.isBlank,
            ),
          );
        }
        writeRow -= 1;
      }
      for (; writeRow >= 0; writeRow -= 1) {
        _board[writeRow][column] = null;
      }
    }

    if (gravityAnimations.isNotEmpty) {
      _pendingAnimations = <TileDropAnimation>[
        ..._pendingAnimations,
        ...gravityAnimations,
      ];
    }
  }

  LetterTile _drawLetterTile() {
    // Small chance of spawning a blank tile.
    if (_random.nextDouble() < 0.03) {
      return const LetterTile(letter: '★', points: 0, isBlank: true);
    }

    // Collect letters currently on the board.
    final Map<String, int> boardCounts = <String, int>{};
    for (final List<LetterTile?> row in _board) {
      for (final LetterTile? tile in row) {
        if (tile != null) {
          boardCounts[tile.letter] = (boardCounts[tile.letter] ?? 0) + 1;
        }
      }
    }

    final Set<String> boardLettersLower = boardCounts.keys
        .map((String letter) => letter.toLowerCase())
        .toSet();

    // Ask the dictionary which letters can still form words.
    final Set<String> useful = _dictionary.usefulLetters(boardLettersLower);

    // Build adjusted weights: base frequency minus board presence,
    // floored at 1 for useful letters, 0 for non-useful ones.
    final Map<String, int> adjustedWeights = <String, int>{};
    int totalWeight = 0;
    for (final MapEntry<String, int> entry in _letterFrequencies.entries) {
      final int onBoard = boardCounts[entry.key] ?? 0;
      final int maxForLetter = _letterMaxOnBoard[entry.key] ?? 2;
      int weight = entry.value;

      // Reduce weight as copies pile up; zero out past the cap.
      if (onBoard >= maxForLetter) {
        weight = 0;
      } else {
        weight = max(1, weight - onBoard * 2);
      }

      // If this letter can't contribute to any word, skip it.
      if (!useful.contains(entry.key) && boardLettersLower.isNotEmpty) {
        weight = 0;
      }

      adjustedWeights[entry.key] = weight;
      totalWeight += weight;
    }

    // Fallback: if every letter was zeroed out, use base frequencies.
    if (totalWeight == 0) {
      totalWeight = _baseBagSize;
      for (final MapEntry<String, int> entry in _letterFrequencies.entries) {
        adjustedWeights[entry.key] = entry.value;
      }
    }

    final int roll = _random.nextInt(totalWeight);
    int runningWeight = 0;
    for (final MapEntry<String, int> entry in adjustedWeights.entries) {
      runningWeight += entry.value;
      if (roll < runningWeight) {
        return LetterTile(letter: entry.key, points: letterPoints[entry.key]!);
      }
    }

    return const LetterTile(letter: 'E', points: 1);
  }
}

const Map<String, int> letterPoints = <String, int>{
  'A': 1,
  'B': 3,
  'C': 3,
  'D': 2,
  'E': 1,
  'F': 4,
  'G': 2,
  'H': 4,
  'I': 1,
  'J': 8,
  'K': 5,
  'L': 1,
  'M': 3,
  'N': 1,
  'O': 1,
  'P': 3,
  'Q': 10,
  'R': 1,
  'S': 1,
  'T': 1,
  'U': 1,
  'V': 4,
  'W': 4,
  'X': 8,
  'Y': 4,
  'Z': 10,
};

const Map<String, int> _letterFrequencies = <String, int>{
  'A': 9,
  'B': 2,
  'C': 2,
  'D': 4,
  'E': 12,
  'F': 2,
  'G': 3,
  'H': 2,
  'I': 9,
  'J': 1,
  'K': 1,
  'L': 4,
  'M': 2,
  'N': 6,
  'O': 8,
  'P': 2,
  'Q': 1,
  'R': 6,
  'S': 4,
  'T': 6,
  'U': 4,
  'V': 2,
  'W': 2,
  'X': 1,
  'Y': 2,
  'Z': 1,
};

const int _baseBagSize = 98;

/// Maximum copies of a letter allowed on the board before its spawn
/// weight drops to zero. Common letters get a higher cap.
const Map<String, int> _letterMaxOnBoard = <String, int>{
  'A': 6,
  'B': 2,
  'C': 2,
  'D': 3,
  'E': 7,
  'F': 2,
  'G': 2,
  'H': 2,
  'I': 6,
  'J': 1,
  'K': 1,
  'L': 3,
  'M': 2,
  'N': 4,
  'O': 5,
  'P': 2,
  'Q': 1,
  'R': 4,
  'S': 3,
  'T': 4,
  'U': 3,
  'V': 2,
  'W': 2,
  'X': 1,
  'Y': 2,
  'Z': 1,
};
