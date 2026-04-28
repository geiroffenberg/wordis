import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'word_dictionary.dart';

const int boardColumns = 7;
const int boardRows = 10;
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

  int get effectivePoints => letterPoints[letter] ?? points;

  BoardScanTile toBoardScanTile() {
    return BoardScanTile(letter: letter, points: effectivePoints);
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

class ScoreBurstEvent {
  const ScoreBurstEvent({
    required this.row,
    required this.column,
    required this.minRow,
    required this.maxRow,
    required this.minColumn,
    required this.maxColumn,
    required this.score,
    required this.maxMultiplier,
    this.badgeText,
  });

  final int row;
  final int column;
  final int minRow;
  final int maxRow;
  final int minColumn;
  final int maxColumn;
  final int score;
  final int maxMultiplier;
  final String? badgeText;
}

class _ScoredEntry {
  const _ScoredEntry({required this.label, required this.cells});

  final String label;
  final List<IndexedCell> cells;
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
  int _clearedTileCount = 0;
  int _consecutiveVowelDraws = 0;
  int _consecutiveConsonantDraws = 0;
  String _statusMessage = 'Loading dictionary...';
  String? _activeTileHint;
  List<ClearedWordSummary> _recentWords = const <ClearedWordSummary>[];
  List<TileDropAnimation> _pendingAnimations = const <TileDropAnimation>[];
  List<FlashCell> _pendingFlashCells = const <FlashCell>[];
  List<ScoreBurstEvent> _pendingScoreBursts = const <ScoreBurstEvent>[];
  bool _waitingForFlash = false;
  Set<String> _pendingClearCells = <String>{};
  Map<String, int> _multiplierCells = <String, int>{};

  /// How long a freshly-spawned tile sits at the top before starting
  /// to fall. Time-based (not tick-based) so it stays meaningful at
  /// every level: at slow speeds it's invisible, at fast speeds it's
  /// the only think-time the player gets per tile.
  static const Duration spawnGraceDuration = Duration(milliseconds: 450);

  /// Wall-clock deadline at which the active tile may begin falling.
  /// While `DateTime.now()` is before this, ticks skip the fall step
  /// (the player can still move the tile or hard-drop it).
  DateTime? _spawnGraceUntil;

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
  List<ScoreBurstEvent> get pendingScoreBursts => _pendingScoreBursts;

  @visibleForTesting
  void setActiveTileForTesting(FallingTile tile) {
    _activeTile = tile;
    _isRunning = true;
  }

  @visibleForTesting
  void lockActiveTileForTesting() {
    _lockActiveTile();
  }

  int multiplierAt(int row, int column) {
    return _multiplierCells['$row:$column'] ?? 1;
  }

  @visibleForTesting
  Future<void> initializeForTesting() async {
    _dictionary = await WordDictionary.load();
    _multiplierCells = <String, int>{};
    _isReady = true;
  }

  @visibleForTesting
  void setMultiplierForTesting(int row, int column, int multiplier) {
    _multiplierCells['$row:$column'] = multiplier;
  }

  @visibleForTesting
  void placeTileForTesting(int row, int column, LetterTile tile) {
    _board[row][column] = tile;
  }

  @visibleForTesting
  int scoreResolvedWordForTesting(ResolvedWord word) {
    return _scoreWordWithMultipliers(word);
  }

  @visibleForTesting
  WordDictionary get dictionaryForTesting => _dictionary;

  @visibleForTesting
  BoardSnapshot snapshotBoardForTesting() => _snapshotBoard();

  bool _waitingForDropAnimation = false;

  /// True while the 3-letter "junk" drop animation is playing at game
  /// start or on a level-up. Player ticks are paused during this time.
  bool _waitingForJunkDrop = false;

  /// Tiles to write into [_board] once the junk drop animation finishes.
  List<({int row, int column, String letter, int points})>
  _pendingJunkPlacements =
      const <({int row, int column, String letter, int points})>[];

  /// Highest level for which junk has already been dropped. Used to
  /// fire a junk drop exactly once per level boundary crossed.
  int _levelAtLastJunk = 0;

  /// How many junk letters fall at game start and on every level-up.
  static const int _junkTilesPerDrop = 3;

  /// Called by the UI after it has started playing the animations.
  void consumeAnimations() {
    _pendingAnimations = const <TileDropAnimation>[];
  }

  /// Called by the UI after it has started playing flash animations.
  void consumeFlashCells() {
    _pendingFlashCells = const <FlashCell>[];
  }

  /// Called by the UI after it has started score burst animations.
  void consumeScoreBursts() {
    _pendingScoreBursts = const <ScoreBurstEvent>[];
  }

  /// Called by the UI when the word-flash animation finishes.
  /// Clears the word tiles, applies gravity, and either runs another
  /// chain pass (if more words/runs formed) or spawns the next tile.
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

    // Chain reaction: scan whole board for new words / runs.
    final List<_ScoredEntry> chainEntries = _scanBoardForEntries();
    if (chainEntries.isNotEmpty) {
      _chainStep += 1;
      _awardEntriesAndStartFlash(chainEntries, isChain: true);
      return;
    }

    _chainStep = 0;
    _spawnAfterTurnOrJunk();
    notifyListeners();
  }

  /// Called by the UI when the hard-drop or junk-drop animation
  /// finishes. Routes to the right completion path based on which
  /// drop kind is in flight.
  void completePendingLock() {
    if (_waitingForJunkDrop) {
      _waitingForJunkDrop = false;
      for (final ({int row, int column, String letter, int points}) p
          in _pendingJunkPlacements) {
        _board[p.row][p.column] = LetterTile(
          letter: p.letter,
          points: p.points,
        );
      }
      _pendingJunkPlacements =
          const <({int row, int column, String letter, int points})>[];
      _spawnNextTile();
      if (!_isGameOver) {
        _statusMessage = _activeTileHint ?? 'Keep building across and down.';
      }
      _scheduleTick();
      notifyListeners();
      return;
    }
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
    _configureMultiplierCells();
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
    _clearedTileCount = 0;
    _consecutiveVowelDraws = 0;
    _consecutiveConsonantDraws = 0;
    _activeTileHint = null;
    _recentWords = const <ClearedWordSummary>[];
    _pendingFlashCells = const <FlashCell>[];
    _pendingScoreBursts = const <ScoreBurstEvent>[];
    _pendingClearCells = <String>{};
    _waitingForFlash = false;
    _waitingForDropAnimation = false;
    _isGameOver = false;
    _isRunning = true;
    _chainStep = 0;
    _spawnGraceUntil = null;
    _waitingForJunkDrop = false;
    _pendingJunkPlacements =
        const <({int row, int column, String letter, int points})>[];
    _levelAtLastJunk = 0;
    _configureMultiplierCells();
    _statusMessage = 'Build the longest word you can.';
    _spawnAfterTurnOrJunk();
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
    _spawnGraceUntil = null;
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
    if (!_isRunning || _isGameOver || _waitingForFlash || _waitingForJunkDrop) {
      return;
    }

    _tickTimer = Timer(_currentTickDuration, () {
      _tick();
      _scheduleTick();
    });
  }

  /// Difficulty curve. Each entry is a level: how many *cleared* tiles
  /// it covers (`width`) and the tick interval used while inside it
  /// (`tickMs`). Levels advance only when tiles disappear from the
  /// board, Tetris-style — stacking random letters never speeds the
  /// game up. Long words and chains advance levels faster because they
  /// clear more tiles at once.
  ///
  /// Beyond the last entry the curve enters a soft-floor mode where
  /// each additional level subtracts [_softFloorStepMs] from the tick,
  /// down to [_hardFloorMs]. Each soft-floor level covers
  /// [_softFloorWidth] cleared tiles.
  static const List<({int width, int tickMs})> _levelTable =
      <({int width, int tickMs})>[
        (width: 20, tickMs: 1000), //  L1: cleared 0-19   (deliberately slow)
        (width: 25, tickMs: 800), //   L2: 20-44          (-20%)
        (width: 30, tickMs: 640), //   L3: 45-74          (-20%)
        (width: 35, tickMs: 510), //   L4: 75-109         (-20%)
        (width: 40, tickMs: 410), //   L5: 110-149        (-20%)
        (width: 50, tickMs: 330), //   L6: 150-199        (-20%)
        (width: 60, tickMs: 270), //   L7: 200-259        (-18%)
        (width: 70, tickMs: 230), //   L8: 260-329        (-15%)
        (width: 80, tickMs: 200), //   L9: 330-409        (-13%)
      ];

  static const int _softFloorWidth = 100;
  static const int _softFloorStepMs = 5;
  static const int _hardFloorMs = 150;

  /// Resolves the current level index (0-based), the tick duration in
  /// ms for that level, and how many cleared tiles remain until the
  /// next level. Driven by [_clearedTileCount] (Tetris-style: only
  /// disappearing tiles count toward leveling).
  ({int levelIndex, int tickMs, int tilesIntoLevel, int levelWidth})
  _resolveLevel() {
    int tilesRemaining = _clearedTileCount;
    for (int i = 0; i < _levelTable.length; i += 1) {
      final ({int width, int tickMs}) entry = _levelTable[i];
      if (tilesRemaining < entry.width) {
        return (
          levelIndex: i,
          tickMs: entry.tickMs,
          tilesIntoLevel: tilesRemaining,
          levelWidth: entry.width,
        );
      }
      tilesRemaining -= entry.width;
    }
    // Soft-floor region: each [_softFloorWidth] cleared tiles past the
    // table shaves [_softFloorStepMs] off the tick, floored at
    // [_hardFloorMs].
    final int extraLevels = tilesRemaining ~/ _softFloorWidth;
    final int baseTick = _levelTable.last.tickMs;
    final int tickMs = max(
      _hardFloorMs,
      baseTick - (extraLevels + 1) * _softFloorStepMs,
    );
    return (
      levelIndex: _levelTable.length + extraLevels,
      tickMs: tickMs,
      tilesIntoLevel: tilesRemaining - extraLevels * _softFloorWidth,
      levelWidth: _softFloorWidth,
    );
  }

  /// 1-based difficulty level for UI display.
  int get currentLevel => _resolveLevel().levelIndex + 1;

  /// Total tiles cleared in this run. Mirrors Tetris's "lines cleared".
  int get clearedTileCount => _clearedTileCount;

  /// Cleared tiles still needed to reach the next level.
  int get tilesUntilNextLevel {
    final ({int levelIndex, int tickMs, int tilesIntoLevel, int levelWidth})
    info = _resolveLevel();
    return info.levelWidth - info.tilesIntoLevel;
  }

  Duration get _currentTickDuration =>
      Duration(milliseconds: _resolveLevel().tickMs);

  void _tick() {
    if (!_isRunning || _activeTile == null) {
      return;
    }

    final DateTime? graceUntil = _spawnGraceUntil;
    if (graceUntil != null && DateTime.now().isBefore(graceUntil)) {
      return;
    }
    _spawnGraceUntil = null;

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
      int bestScore = -1;
      for (final String letter in letterPoints.keys) {
        _board[lockedTile.row][lockedTile.column] = LetterTile(
          letter: letter,
          points: letterPoints[letter] ?? 1,
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
      if (bestScore <= 0) {
        bestLetter = _selectWildcardFallbackLetter(
          row: lockedTile.row,
          column: lockedTile.column,
        );
      }
      _board[lockedTile.row][lockedTile.column] = LetterTile(
        letter: bestLetter,
        points: letterPoints[bestLetter] ?? 1,
        isBlank: true,
      );
    } else {
      _board[lockedTile.row][lockedTile.column] = LetterTile(
        letter: lockedTile.letter,
        points: lockedTile.points,
      );
    }

    _activeTile = null;

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
      final List<_ScoredEntry> entries = <_ScoredEntry>[];
      for (final ResolvedWord word in resolvedWords) {
        entries.add(
          _ScoredEntry(label: word.word.toUpperCase(), cells: word.cells),
        );
      }
      for (final List<IndexedCell> run in matchingRuns) {
        entries.add(_ScoredEntry(label: _runSummaryLabel(run), cells: run));
      }

      _awardEntriesAndStartFlash(entries, isChain: false);
      return;
    }

    _recentWords = const <ClearedWordSummary>[];
    _spawnAfterTurnOrJunk();
    notifyListeners();
  }

  int _chainStep = 0;

  /// Score the given list of word/run entries and start the flash/clear
  /// animation for them. [isChain] is true when invoked by gravity-driven
  /// chain reactions (post first scoring pass).
  void _awardEntriesAndStartFlash(
    List<_ScoredEntry> entries, {
    required bool isChain,
  }) {
    final Set<String> cellsToClear = <String>{};
    final Map<String, IndexedCell> uniqueCellsByKey = <String, IndexedCell>{};
    for (final _ScoredEntry entry in entries) {
      for (final IndexedCell cell in entry.cells) {
        final String key = '${cell.row}:${cell.column}';
        cellsToClear.add(key);
        uniqueCellsByKey[key] = cell;
      }
    }
    final List<IndexedCell> uniqueCells = uniqueCellsByKey.values.toList();

    final int baseSum = uniqueCells.fold<int>(
      0,
      (int total, IndexedCell cell) => total + cell.points,
    );
    final int cellMultiplier = _maxMultiplierForCells(uniqueCells);
    final bool isDoubleWord = entries.length >= 2;
    final int finalMultiplier = isDoubleWord
        ? max(2, cellMultiplier)
        : cellMultiplier;
    final int earnedScore = baseSum * finalMultiplier;

    final List<ClearedWordSummary> summaries = <ClearedWordSummary>[];
    for (final _ScoredEntry entry in entries) {
      final int entryBase = entry.cells.fold<int>(
        0,
        (int total, IndexedCell cell) => total + cell.points,
      );
      summaries.add(ClearedWordSummary(word: entry.label, score: entryBase));
    }

    final List<ScoreBurstEvent> bursts = <ScoreBurstEvent>[];
    final String? chainPrefix = isChain && _chainStep >= 1
        ? 'CHAIN x${_chainStep + 1}'
        : null;
    if (!isDoubleWord) {
      final _ScoredEntry only = entries.single;
      String? badge = _badgeForEntry(only, finalMultiplier);
      if (chainPrefix != null) {
        badge = badge == null ? chainPrefix : '$chainPrefix • $badge';
      }
      bursts.add(
        _buildScoreBurst(
          cells: only.cells,
          score: earnedScore,
          maxMultiplier: finalMultiplier,
          badgeText: badge,
        ),
      );
    } else {
      String badge = finalMultiplier > 2
          ? 'DOUBLE WORD ${finalMultiplier}x'
          : 'DOUBLE WORD';
      if (chainPrefix != null) {
        badge = '$chainPrefix • $badge';
      }
      bursts.add(
        _buildScoreBurst(
          cells: uniqueCells,
          score: earnedScore,
          maxMultiplier: finalMultiplier,
          badgeText: badge,
        ),
      );
    }

    _relocateFourXIfClaimed(cellsToClear);

    _recentWords = summaries;
    _score += earnedScore;

    final List<String> statusParts = summaries
        .map((ClearedWordSummary w) => w.word)
        .toList();
    String statusMessage;
    if (isDoubleWord) {
      final String bonusLabel = finalMultiplier > 2
          ? 'DOUBLE WORD ${finalMultiplier}x'
          : 'DOUBLE WORD';
      statusMessage =
          '${statusParts.join(' + ')}  •  $bonusLabel +$earnedScore';
    } else if (finalMultiplier > 1) {
      statusMessage =
          '${statusParts.first}  •  ${finalMultiplier}x BONUS +$earnedScore';
    } else {
      statusMessage = '${statusParts.first} +$earnedScore';
    }
    if (chainPrefix != null) {
      statusMessage = '$chainPrefix • $statusMessage';
    }
    _statusMessage = statusMessage;

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
    _pendingScoreBursts = bursts;
    _pendingClearCells = cellsToClear;
    _clearedTileCount += cellsToClear.length;
    _waitingForFlash = true;
    notifyListeners();
  }

  /// Scans the entire board for words (any length >= [minimumWordLength])
  /// and runs of 3+ identical letters. Returns deduplicated entries.
  List<_ScoredEntry> _scanBoardForEntries() {
    final BoardSnapshot snapshot = _snapshotBoard();
    final List<_ScoredEntry> entries = <_ScoredEntry>[];

    // Word scan: longest match per (axis, start cell, length) — dedup by
    // a signature of the spanning cells.
    final Set<String> seenWordSignatures = <String>{};
    for (int row = 0; row < boardRows; row += 1) {
      for (int column = 0; column < boardColumns; column += 1) {
        if (_board[row][column] == null) {
          continue;
        }
        final List<ResolvedWord> words = _dictionary.findLongestWords(
          board: snapshot,
          row: row,
          column: column,
          minimumLength: minimumWordLength,
        );
        for (final ResolvedWord word in words) {
          final String sig =
              '${word.axis}:${word.cells.first.row}:${word.cells.first.column}:${word.cells.length}';
          if (seenWordSignatures.add(sig)) {
            entries.add(
              _ScoredEntry(label: word.word.toUpperCase(), cells: word.cells),
            );
          }
        }
      }
    }

    // Run scan: 3+ identical letters horizontally and vertically.
    final Set<String> seenRunSignatures = <String>{};
    for (int row = 0; row < boardRows; row += 1) {
      int col = 0;
      while (col < boardColumns) {
        final LetterTile? tile = _board[row][col];
        if (tile == null) {
          col += 1;
          continue;
        }
        int end = col;
        while (end + 1 < boardColumns &&
            _board[row][end + 1]?.letter == tile.letter) {
          end += 1;
        }
        if (end - col + 1 >= 3) {
          final List<IndexedCell> cells = <IndexedCell>[
            for (int c = col; c <= end; c += 1)
              IndexedCell(
                row: row,
                column: c,
                letter: _board[row][c]!.letter,
                points: _board[row][c]!.effectivePoints,
              ),
          ];
          final String sig = 'H:$row:$col:${cells.length}';
          if (seenRunSignatures.add(sig)) {
            entries.add(
              _ScoredEntry(label: _runSummaryLabel(cells), cells: cells),
            );
          }
        }
        col = end + 1;
      }
    }
    for (int column = 0; column < boardColumns; column += 1) {
      int row = 0;
      while (row < boardRows) {
        final LetterTile? tile = _board[row][column];
        if (tile == null) {
          row += 1;
          continue;
        }
        int end = row;
        while (end + 1 < boardRows &&
            _board[end + 1][column]?.letter == tile.letter) {
          end += 1;
        }
        if (end - row + 1 >= 3) {
          final List<IndexedCell> cells = <IndexedCell>[
            for (int r = row; r <= end; r += 1)
              IndexedCell(
                row: r,
                column: column,
                letter: _board[r][column]!.letter,
                points: _board[r][column]!.effectivePoints,
              ),
          ];
          final String sig = 'V:$row:$column:${cells.length}';
          if (seenRunSignatures.add(sig)) {
            entries.add(
              _ScoredEntry(label: _runSummaryLabel(cells), cells: cells),
            );
          }
        }
        row = end + 1;
      }
    }

    return entries;
  }

  /// Either drops a batch of junk tiles (if a level boundary was just
  /// crossed) or spawns the next player tile normally. Junk drops fire
  /// once per level transition and once at game start (level 1 vs the
  /// initial sentinel of 0).
  void _spawnAfterTurnOrJunk() {
    if (_isGameOver) {
      return;
    }
    final int level = currentLevel;
    if (level > _levelAtLastJunk) {
      _levelAtLastJunk = level;
      if (_dropJunkTiles(_junkTilesPerDrop)) {
        return;
      }
    }
    _spawnNextTile();
    if (!_isGameOver) {
      _statusMessage = _activeTileHint ?? 'Keep building across and down.';
    }
    _scheduleTick();
  }

  /// Drops up to [count] random "junk" letters at random columns,
  /// chosen so they never form a word or matching run on landing.
  /// Returns true if at least one junk tile was queued for animation.
  bool _dropJunkTiles(int count) {
    final List<int> available = <int>[];
    for (int c = 0; c < boardColumns; c += 1) {
      if (_board[0][c] == null) {
        available.add(c);
      }
    }
    if (available.isEmpty) {
      return false;
    }
    available.shuffle(_random);
    final int n = min(count, available.length);

    final List<({int row, int column, String letter, int points})> placements =
        <({int row, int column, String letter, int points})>[];
    final List<TileDropAnimation> anims = <TileDropAnimation>[];

    for (int i = 0; i < n; i += 1) {
      final int col = available[i];
      int row = boardRows - 1;
      while (row >= 0 && _board[row][col] != null) {
        row -= 1;
      }
      if (row < 0) {
        continue;
      }

      final String letter = _pickJunkLetter(row, col);
      final int points = letterPoints[letter] ?? 1;

      // Provisional placement so subsequent picks see this letter
      // (avoids two junk tiles together accidentally forming a word).
      _board[row][col] = LetterTile(letter: letter, points: points);
      placements.add((row: row, column: col, letter: letter, points: points));
      anims.add(
        TileDropAnimation(
          letter: letter,
          points: points,
          column: col,
          fromRow: -1,
          toRow: row,
        ),
      );
    }

    // Pull the provisional tiles back off — they'll be re-applied when
    // the animation completes via completePendingLock().
    for (final ({int row, int column, String letter, int points}) p
        in placements) {
      _board[p.row][p.column] = null;
    }

    if (placements.isEmpty) {
      return false;
    }

    _pendingJunkPlacements = placements;
    _pendingAnimations = anims;
    _waitingForJunkDrop = true;
    _tickTimer?.cancel();
    _statusMessage = 'Incoming junk!';
    notifyListeners();
    return true;
  }

  /// Picks a letter for a junk tile at (row, column) that won't form
  /// any word or matching run on landing. Falls back to 'Q' if the
  /// search is exhausted (extremely unlikely on a near-empty board).
  String _pickJunkLetter(int row, int column) {
    final List<String> candidates = letterPoints.keys.toList()
      ..shuffle(_random);
    for (final String letter in candidates) {
      _board[row][column] = LetterTile(
        letter: letter,
        points: letterPoints[letter] ?? 1,
      );
      final List<ResolvedWord> words = _dictionary.findLongestWords(
        board: _snapshotBoard(),
        row: row,
        column: column,
        minimumLength: minimumWordLength,
      );
      final List<List<IndexedCell>> runs = _findMatchingRuns(row, column);
      _board[row][column] = null;
      if (words.isEmpty && runs.isEmpty) {
        return letter;
      }
    }
    return 'Q';
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
      _activeTileHint = null;
      return;
    }

    _activeTileHint = _hintForTile(tile);

    _activeTile = FallingTile(
      letter: tile.letter,
      points: tile.points,
      row: 0,
      column: spawnColumn,
      isBlank: tile.isBlank,
    );
    _spawnGraceUntil = DateTime.now().add(spawnGraceDuration);
  }

  int _scoreWordWithMultipliers(ResolvedWord word) {
    final int baseScore = word.cells.fold<int>(
      0,
      (int total, IndexedCell cell) => total + cell.points,
    );
    final int wordMultiplier = _maxMultiplierForCells(word.cells);
    return baseScore * wordMultiplier;
  }

  int _maxMultiplierForCells(List<IndexedCell> cells) {
    int maxMultiplier = 1;
    for (final IndexedCell cell in cells) {
      maxMultiplier = max(maxMultiplier, multiplierAt(cell.row, cell.column));
    }
    return maxMultiplier;
  }

  ScoreBurstEvent _buildScoreBurst({
    required List<IndexedCell> cells,
    required int score,
    required int maxMultiplier,
    String? badgeText,
  }) {
    int minRow = cells.first.row;
    int maxRow = cells.first.row;
    int minColumn = cells.first.column;
    int maxColumn = cells.first.column;

    for (final IndexedCell cell in cells) {
      minRow = min(minRow, cell.row);
      maxRow = max(maxRow, cell.row);
      minColumn = min(minColumn, cell.column);
      maxColumn = max(maxColumn, cell.column);
    }

    return ScoreBurstEvent(
      row: _centerRowForCells(cells),
      column: _centerColumnForCells(cells),
      minRow: minRow,
      maxRow: maxRow,
      minColumn: minColumn,
      maxColumn: maxColumn,
      score: score,
      maxMultiplier: maxMultiplier,
      badgeText: badgeText,
    );
  }

  String _runSummaryLabel(List<IndexedCell> run) {
    final String letter = run.first.letter.toUpperCase();
    if (run.length == 3) {
      return 'TRIPLE $letter';
    }
    if (run.length == 4) {
      return 'QUAD $letter';
    }
    if (run.length == 5) {
      return 'PENTA $letter';
    }
    return '$letter×${run.length}';
  }

  String? _badgeForEntry(_ScoredEntry entry, int finalMultiplier) {
    final String? runBadge = entry.label.startsWith('TRIPLE ')
        ? 'TRIPLE LETTER'
        : entry.label.startsWith('QUAD ')
        ? 'QUAD LETTER'
        : entry.label.startsWith('PENTA ')
        ? 'PENTA LETTER'
        : null;
    if (runBadge != null) {
      return finalMultiplier > 1 ? '$runBadge ${finalMultiplier}x' : runBadge;
    }
    if (finalMultiplier > 1) {
      return '${finalMultiplier}x BONUS';
    }
    return null;
  }

  int _centerRowForCells(List<IndexedCell> cells) {
    final int sum = cells.fold<int>(
      0,
      (int s, IndexedCell cell) => s + cell.row,
    );
    return (sum / cells.length).round();
  }

  int _centerColumnForCells(List<IndexedCell> cells) {
    final int sum = cells.fold<int>(
      0,
      (int s, IndexedCell cell) => s + cell.column,
    );
    return (sum / cells.length).round();
  }

  void _configureMultiplierCells() {
    final Map<String, int> multipliers = <String, int>{};

    for (final Point<int> cell in _fixedDoubleWordCells) {
      multipliers['${cell.x}:${cell.y}'] = 2;
    }
    for (final Point<int> cell in _fixedTripleWordCells) {
      multipliers['${cell.x}:${cell.y}'] = 3;
    }

    final List<Point<int>> candidates = <Point<int>>[];
    for (int row = 0; row < boardRows; row += 1) {
      if (!_isFourXRowAllowed(row)) {
        continue;
      }
      for (int column = 0; column < boardColumns; column += 1) {
        if (multipliers.containsKey('$row:$column')) {
          continue;
        }
        candidates.add(Point<int>(row, column));
      }
    }

    if (candidates.isNotEmpty) {
      final Point<int> bonusCell =
          candidates[_random.nextInt(candidates.length)];
      multipliers['${bonusCell.x}:${bonusCell.y}'] = 4;
    }

    _multiplierCells = multipliers;
  }

  bool _isFourXRowAllowed(int row) {
    return row < boardRows - _noFourXBottomRows;
  }

  void _relocateFourXIfClaimed(Set<String> clearedCells) {
    bool usedFourX = false;
    for (final String cell in clearedCells) {
      if (_multiplierCells[cell] == 4) {
        usedFourX = true;
        break;
      }
    }
    if (!usedFourX) {
      return;
    }

    _multiplierCells.removeWhere((String _, int multiplier) => multiplier == 4);

    final Set<String> occupiedCells = <String>{
      for (int row = 0; row < boardRows; row += 1)
        for (int column = 0; column < boardColumns; column += 1)
          if (_board[row][column] != null) '$row:$column',
    };

    List<Point<int>> candidates = <Point<int>>[];
    for (int row = 0; row < boardRows; row += 1) {
      if (!_isFourXRowAllowed(row)) {
        continue;
      }
      for (int column = 0; column < boardColumns; column += 1) {
        final String key = '$row:$column';
        if (_multiplierCells.containsKey(key)) {
          continue;
        }
        if (clearedCells.contains(key)) {
          continue;
        }
        if (occupiedCells.contains(key)) {
          continue;
        }
        candidates.add(Point<int>(row, column));
      }
    }

    if (candidates.isEmpty) {
      for (int row = 0; row < boardRows; row += 1) {
        if (!_isFourXRowAllowed(row)) {
          continue;
        }
        for (int column = 0; column < boardColumns; column += 1) {
          final String key = '$row:$column';
          if (_multiplierCells.containsKey(key)) {
            continue;
          }
          if (clearedCells.contains(key)) {
            continue;
          }
          candidates.add(Point<int>(row, column));
        }
      }
    }

    if (candidates.isEmpty) {
      return;
    }

    final Point<int> nextCell = candidates[_random.nextInt(candidates.length)];
    _multiplierCells['${nextCell.x}:${nextCell.y}'] = 4;
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
            points: _board[row][c]!.effectivePoints,
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
            points: _board[r][column]!.effectivePoints,
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

    final int vowelsOnBoard = boardCounts.entries.fold<int>(
      0,
      (int total, MapEntry<String, int> entry) =>
          total + (_vowels.contains(entry.key) ? entry.value : 0),
    );
    final int consonantsOnBoard = boardCounts.entries.fold<int>(
      0,
      (int total, MapEntry<String, int> entry) =>
          total + (_vowels.contains(entry.key) ? 0 : entry.value),
    );

    // Ask the dictionary which letters can still form words.
    final Set<String> useful = _dictionary.usefulLetters(boardLettersLower);

    final bool strategicMode = _occupiedCellCount() >= _strategicModeMinTiles;
    final Set<String> strategicLetters = strategicMode
        ? _lettersThatCanMakeImmediateWord()
        : const <String>{};

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

      // Avoid long streaks of vowels or consonants in generated draws.
      if (_consecutiveVowelDraws >= _maxConsecutiveVowels &&
          _vowels.contains(entry.key)) {
        weight = 0;
      }
      if (_consecutiveConsonantDraws >= _maxConsecutiveConsonants &&
          !_vowels.contains(entry.key)) {
        weight = 0;
      }

      // Keep board letter mix healthy by nudging toward balance.
      if (_vowels.contains(entry.key) &&
          vowelsOnBoard > consonantsOnBoard + 3) {
        weight = max(1, weight ~/ 3);
      }
      if (!_vowels.contains(entry.key) &&
          consonantsOnBoard > vowelsOnBoard + 5) {
        weight = max(1, weight ~/ 2);
      }

      // In strategic mode, prefer letters that can immediately complete
      // at least one 3+ letter word somewhere on the board.
      if (strategicMode &&
          strategicLetters.isNotEmpty &&
          !strategicLetters.contains(entry.key)) {
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
        _registerDrawLetter(entry.key);
        return LetterTile(letter: entry.key, points: letterPoints[entry.key]!);
      }
    }

    _registerDrawLetter('E');
    return const LetterTile(letter: 'E', points: 1);
  }

  void _registerDrawLetter(String letter) {
    if (_vowels.contains(letter)) {
      _consecutiveVowelDraws += 1;
      _consecutiveConsonantDraws = 0;
    } else {
      _consecutiveConsonantDraws += 1;
      _consecutiveVowelDraws = 0;
    }
  }

  int _occupiedCellCount() {
    int count = 0;
    for (final List<LetterTile?> row in _board) {
      for (final LetterTile? tile in row) {
        if (tile != null) {
          count += 1;
        }
      }
    }
    return count;
  }

  Set<String> _lettersThatCanMakeImmediateWord() {
    final Set<String> candidates = <String>{};
    for (final String letter in letterPoints.keys) {
      if (_canLetterMakeImmediateWord(letter)) {
        candidates.add(letter);
      }
    }
    return candidates;
  }

  bool _canLetterMakeImmediateWord(String letter) {
    return _bestImmediateWordForLetter(letter) != null;
  }

  ResolvedWord? _bestImmediateWordForLetter(String letter) {
    final int points = letterPoints[letter] ?? 1;
    ResolvedWord? bestWord;

    for (int column = 0; column < boardColumns; column += 1) {
      int? landingRow;
      for (int row = boardRows - 1; row >= 0; row -= 1) {
        if (_board[row][column] == null) {
          landingRow = row;
          break;
        }
      }
      if (landingRow == null) {
        continue;
      }

      _board[landingRow][column] = LetterTile(letter: letter, points: points);
      final List<ResolvedWord> words = _dictionary.findLongestWords(
        board: _snapshotBoard(),
        row: landingRow,
        column: column,
        minimumLength: minimumWordLength,
      );
      _board[landingRow][column] = null;

      for (final ResolvedWord word in words) {
        if (bestWord == null ||
            word.word.length > bestWord.word.length ||
            (word.word.length == bestWord.word.length &&
                _scoreWordWithMultipliers(word) >
                    _scoreWordWithMultipliers(bestWord))) {
          bestWord = word;
        }
      }
    }

    return bestWord;
  }

  String? _hintForTile(LetterTile tile) {
    if (tile.isBlank || _occupiedCellCount() < _strategicModeMinTiles) {
      return null;
    }

    final ResolvedWord? hintWord = _bestImmediateWordForLetter(tile.letter);
    if (hintWord != null) {
      return 'Hint: ${hintWord.word.toUpperCase()}';
    }

    return null;
  }

  String _selectWildcardFallbackLetter({
    required int row,
    required int column,
  }) {
    final Map<String, int> boardCounts = <String, int>{};
    for (final List<LetterTile?> boardRow in _board) {
      for (final LetterTile? tile in boardRow) {
        if (tile != null) {
          boardCounts[tile.letter] = (boardCounts[tile.letter] ?? 0) + 1;
        }
      }
    }

    final Set<String> boardLettersLower = boardCounts.keys
        .map((String letter) => letter.toLowerCase())
        .toSet();
    final Set<String> usefulLetters = _dictionary.usefulLetters(
      boardLettersLower,
    );
    final Iterable<String> candidates = usefulLetters.isNotEmpty
        ? usefulLetters
        : letterPoints.keys;

    final int vowelsOnBoard = boardCounts.entries.fold<int>(
      0,
      (int total, MapEntry<String, int> entry) =>
          total + (_vowels.contains(entry.key) ? entry.value : 0),
    );
    final int consonantsOnBoard = boardCounts.entries.fold<int>(
      0,
      (int total, MapEntry<String, int> entry) =>
          total + (_vowels.contains(entry.key) ? 0 : entry.value),
    );

    String bestLetter = 'E';
    double bestHeuristic = -double.infinity;
    for (final String letter in candidates) {
      final int frequency = _letterFrequencies[letter] ?? 1;
      double heuristic = sqrt(frequency.toDouble());

      if (_vowels.contains(letter)) {
        heuristic += (vowelsOnBoard <= consonantsOnBoard) ? 1.0 : -2.0;
      } else {
        heuristic += (consonantsOnBoard <= vowelsOnBoard + 1) ? 1.2 : -1.6;
      }

      heuristic += _neighborHeuristic(letter: letter, row: row, column: column);

      // Small jitter avoids repetitive ties while keeping choices stable.
      heuristic += _random.nextDouble() * 0.15;

      if (heuristic > bestHeuristic) {
        bestHeuristic = heuristic;
        bestLetter = letter;
      }
    }

    return bestLetter;
  }

  double _neighborHeuristic({
    required String letter,
    required int row,
    required int column,
  }) {
    double score = 0;
    for (final (int dr, int dc) in _orthogonalDirections) {
      final int r = row + dr;
      final int c = column + dc;
      if (r < 0 || r >= boardRows || c < 0 || c >= boardColumns) {
        continue;
      }
      final LetterTile? neighbor = _board[r][c];
      if (neighbor == null) {
        continue;
      }

      if (neighbor.letter == letter) {
        score += 2.2;
      } else {
        final bool isVowel = _vowels.contains(letter);
        final bool neighborIsVowel = _vowels.contains(neighbor.letter);
        score += (isVowel != neighborIsVowel) ? 1.1 : 0.35;
      }
    }
    return score;
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
const int _noFourXBottomRows = 4;
const int _strategicModeMinTiles = 10;
const int _maxConsecutiveVowels = 3;
const int _maxConsecutiveConsonants = 5;

const Set<String> _vowels = <String>{'A', 'E', 'I', 'O', 'U'};
const List<(int, int)> _orthogonalDirections = <(int, int)>[
  (-1, 0),
  (1, 0),
  (0, -1),
  (0, 1),
];

// Rows are defined from the bottom of the board:
// row 1 = bottom row, row 10 = top row.
const int _row4FromBottom = boardRows - 4;
const int _row7FromBottom = boardRows - 7;

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

const List<Point<int>> _fixedDoubleWordCells = <Point<int>>[
  Point<int>(_row4FromBottom, 1),
  Point<int>(_row4FromBottom, 5),
];

const List<Point<int>> _fixedTripleWordCells = <Point<int>>[
  Point<int>(_row7FromBottom, 0),
  Point<int>(_row7FromBottom, 6),
];
