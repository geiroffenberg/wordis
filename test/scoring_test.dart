import 'package:flutter_test/flutter_test.dart';

import 'package:wordis/src/game/game_controller.dart';
import 'package:wordis/src/game/word_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameController controller;

  setUp(() async {
    controller = GameController();
    await controller.initializeForTesting();
  });

  ResolvedWord buildResolvedWord(String word, int row, int startColumn) {
    final List<IndexedCell> cells = <IndexedCell>[];
    for (int i = 0; i < word.length; i++) {
      final String letter = word[i].toUpperCase();
      cells.add(
        IndexedCell(
          row: row,
          column: startColumn + i,
          letter: letter,
          points: letterPoints[letter]!,
        ),
      );
    }
    return ResolvedWord(
      axis: WordAxis.horizontal,
      word: word.toLowerCase(),
      cells: cells,
    );
  }

  test('TOP base score is 5 (T=1, O=1, P=3) with no multiplier', () {
    final ResolvedWord word = buildResolvedWord('TOP', 0, 0);
    expect(word.score, 5);
    expect(controller.scoreResolvedWordForTesting(word), 5);
  });

  test('TOP over a 2x cell yields 10 points', () {
    final ResolvedWord word = buildResolvedWord('TOP', 6, 1);
    controller.setMultiplierForTesting(6, 1, 2); // T on 2x
    expect(controller.scoreResolvedWordForTesting(word), 10);
  });

  test('TOP over 2x on the O cell yields 10 points', () {
    final ResolvedWord word = buildResolvedWord('TOP', 6, 1);
    controller.setMultiplierForTesting(6, 2, 2);
    expect(controller.scoreResolvedWordForTesting(word), 10);
  });

  test('TOP over 3x cell yields 15 points', () {
    final ResolvedWord word = buildResolvedWord('TOP', 3, 0);
    controller.setMultiplierForTesting(3, 2, 3);
    expect(controller.scoreResolvedWordForTesting(word), 15);
  });

  test('Word found via dictionary scan honors multiplier', () async {
    // Place T,O,P at row 6, columns 0,1,2. Mark column 1 as 2x.
    controller.placeTileForTesting(
      6,
      0,
      const LetterTile(letter: 'T', points: 1),
    );
    controller.placeTileForTesting(
      6,
      1,
      const LetterTile(letter: 'O', points: 1),
    );
    controller.placeTileForTesting(
      6,
      2,
      const LetterTile(letter: 'P', points: 3),
    );
    controller.setMultiplierForTesting(6, 1, 2);

    final BoardSnapshot snapshot = controller.snapshotBoardForTesting();
    final List<ResolvedWord> words = controller.dictionaryForTesting
        .findLongestWords(
          board: snapshot,
          row: 6,
          column: 2,
          minimumLength: 3,
        );
    expect(words, isNotEmpty);
    final ResolvedWord top = words.firstWhere(
      (ResolvedWord w) => w.word.toLowerCase() == 'top',
    );
    expect(top.score, 5, reason: 'base score should be 1+1+3');
    expect(controller.scoreResolvedWordForTesting(top), 10);
  });

  test('End-to-end: dropping P next to TO over 2x scores 10', () {
    // Place T,O at row 6 cols 0,1; will drop P at col 2 (a 2x cell on O).
    controller.placeTileForTesting(
      6,
      0,
      const LetterTile(letter: 'T', points: 1),
    );
    controller.placeTileForTesting(
      6,
      1,
      const LetterTile(letter: 'O', points: 1),
    );
    controller.setMultiplierForTesting(6, 1, 2);

    final int scoreBefore = controller.score;
    controller.setActiveTileForTesting(
      const FallingTile(letter: 'P', points: 3, row: 6, column: 2),
    );
    controller.lockActiveTileForTesting();

    expect(controller.score - scoreBefore, 10,
        reason: 'TOP with O on a 2x should award (1+1+3)*2 = 10');
    expect(controller.recentWords, isNotEmpty);
    expect(controller.recentWords.first.word, 'TOP');
    // recentWords now reflects per-word base sums (without bonus).
    expect(controller.recentWords.first.score, 5);
  });

  group('Game rules', () {
    void place(int row, int col, String letter) {
      controller.placeTileForTesting(
        row,
        col,
        LetterTile(letter: letter, points: letterPoints[letter]!),
      );
    }

    int dropAndScore(int row, int col, String letter) {
      final int before = controller.score;
      controller.setActiveTileForTesting(
        FallingTile(
          letter: letter,
          points: letterPoints[letter]!,
          row: row,
          column: col,
        ),
      );
      controller.lockActiveTileForTesting();
      return controller.score - before;
    }

    test('Single word: TOP -> 5', () {
      place(6, 0, 'T');
      place(6, 1, 'O');
      expect(dropAndScore(6, 2, 'P'), 5);
    });

    test('Single word with 3x cell: TOP on 3x -> 15', () {
      place(6, 0, 'T');
      place(6, 1, 'O');
      controller.setMultiplierForTesting(6, 1, 3);
      expect(dropAndScore(6, 2, 'P'), 15);
    });

    test('Single word with 4x cell: TOP on 4x -> 20', () {
      place(6, 0, 'T');
      place(6, 1, 'O');
      controller.setMultiplierForTesting(6, 0, 4);
      expect(dropAndScore(6, 2, 'P'), 20);
    });

    test('Double word (cross words) TOP horizontal + TOP vertical -> '
        '(unique letter sum) * 2', () {
      // Build a + shape so dropping the anchor T forms TOP horizontal
      // and TOP vertical sharing the same T at (4,2).
      // Horizontal: T(4,2) O(4,3) P(4,4)
      place(4, 3, 'O');
      place(4, 4, 'P');
      // Vertical: T(4,2) O(5,2) P(6,2)
      place(5, 2, 'O');
      place(6, 2, 'P');

      // Unique cells: T,O,P,O,P = 1+1+3+1+3 = 9. Double word x2 = 18.
      expect(dropAndScore(4, 2, 'T'), 18);
    });

    test('Double word + 2x cell -> sum * max(2, cellMult) = sum * 2', () {
      place(4, 3, 'O');
      place(4, 4, 'P');
      place(5, 2, 'O');
      place(6, 2, 'P');
      controller.setMultiplierForTesting(4, 2, 2); // anchor on 2x

      // Unique sum = 9, multiplier = max(2, 2) = 2 -> 18
      expect(dropAndScore(4, 2, 'T'), 18);
    });

    test('Double word + 3x cell -> sum * 3 (cell wins over base double)',
        () {
      place(4, 3, 'O');
      place(4, 4, 'P');
      place(5, 2, 'O');
      place(6, 2, 'P');
      controller.setMultiplierForTesting(4, 2, 3);

      // Unique sum = 9, multiplier = max(2, 3) = 3 -> 27
      expect(dropAndScore(4, 2, 'T'), 27);
    });

    test('Double word + 4x cell -> sum * 4', () {
      place(4, 3, 'O');
      place(4, 4, 'P');
      place(5, 2, 'O');
      place(6, 2, 'P');
      controller.setMultiplierForTesting(4, 2, 4);

      expect(dropAndScore(4, 2, 'T'), 36);
    });

    test('Matching-letter runs no longer score by themselves', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      controller.setMultiplierForTesting(6, 1, 4);
      expect(dropAndScore(6, 2, 'P'), 0);
    });

    test('Word + non-word cross only scores the word', () {
      place(4, 0, 'T');
      place(5, 0, 'T');
      place(6, 1, 'O');
      place(6, 2, 'P');

      expect(dropAndScore(6, 0, 'T'), 5);
    });

    test('Tapping a marked word clears it and scores again', () {
      place(6, 0, 'T');
      place(6, 1, 'O');

      final int beforeDrop = controller.score;
      controller.setActiveTileForTesting(
        const FallingTile(letter: 'P', points: 3, row: 6, column: 2),
      );
      controller.lockActiveTileForTesting();
      expect(controller.score - beforeDrop, 5);

      final int beforeTap = controller.score;
      controller.tapMarkedCell(6, 1);
      expect(controller.score - beforeTap, 5);

      controller.completeFlashPhase();
      expect(controller.board[6][0], isNull);
      expect(controller.board[6][1], isNull);
      expect(controller.board[6][2], isNull);
    });

    test('Tap-clear can trigger gravity-formed words that auto-mark and score', () {
      // Stack CAT above TOP so clearing TOP drops CAT into place.
      place(8, 0, 'C');
      place(8, 1, 'A');
      place(7, 2, 'T');
      place(9, 0, 'T');
      place(9, 1, 'O');

      controller.setActiveTileForTesting(
        const FallingTile(letter: 'P', points: 3, row: 9, column: 2),
      );
      controller.lockActiveTileForTesting();
      expect(controller.score, 5);

      final int beforeTap = controller.score;
      controller.tapMarkedCell(9, 1);
      // Clear score for 3-letter TOP at level 1 is the same base value.
      expect(controller.score - beforeTap, 5);

      final int beforeResolve = controller.score;
      controller.completeFlashPhase();
      // CAT forms after gravity and is scored as a newly marked word.
      expect(controller.score - beforeResolve, 5);
    });
  });

  test('Wildcard resolved to P also scores 10 over a 2x O cell', () {
    controller.placeTileForTesting(
      6,
      0,
      const LetterTile(letter: 'T', points: 1),
    );
    controller.placeTileForTesting(
      6,
      1,
      const LetterTile(letter: 'O', points: 1),
    );
    controller.setMultiplierForTesting(6, 1, 2);

    final int scoreBefore = controller.score;
    controller.setActiveTileForTesting(
      const FallingTile(
        letter: '★',
        points: 0,
        row: 6,
        column: 2,
        isBlank: true,
      ),
    );
    controller.lockActiveTileForTesting();

    expect(controller.score - scoreBefore, greaterThanOrEqualTo(10),
        reason: 'wildcard should score at least (1+1+3)*2 = 10');
  });
}
