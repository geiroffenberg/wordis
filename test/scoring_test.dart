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

    test('Triple letter run AAA -> sum (3 * 1 = 3)', () {
      place(6, 0, 'A');
      place(6, 1, 'A');
      expect(dropAndScore(6, 2, 'A'), 3);
    });

    test('Quad letter run AAAA -> sum (4)', () {
      place(6, 0, 'A');
      place(6, 1, 'A');
      place(6, 2, 'A');
      expect(dropAndScore(6, 3, 'A'), 4);
    });

    test('Triple letter run with 2x -> sum * 2', () {
      place(6, 0, 'P'); // P=3
      place(6, 1, 'P');
      controller.setMultiplierForTesting(6, 1, 2);
      // 3+3+3 = 9, * 2 = 18
      expect(dropAndScore(6, 2, 'P'), 18);
    });

    test('Triple letter run with 4x -> sum * 4', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      controller.setMultiplierForTesting(6, 0, 4);
      expect(dropAndScore(6, 2, 'P'), 36);
    });

    test('Quad letter run with 2x -> sum * 2', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      place(6, 2, 'P');
      controller.setMultiplierForTesting(6, 1, 2);
      // 4 * 3 = 12, * 2 = 24
      expect(dropAndScore(6, 3, 'P'), 24);
    });

    test('Quad letter run with 3x -> sum * 3', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      place(6, 2, 'P');
      controller.setMultiplierForTesting(6, 2, 3);
      // 4 * 3 = 12, * 3 = 36
      expect(dropAndScore(6, 3, 'P'), 36);
    });

    test('Quintuple letter run with 4x -> sum * 4', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      place(6, 2, 'P');
      place(6, 3, 'P');
      controller.setMultiplierForTesting(6, 2, 4);
      // 5 * 3 = 15, * 4 = 60
      expect(dropAndScore(6, 4, 'P'), 60);
    });

    test('Quintuple letter run with no bonus -> sum', () {
      place(6, 0, 'P');
      place(6, 1, 'P');
      place(6, 2, 'P');
      place(6, 3, 'P');
      // 5 * 3 = 15
      expect(dropAndScore(6, 4, 'P'), 15);
    });

    test('Word + run on opposite axis acts as double-word', () {
      // Horizontal word "TOP" (T,O,P) and vertical run "T,T,T" through
      // the placed T at (6,0).
      place(4, 0, 'T');
      place(5, 0, 'T');
      place(6, 1, 'O');
      place(6, 2, 'P');

      // Drop T at (6,0):
      // Horizontal word TOP cells: (6,0)T, (6,1)O, (6,2)P -> 1+1+3 = 5
      // Vertical run TTT cells: (4,0),(5,0),(6,0) -> 1+1+1 = 3
      // Unique cells: T(4,0)+T(5,0)+T(6,0)+O(6,1)+P(6,2) = 1+1+1+1+3 = 7
      // Double word x2 = 14
      expect(dropAndScore(6, 0, 'T'), 14);
    });

    test('Chain reaction: clearing a row drops a tile that forms another word',
        () {
      // Setup at row 8 (second from bottom): A,A,A across cols 0..2.
      // Row 9 (bottom): T at col 0, P at col 2 (the col 1 below A is empty).
      // Above row 8 col 1 we stack an O at row 7.
      // Drop A at (8,1) -> AAA run clears row 8.
      // Gravity then drops O at (7,1) down to (9,1) -> TOP forms at row 9.
      place(9, 0, 'T');
      place(9, 2, 'P');
      place(8, 0, 'A');
      place(8, 2, 'A');
      place(7, 1, 'O');

      final int before = controller.score;
      controller.setActiveTileForTesting(
        const FallingTile(letter: 'A', points: 1, row: 8, column: 1),
      );
      controller.lockActiveTileForTesting();
      // First scoring: AAA run = 3.
      expect(controller.score - before, 3);
      // Simulate the UI completing the flash so gravity + chain pass run.
      controller.completeFlashPhase();
      // After gravity, O lands at (9,1) forming "TOP" -> +5.
      expect(controller.score - before, 8);
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
