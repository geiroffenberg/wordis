import 'dart:convert';

import 'package:flutter/services.dart';

enum WordAxis { horizontal, vertical }

class WordDictionary {
  WordDictionary._(this._wordsByLength);

  static const String assetPath = 'assets/enable1_2_to_7_by_length.json';

  final Map<int, Set<String>> _wordsByLength;

  static Future<WordDictionary> load() async {
    final String rawJson = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> parsedJson =
        jsonDecode(rawJson) as Map<String, dynamic>;
    final Map<int, Set<String>> wordsByLength = <int, Set<String>>{};

    for (final MapEntry<String, dynamic> entry in parsedJson.entries) {
      wordsByLength[int.parse(entry.key)] = (entry.value as List<dynamic>)
          .cast<String>()
          .map((String word) => word.toLowerCase())
          .toSet();
    }

    return WordDictionary._(wordsByLength);
  }

  bool contains(String word) {
    final String normalizedWord = word.toLowerCase();
    return _wordsByLength[normalizedWord.length]?.contains(normalizedWord) ??
        false;
  }

  /// Returns the set of letters that could eventually form a word given
  /// the letters already on the board. Checks whether any dictionary word
  /// contains at least one board letter plus the candidate letter.
  Set<String> usefulLetters(Set<String> boardLetters) {
    final Set<String> useful = <String>{};
    for (final Set<String> words in _wordsByLength.values) {
      for (final String word in words) {
        bool hasBoardLetter = false;
        for (int i = 0; i < word.length; i++) {
          if (boardLetters.contains(word[i])) {
            hasBoardLetter = true;
            break;
          }
        }
        if (!hasBoardLetter && boardLetters.isNotEmpty) {
          continue;
        }
        for (int i = 0; i < word.length; i++) {
          useful.add(word[i].toUpperCase());
        }
        if (useful.length == 26) {
          return useful;
        }
      }
    }
    return useful;
  }
}

class IndexedCell {
  const IndexedCell({
    required this.row,
    required this.column,
    required this.letter,
    required this.points,
  });

  final int row;
  final int column;
  final String letter;
  final int points;
}

class ResolvedWord {
  const ResolvedWord({
    required this.axis,
    required this.word,
    required this.cells,
  });

  final WordAxis axis;
  final String word;
  final List<IndexedCell> cells;

  int get score =>
      cells.fold<int>(0, (int total, IndexedCell cell) => total + cell.points);
}

class BoardScanTile {
  const BoardScanTile({required this.letter, required this.points});

  final String letter;
  final int points;
}

typedef BoardSnapshot = List<List<BoardScanTile?>>;

extension WordSearch on WordDictionary {
  List<ResolvedWord> findLongestWords({
    required BoardSnapshot board,
    required int row,
    required int column,
    int minimumLength = 3,
  }) {
    final List<ResolvedWord> resolvedWords = <ResolvedWord>[];

    final ResolvedWord? horizontalWord = _findLongestWordOnAxis(
      board: board,
      row: row,
      column: column,
      axis: WordAxis.horizontal,
      minimumLength: minimumLength,
    );
    if (horizontalWord != null) {
      resolvedWords.add(horizontalWord);
    }

    final ResolvedWord? verticalWord = _findLongestWordOnAxis(
      board: board,
      row: row,
      column: column,
      axis: WordAxis.vertical,
      minimumLength: minimumLength,
    );
    if (verticalWord != null) {
      resolvedWords.add(verticalWord);
    }

    return resolvedWords;
  }

  ResolvedWord? _findLongestWordOnAxis({
    required BoardSnapshot board,
    required int row,
    required int column,
    required WordAxis axis,
    required int minimumLength,
  }) {
    final List<IndexedCell> line = _extractLine(
      board: board,
      row: row,
      column: column,
      axis: axis,
    );
    if (line.length < minimumLength) {
      return null;
    }

    final int anchorIndex = line.indexWhere(
      (IndexedCell cell) => cell.row == row && cell.column == column,
    );
    if (anchorIndex == -1) {
      return null;
    }

    ResolvedWord? bestMatch;

    for (int startIndex = 0; startIndex <= anchorIndex; startIndex += 1) {
      for (
        int endIndex = line.length - 1;
        endIndex >= anchorIndex;
        endIndex -= 1
      ) {
        final int spanLength = endIndex - startIndex + 1;
        if (spanLength < minimumLength || spanLength > 7) {
          continue;
        }

        final List<IndexedCell> candidateCells = line.sublist(
          startIndex,
          endIndex + 1,
        );
        final String candidateWord = candidateCells
            .map((IndexedCell cell) => cell.letter)
            .join();

        if (!contains(candidateWord)) {
          continue;
        }

        final ResolvedWord candidate = ResolvedWord(
          axis: axis,
          word: candidateWord,
          cells: candidateCells,
        );

        if (bestMatch == null ||
            candidate.word.length > bestMatch.word.length) {
          bestMatch = candidate;
          continue;
        }

        if (candidate.word.length == bestMatch.word.length &&
            candidate.score > bestMatch.score) {
          bestMatch = candidate;
        }
      }
    }

    return bestMatch;
  }

  List<IndexedCell> _extractLine({
    required BoardSnapshot board,
    required int row,
    required int column,
    required WordAxis axis,
  }) {
    int startRow = row;
    int startColumn = column;

    while (true) {
      final int nextRow = axis == WordAxis.horizontal ? startRow : startRow - 1;
      final int nextColumn = axis == WordAxis.horizontal
          ? startColumn - 1
          : startColumn;

      if (!_containsTile(board, nextRow, nextColumn)) {
        break;
      }

      startRow = nextRow;
      startColumn = nextColumn;
    }

    final List<IndexedCell> cells = <IndexedCell>[];
    int currentRow = startRow;
    int currentColumn = startColumn;

    while (_containsTile(board, currentRow, currentColumn)) {
      final BoardScanTile tile = board[currentRow][currentColumn]!;
      cells.add(
        IndexedCell(
          row: currentRow,
          column: currentColumn,
          letter: tile.letter,
          points: tile.points,
        ),
      );

      if (axis == WordAxis.horizontal) {
        currentColumn += 1;
      } else {
        currentRow += 1;
      }
    }

    return cells;
  }

  bool _containsTile(BoardSnapshot board, int row, int column) {
    if (row < 0 || row >= board.length) {
      return false;
    }
    if (column < 0 || column >= board[row].length) {
      return false;
    }
    return board[row][column] != null;
  }
}
