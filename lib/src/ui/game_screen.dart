import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/game_controller.dart';
import '../game/sound_manager.dart';
import '../game/word_dictionary.dart' show IndexedCell;
import 'ad_banner.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _controller;
  late final SoundManager _sound;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller = GameController();
    _controller.initialize();
    _sound = SoundManager();
    _sound.initialize();
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wordis',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1C443E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2B7E73),
          secondary: Color(0xFFE07A5C),
          surface: Color(0xFF1C443E),
        ),
      ),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFF23574F), Color(0xFF18403A)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(controller: _controller),
                    _StatusBar(controller: _controller, sound: _sound),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _BoardPanel(
                          controller: _controller,
                          sound: _sound,
                        ),
                      ),
                    ),
                    _BottomControls(controller: _controller, sound: _sound),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: AdBanner(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Text(
            'Wordis',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF7EDD8),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 30,
              icon: const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFF0E5D0),
              ),
              tooltip: 'How to play',
              onPressed: () => _showInfoDialog(context),
            ),
          ),
          const Spacer(),
          if (controller.upcomingTiles.isNotEmpty)
            _UpcomingTilesPreview(tiles: controller.upcomingTiles),
          if (controller.upcomingTiles.isNotEmpty) const SizedBox(width: 14),
          _MiniScore(label: 'SCORE', value: controller.score),
          const SizedBox(width: 14),
          _MiniScore(label: 'HIGH', value: controller.highScore),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xAAF7EDD8),
            letterSpacing: 1.2,
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (BuildContext context, double v, _) {
            return Text(
              v.toInt().toString(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF7EDD8),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.sound});

  final GameController controller;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0x22000000),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              controller.statusMessage,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: const Color(0xDDF7EDD8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _SmallActionButton(
            label: controller.isRunning ? 'Pause' : 'Resume',
            onPressed: controller.isReady && !controller.isGameOver
                ? () {
                    sound.playTap();
                    controller.togglePause();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _SmallActionButton(
            label: 'New',
            onPressed: controller.isReady
                ? () {
                    sound.playTap();
                    controller.startNewGame();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _BoardPanel extends StatefulWidget {
  const _BoardPanel({required this.controller, required this.sound});

  final GameController controller;
  final SoundManager sound;

  @override
  State<_BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends State<_BoardPanel>
    with TickerProviderStateMixin {
  late final AnimationController _animController;
  late final AnimationController _flashController;
  late final AnimationController _scoreBurstController;
  late final AnimationController _levelUpController;
  late final AnimationController _shakeController;
  late final AnimationController _wordFoundController;
  late final AnimationController _bonusPendingController;
  late final AnimationController _popController;
  List<TileDropAnimation> _activeDrops = const <TileDropAnimation>[];
  List<FlashCell> _popCells = const <FlashCell>[];
  bool _bonusDropPending = false;
  List<FlashCell> _activeFlashCells = const <FlashCell>[];
  List<ScoreBurstEvent> _activeScoreBursts = const <ScoreBurstEvent>[];
  List<IndexedCell> _wordFoundCells = const <IndexedCell>[];
  int _lastSeenLevel = 1;
  String? _activeLevelUpText;
  Set<String> _knownMarkedSignatures = <String>{};
  double _hDragStartX = 0;
  int _hDragMoveCount = 0;

  /// Keys: "column:toRow" — cells currently being animated into.
  /// We hide the static tile in the grid and show the overlay instead.
  final Set<String> _animatingCells = <String>{};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _animController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _activeDrops = const <TileDropAnimation>[];
          _animatingCells.clear();
        });
        // Complete the deferred lock after the drop animation finishes.
        widget.controller.completePendingLock();
      }
    });
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _flashController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _activeFlashCells = const <FlashCell>[];
        });
        widget.controller.completeFlashPhase();
      }
    });
    _scoreBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _scoreBurstController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _activeScoreBursts = const <ScoreBurstEvent>[];
        });
      }
    });
    _levelUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _levelUpController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _activeLevelUpText = null;
        });
      }
    });
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _wordFoundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _wordFoundController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _wordFoundCells = const <IndexedCell>[];
        });
      }
    });
    _lastSeenLevel = widget.controller.currentLevel;
    _bonusPendingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _popController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _popCells = const <FlashCell>[];
        });
      }
    });
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _scoreBurstController.dispose();
    _flashController.dispose();
    _animController.dispose();
    _levelUpController.dispose();
    _shakeController.dispose();
    _wordFoundController.dispose();
    _bonusPendingController.dispose();
    _popController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final int level = widget.controller.currentLevel;
    if (level != _lastSeenLevel) {
      if (level > _lastSeenLevel && widget.controller.isRunning) {
        setState(() {
          _activeLevelUpText = 'LEVEL $level';
        });
        _levelUpController.forward(from: 0);
        widget.sound.playLevelUp();
      }
      _lastSeenLevel = level;
    }

    final List<ScoreBurstEvent> scoreBursts =
        widget.controller.pendingScoreBursts;
    bool isLineClear = false;
    if (scoreBursts.isNotEmpty) {
      isLineClear = scoreBursts.any(
        (ScoreBurstEvent b) => b.badgeText?.startsWith('LINE CLEAR') == true,
      );
      widget.controller.consumeScoreBursts();
      setState(() {
        _activeScoreBursts = scoreBursts;
      });
      _scoreBurstController.forward(from: 0);
      if (isLineClear) {
        _shakeController.forward(from: 0);
        widget.sound.playLineClear();
      }
    }

    final List<FlashCell> flashCells = widget.controller.pendingFlashCells;
    if (flashCells.isNotEmpty) {
      widget.controller.consumeFlashCells();
      if (!isLineClear) {
        widget.sound.playClear();
      }
      setState(() {
        _activeFlashCells = flashCells;
      });
      _flashController.forward(from: 0);
      return;
    }

    final List<TileDropAnimation> pending = widget.controller.pendingAnimations;
    if (pending.isNotEmpty) {
      widget.controller.consumeAnimations();
      widget.sound.playDrop();
      // Junk drops (fromRow < 0) animate much slower than hard-drops so
      // the player can see the incoming letters and register the
      // level-up before play resumes.
      final bool isJunk = pending.any((TileDropAnimation d) => d.fromRow < 0);
      _animController.duration = isJunk
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 120);
      setState(() {
        _activeDrops = pending;
        _animatingCells.clear();
        for (final TileDropAnimation drop in pending) {
          _animatingCells.add('${drop.column}:${drop.toRow}');
        }
      });
      _animController.forward(from: 0);
    }

    // Detect newly marked words → word-found flash.
    final Set<String> nowMarked = widget.controller.markedWords
        .map((MarkedWord w) => w.signature)
        .toSet();
    final Set<String> brandNew = nowMarked.difference(_knownMarkedSignatures);
    _knownMarkedSignatures = nowMarked;
    if (brandNew.isNotEmpty) {
      final List<IndexedCell> cells = widget.controller.markedWords
          .where((MarkedWord w) => brandNew.contains(w.signature))
          .expand((MarkedWord w) => w.cells)
          .toList();
      setState(() {
        _wordFoundCells = cells;
      });
      widget.sound.playWordFound();
      _wordFoundController.forward(from: 0);
    }

    // Bonus-drop-pending strip: show while the in-flight tile is still
    // falling after a level-up, before the junk drop fires.
    final bool bonusPending =
        widget.controller.currentLevel > widget.controller.levelAtLastJunk;
    if (bonusPending != _bonusDropPending) {
      setState(() => _bonusDropPending = bonusPending);
      if (bonusPending) {
        _bonusPendingController.repeat(reverse: true);
      } else {
        _bonusPendingController.stop();
        _bonusPendingController.value = 0;
      }
    }

    // Tile pop: junk tiles that didn't form a word burst off the board.
    final List<FlashCell> pops = widget.controller.pendingPopCells;
    if (pops.isNotEmpty) {
      widget.controller.consumePopCells();
      setState(() => _popCells = pops);
      const int cellMs = 350;
      const int staggerMs = 300;
      _popController.duration = Duration(
        milliseconds: cellMs + (pops.length - 1) * staggerMs,
      );
      _popController.forward(from: 0);
      // Play the pop sound once per tile, staggered.
      for (int i = 0; i < pops.length; i++) {
        if (i == 0) {
          widget.sound.playPop();
        } else {
          Future.delayed(Duration(milliseconds: i * staggerMs), () {
            if (mounted) widget.sound.playPop();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameController controller = widget.controller;

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (BuildContext context, Widget? child) {
        final double t = _shakeController.value;
        final double shakeX =
            t > 0 ? sin(t * pi * 7) * 9.0 * (1.0 - t) : 0.0;
        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: child,
        );
      },
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _boardColorForLevel(controller.currentLevel),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AspectRatio(
        aspectRatio: boardColumns / boardRows,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cellWidth = constraints.maxWidth / boardColumns;
            final double cellHeight = constraints.maxHeight / boardRows;

            return GestureDetector(
              onVerticalDragEnd: (DragEndDetails details) {
                if ((details.primaryVelocity ?? 0) > 250) {
                  widget.sound.playTap();
                  widget.controller.hardDrop();
                }
              },
              onHorizontalDragStart: (DragStartDetails details) {
                _hDragStartX = details.localPosition.dx;
                _hDragMoveCount = 0;
              },
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                if (!widget.controller.isRunning) return;
                final double totalDx =
                    details.localPosition.dx - _hDragStartX;
                final int target = (totalDx / cellWidth).round();
                final int delta = target - _hDragMoveCount;
                if (delta > 0) {
                  for (int i = 0; i < delta; i++) {
                    widget.controller.moveRight();
                  }
                  _hDragMoveCount = target;
                } else if (delta < 0) {
                  for (int i = 0; i < -delta; i++) {
                    widget.controller.moveLeft();
                  }
                  _hDragMoveCount = target;
                }
              },
              child: Stack(
              children: <Widget>[
                // Static grid
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: boardColumns,
                  ),
                  itemCount: boardColumns * boardRows,
                  itemBuilder: (BuildContext context, int index) {
                    final int row = index ~/ boardColumns;
                    final int column = index % boardColumns;
                    final LetterTile? tile = controller.board[row][column];
                    final int multiplier = controller.multiplierAt(row, column);
                    final bool isMarked = controller.isCellMarked(row, column);
                    final bool isCrossMarked = controller.isCellMarkedCross(
                      row,
                      column,
                    );
                    final bool isLineClear = controller.isRowLineClear(row);
                    final FallingTile? activeTile = controller.activeTile;
                    final bool isActiveTile =
                        activeTile != null &&
                        activeTile.row == row &&
                        activeTile.column == column;

                    // Hide tiles that are currently animating into place.
                    final bool isBeingAnimated = _animatingCells.contains(
                      '$column:$row',
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isMarked
                          ? () {
                              widget.sound.playTap();
                              controller.tapMarkedCell(row, column);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: _BoardSquare(
                          multiplier: multiplier,
                          level: controller.currentLevel,
                          isMarked: isMarked,
                          isCrossMarked: isCrossMarked,
                          isLineClear: isLineClear,
                          child: (tile != null && !isBeingAnimated)
                              ? _LetterFace(tile: tile)
                              : (isActiveTile && !isBeingAnimated)
                              ? _LetterFace(tile: activeTile)
                              : null,
                        ),
                      ),
                    );
                  },
                ),

                // Animated overlay tiles
                if (_activeDrops.isNotEmpty)
                  AnimatedBuilder(
                    animation: _animController,
                    builder: (BuildContext context, _) {
                      return Stack(
                        children: _activeDrops.map((TileDropAnimation drop) {
                          final double fromY = drop.fromRow * cellHeight;
                          final double toY = drop.toRow * cellHeight;
                          final double currentY =
                              fromY +
                              (toY - fromY) *
                                  Curves.easeIn.transform(
                                    _animController.value,
                                  );
                          final double x = drop.column * cellWidth;

                          return Positioned(
                            left: x + 2,
                            top: currentY + 2,
                            width: cellWidth - 4,
                            height: cellHeight - 4,
                            child: _BoardSquare(
                              multiplier: controller.multiplierAt(
                                drop.toRow,
                                drop.column,
                              ),
                              level: controller.currentLevel,
                              child: _LetterFace(
                                tile: LetterTile(
                                  letter: drop.letter,
                                  points: drop.points,
                                  isBlank: drop.isBlank,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                // Word flash overlay
                if (_activeFlashCells.isNotEmpty)
                  AnimatedBuilder(
                    animation: _flashController,
                    builder: (BuildContext context, _) {
                      final double glow =
                          1.0 - Curves.easeIn.transform(_flashController.value);
                      return Stack(
                        children: _activeFlashCells.map((FlashCell cell) {
                          final double x = cell.column * cellWidth;
                          final double y = cell.row * cellHeight;
                          return Positioned(
                            left: x + 2,
                            top: y + 2,
                            width: cellWidth - 4,
                            height: cellHeight - 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color.fromRGBO(
                                  255,
                                  255,
                                  255,
                                  glow * 0.7,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Color.fromRGBO(
                                      255,
                                      215,
                                      0,
                                      glow * 0.6,
                                    ),
                                    blurRadius: 16 * glow,
                                    spreadRadius: 4 * glow,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                // Floating score bursts
                if (_activeScoreBursts.isNotEmpty)
                  AnimatedBuilder(
                    animation: _scoreBurstController,
                    builder: (BuildContext context, _) {
                      final double progress = Curves.easeOutCubic.transform(
                        _scoreBurstController.value,
                      );

                      return IgnorePointer(
                        child: Stack(
                          children: _activeScoreBursts.map((
                            ScoreBurstEvent burst,
                          ) {
                            final double burstOpacity = _scoreBurstOpacity(
                              progress: progress,
                              multiplier: burst.maxMultiplier,
                            );
                            final double burstRise = _scoreBurstRise(
                              progress: progress,
                              multiplier: burst.maxMultiplier,
                            );
                            final double areaLeft = burst.minColumn * cellWidth;
                            final double areaWidth =
                                (burst.maxColumn - burst.minColumn + 1) *
                                cellWidth;
                            final double areaTop = burst.minRow * cellHeight;
                            final double areaHeight =
                                (burst.maxRow - burst.minRow + 1) * cellHeight;
                            final double centerY =
                                areaTop + (areaHeight / 2) - burstRise;
                            final String? badgeText =
                                burst.badgeText ??
                                (burst.maxMultiplier > 1
                                    ? '${burst.maxMultiplier}x BONUS'
                                    : null);
                            final bool hasBadge = badgeText != null;

                            return Positioned(
                              left: areaLeft,
                              top: centerY - (hasBadge ? 42 : 24),
                              width: areaWidth,
                              child: Opacity(
                                opacity: burstOpacity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Stack(
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        Text(
                                          '+${burst.score}',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: hasBadge ? 36 : 32,
                                            fontWeight: FontWeight.w900,
                                            foreground: Paint()
                                              ..style = PaintingStyle.stroke
                                              ..strokeWidth = 3.2
                                              ..color = const Color(0xCC1A130E),
                                          ),
                                        ),
                                        Text(
                                          '+${burst.score}',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: hasBadge ? 36 : 32,
                                            fontWeight: FontWeight.w900,
                                            color: _scoreBurstColor(
                                              burst.maxMultiplier,
                                            ),
                                            shadows: const <Shadow>[
                                              Shadow(
                                                color: Color(0x55000000),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasBadge)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: <Widget>[
                                            Text(
                                              badgeText,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.visible,
                                              style: GoogleFonts.spaceGrotesk(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                                foreground: Paint()
                                                  ..style = PaintingStyle.stroke
                                                  ..strokeWidth = 2.6
                                                  ..color = const Color(
                                                    0xCC1A130E,
                                                  ),
                                              ),
                                            ),
                                            Text(
                                              badgeText,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.visible,
                                              style: GoogleFonts.spaceGrotesk(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                                color: _scoreBurstColor(
                                                  burst.maxMultiplier,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),

                // Level-up burst (centered, on top of everything except
                // the modal overlays below).
                if (_activeLevelUpText != null)
                  AnimatedBuilder(
                    animation: _levelUpController,
                    builder: (BuildContext context, _) {
                      final double t = _levelUpController.value;
                      final double rise = Curves.easeOutCubic.transform(t) * 60;
                      final double opacity = t < 0.15
                          ? t / 0.15
                          : t > 0.78
                          ? (1.0 - (t - 0.78) / 0.22).clamp(0.0, 1.0)
                          : 1.0;
                      final double scale =
                          0.85 +
                          0.25 *
                              Curves.easeOutBack.transform(
                                t.clamp(0.0, 0.45) / 0.45,
                              );
                      final double centerY = (constraints.maxHeight / 2) - rise;
                      return IgnorePointer(
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: 0,
                              right: 0,
                              top: centerY - 30,
                              child: Opacity(
                                opacity: opacity,
                                child: Transform.scale(
                                  scale: scale,
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        Text(
                                          _activeLevelUpText!,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: 44,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 2.5,
                                            foreground: Paint()
                                              ..style = PaintingStyle.stroke
                                              ..strokeWidth = 4.0
                                              ..color = const Color(0xCC0E1A16),
                                          ),
                                        ),
                                        Text(
                                          _activeLevelUpText!,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: 44,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 2.5,
                                            color: const Color(0xFFFFE6AF),
                                            shadows: const <Shadow>[
                                              Shadow(
                                                color: Color(0xAA000000),
                                                blurRadius: 12,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                // Word-found flash (pulse when word border first appears)
                if (_wordFoundCells.isNotEmpty)
                  AnimatedBuilder(
                    animation: _wordFoundController,
                    builder: (BuildContext context, _) {
                      final double t = _wordFoundController.value;
                      final double glow =
                          t < 0.3 ? t / 0.3 : 1.0 - ((t - 0.3) / 0.7);
                      return IgnorePointer(
                        child: Stack(
                          children: _wordFoundCells
                              .map((IndexedCell cell) {
                                final double x = cell.column * cellWidth;
                                final double y = cell.row * cellHeight;
                                return Positioned(
                                  left: x + 2,
                                  top: y + 2,
                                  width: cellWidth - 4,
                                  height: cellHeight - 4,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color.fromRGBO(
                                        255,
                                        255,
                                        220,
                                        glow * 0.5,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: Color.fromRGBO(
                                            255,
                                            60,
                                            60,
                                            glow * 0.5,
                                          ),
                                          blurRadius: 12 * glow,
                                          spreadRadius: 3 * glow,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      );
                    },
                  ),

                // Tile pop — junk tiles that didn't form a word burst off
                if (_popCells.isNotEmpty)
                  AnimatedBuilder(
                    animation: _popController,
                    builder: (BuildContext context, _) {
                      final double controllerT = _popController.value;
                      final int n = _popCells.length;
                      const double cellMs = 350.0;
                      const double staggerMs = 200.0;
                      final double totalMs = cellMs + (n - 1) * staggerMs;
                      return IgnorePointer(
                        child: Stack(
                          children: List<Widget>.generate(n, (int i) {
                            final FlashCell cell = _popCells[i];
                            final double cellStart = (i * staggerMs) / totalMs;
                            final double cellDuration = cellMs / totalMs;
                            final double localT = ((controllerT - cellStart) /
                                    cellDuration)
                                .clamp(0.0, 1.0);
                            final double scale = 1.0 + localT * 0.6;
                            final double opacity = (1.0 - localT).clamp(0.0, 1.0);
                            final double x = cell.column * cellWidth;
                            final double y = cell.row * cellHeight;
                            return Positioned(
                              left: x + 2,
                              top: y + 2,
                              width: cellWidth - 4,
                              height: cellHeight - 4,
                              child: Opacity(
                                opacity: opacity,
                                child: Transform.scale(
                                  scale: scale,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0x99FF5500),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: Color.fromRGBO(
                                            255,
                                            200,
                                            0,
                                            opacity * 0.8,
                                          ),
                                          blurRadius: 14 * opacity,
                                          spreadRadius: 4 * opacity,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),

                // Bonus-drop-pending strip — pulsing amber glow while the
                // current tile finishes falling before the level-up junk drop
                if (_bonusDropPending)
                  AnimatedBuilder(
                    animation: _bonusPendingController,
                    builder: (BuildContext context, _) {
                      final double pulse = _bonusPendingController.value;
                      return IgnorePointer(
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Opacity(
                                opacity: 0.55 + pulse * 0.45,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Color.fromRGBO(
                                      255,
                                      150,
                                      0,
                                      0.18 + pulse * 0.22,
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(10),
                                    ),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: Color.fromRGBO(
                                          255,
                                          150,
                                          0,
                                          pulse * 0.45,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '\u2605 BONUS DROP INCOMING \u2605',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: const Color(0xFFFFC842),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                // Overlays
                if (!controller.isReady)
                  const _BoardOverlay(message: 'Loading...')
                else if (!controller.isRunning && !controller.isGameOver)
                  _BoardOverlay(
                    message: 'Wordis',
                    detail: 'Tap Start to play',
                    actionLabel: 'Start',
                    onPressed: controller.startNewGame,
                  )
                else if (controller.isGameOver)
                  _BoardOverlay(
                    message: 'Game Over',
                    detail: 'Score: ${controller.score}',
                    actionLabel: 'Play Again',
                    onPressed: controller.startNewGame,
                  ),
              ],
              ),
            );
          },
        ),
      ),
    ),
  );
  }
}

Color _scoreBurstColor(int multiplier) {
  return switch (multiplier) {
    4 => const Color(0xFFFF784E),
    3 => const Color(0xFFF2B93D),
    2 => const Color(0xFF3ED8BC),
    _ => const Color(0xFFFFE6AF),
  };
}

double _scoreBurstOpacity({required double progress, required int multiplier}) {
  final double holdUntil = multiplier >= 4 ? 0.86 : 0.74;
  if (progress <= holdUntil) {
    return 1.0;
  }
  final double fadeSpan = 1.0 - holdUntil;
  return (1.0 - ((progress - holdUntil) / fadeSpan)).clamp(0.0, 1.0);
}

double _scoreBurstRise({required double progress, required int multiplier}) {
  final double maxRise = multiplier >= 4 ? 72 : 86;
  return maxRise * progress;
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.controller, required this.sound});

  final GameController controller;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ControlButton(
              icon: Icons.chevron_left_rounded,
              onPressed: controller.isRunning
                  ? () {
                      sound.playTap();
                      controller.moveLeft();
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ControlButton(
              icon: Icons.keyboard_double_arrow_down_rounded,
              onPressed: controller.isRunning
                  ? () {
                      sound.playTap();
                      controller.hardDrop();
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ControlButton(
              icon: Icons.chevron_right_rounded,
              onPressed: controller.isRunning
                  ? () {
                      sound.playTap();
                      controller.moveRight();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardSquare extends StatelessWidget {
  const _BoardSquare({
    required this.multiplier,
    this.level = 1,
    this.isMarked = false,
    this.isCrossMarked = false,
    this.isLineClear = false,
    this.child,
  });

  final int multiplier;
  final int level;
  final bool isMarked;
  final bool isCrossMarked;
  final bool isLineClear;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bool isMultiplier = multiplier > 1;
    final Color baseColor = switch (multiplier) {
      2 => const Color(0xFF2B6459),
      3 => const Color(0xFF5F5530),
      4 => const Color(0xFF76433C),
      _ => _emptyCellColorForLevel(level),
    };
    final Color borderColor = switch (multiplier) {
      2 => const Color(0x4DB6F1DF),
      3 => const Color(0x5CE8CF86),
      4 => const Color(0x66F1A58E),
      _ => const Color(0x2C9EE8D4),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLineClear
              ? const Color(0xFF00FFCC)
              : isMarked
              ? (isCrossMarked
                    ? const Color(0xFFFFBB00)
                    : const Color(0xFFFF3838))
              : borderColor,
          width: isLineClear ? 4.0 : isCrossMarked ? 3.5 : (isMarked ? 3.0 : 1.0),
        ),
        boxShadow: isLineClear
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xCC00FFCC),
                  blurRadius: 14,
                  spreadRadius: 3,
                ),
              ]
            : isMarked
            ? <BoxShadow>[
                BoxShadow(
                  color: isCrossMarked
                      ? const Color(0xAAFFBB00)
                      : const Color(0xAAFF3838),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (child != null)
            child!
          else if (isMultiplier)
            Center(
              child: Text(
                '${multiplier}x',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xB3F7EDD8),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          if (isCrossMarked)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(3.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFFFFE57F),
                      width: 2.0,
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

/// Empty-cell colors mirror the level board palette but stay one step
/// lighter so the cells read as raised against the panel.
const List<Color> _emptyCellColors = <Color>[
  Color(0xFF245248), // L1 — teal (original)
  Color(0xFF1A2A4D), // L2 — midnight (was L10)
  Color(0xFF3D5A2C), // L3 — dark olive
  Color(0xFF5D5226), // L4 — warm bronze
  Color(0xFF6A4126), // L5 — rust
  Color(0xFF67303C), // L6 — burgundy
  Color(0xFF592C5C), // L7 — plum
  Color(0xFF3A2F66), // L8 — violet
  Color(0xFF233564), // L9 — navy
  Color(0xFF26614A), // L10+ — emerald (was L2)
];

Color _emptyCellColorForLevel(int level) {
  final int idx = (level - 1).clamp(0, _emptyCellColors.length - 1);
  return _emptyCellColors[idx];
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3A786D),
          foregroundColor: const Color(0xFFF7EDD8),
          disabledBackgroundColor: const Color(0xFF245248),
          disabledForegroundColor: const Color(0x55F7EDD8),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Icon(icon, size: 34),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xDDF7EDD8),
          side: const BorderSide(color: Color(0x66F7EDD8)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _UpcomingTilesPreview extends StatelessWidget {
  const _UpcomingTilesPreview({required this.tiles});

  final List<LetterTile> tiles;

  // Sizes and opacities for positions 0, 1, 2 in the queue.
  static const List<double> _sizes = <double>[32, 27, 22];
  static const List<double> _opacities = <double>[1.0, 0.65, 0.38];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          'NEXT',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xAAF7EDD8),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Opacity(
                opacity: i < _opacities.length ? _opacities[i] : 0.25,
                child: SizedBox(
                  width: i < _sizes.length ? _sizes[i] : 18,
                  height: i < _sizes.length ? _sizes[i] : 18,
                  child: _LetterFace(tile: tiles[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _LetterFace extends StatelessWidget {
  const _LetterFace({required this.tile});

  final LetterTile tile;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tile.isBlank
              ? const <Color>[Color(0xFFE8DFF8), Color(0xFFBEAED8)]
              : const <Color>[Color(0xFFFDF0D6), Color(0xFFE8C47B)],
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  tile.letter,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: tile.isBlank
                        ? const Color(0xFF4A3060)
                        : const Color(0xFF55321A),
                    height: 1.0,
                  ),
                ),
                Text(
                  '${tile.points}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: tile.isBlank
                        ? const Color(0x994A3060)
                        : const Color(0x9955321A),
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardOverlay extends StatelessWidget {
  const _BoardOverlay({
    required this.message,
    this.detail,
    this.actionLabel,
    this.onPressed,
  });

  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xCC163732),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0E5D0),
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      color: const Color(0xCCF7EDD8),
                    ),
                  ),
                ],
                if (actionLabel != null && onPressed != null) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD66A4A),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: const Color(0xFF245248),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  'Wordis',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0E5D0),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'A falling-letter word game',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: const Color(0xCCF7EDD8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _infoHeading('How to Play'),
              _infoParagraph(
                'Letters fall one at a time onto a 7\u00d710 board. '
                'Use the arrow buttons \u2014 or swipe left or right on the board \u2014 '
                'to move the tile. Tap the \u21913 button or swipe down anywhere '
                'on the board to hard-drop the tile instantly.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Scoring Words'),
              _infoParagraph(
                'When a letter lands and completes a word of 3+ letters '
                '(horizontally or vertically), the word is marked and '
                'you immediately earn points based on each letter\'s '
                'Scrabble-style value.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Letter Values'),
              const SizedBox(height: 6),
              _LetterValuesGrid(),
              const SizedBox(height: 12),
              _infoHeading('Multiplier Squares'),
              _infoParagraph(
                'Two 2\u00d7 squares sit on row 4 and two 3\u00d7 squares on row 7 '
                '(counting from the bottom). When a word clears, the highest '
                'multiplier touched by any of its tiles applies to the whole '
                'word score. The roaming 4\u00d7 square relocates after each '
                'claim \u2014 plan ahead to land on it.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Scoring Examples'),
              const SizedBox(height: 6),
              _ScoringExamplesTable(),
              const SizedBox(height: 12),
              _infoHeading('Tap to Clear'),
              _infoParagraph(
                'Marked words stay on the board with a red glow. Tap any '
                'tile in a marked word to clear it and collect your bonus. '
                'Tapping where a horizontal and vertical word cross clears '
                'both at once for a DOUBLE WORD bonus.',
              ),
              const SizedBox(height: 8),
              _infoParagraph(
                '\u2605 LINE CLEAR \u2014 when every tile in a full row is '
                'marked, the whole row glows cyan. Tap any of those tiles '
                'to wipe the entire row with a \u00d72 bonus on every '
                'word\u2019s score.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Blank Tiles  \u2605'),
              _infoParagraph(
                'Occasionally a blank tile (\u2605) appears. When it lands, it '
                'becomes whichever letter forms the best-scoring word at that '
                'position and uses that letter\'s point value.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Gravity'),
              _infoParagraph(
                'After tiles are cleared, remaining tiles above drop down '
                'to fill the gaps. Any new words formed by the fall are '
                'marked and scored immediately.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Levels & Speed'),
              _infoParagraph(
                'Each word you clear by tapping counts as +1 word toward '
                'the next level \u2014 regardless of word length. '
                'Stacking letters without tapping never advances the level. '
                'Chain clears from gravity also count. '
                'The board hue shifts on every level-up.',
              ),
              const SizedBox(height: 8),
              _LevelSpeedTable(),
              const SizedBox(height: 12),
              _infoHeading('Bonus Drops'),
              _infoParagraph(
                'Each time you level up, three bonus tiles drop onto the board. '
                'The game tries to arrange your upcoming tiles to spell a valid '
                '3-letter word. Watch for the \u2605 BONUS DROP INCOMING \u2605 '
                'strip pulsing at the board bottom while your current tile lands.\n\n'
                'If a word can be placed, those tiles land and glow like any '
                'other marked word \u2014 tap to collect the score. '
                'If no word fits, the tiles burst off the board instead.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Strategy Tips'),
              _infoParagraph(
                '\u2022 Don\u2019t rush to tap \u2014 let new letters land on '
                'marked tiles to extend words before clearing.\n'
                '\u2022 Longer words score more at the clear phase; a 7-letter '
                'clear beats two 3-letter ones easily.\n'
                '\u2022 Stack words so they share tiles. Tapping the crossing '
                'point clears both and doubles the score.\n'
                '\u2022 Aim for the 3\u00d7 and roaming 4\u00d7 squares \u2014 '
                'one high-value letter multiplied is worth many plain clears.\n'
                '\u2022 Build toward LINE CLEAR: a full red row with the \u00d72 '
                'bonus can be your biggest single-tap score.\n'
                '\u2022 Use hard-drop (swipe down) to place tiles precisely '
                'without waiting for the tick timer.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Game Over'),
              _infoParagraph(
                'The game ends when a new tile cannot be placed at the '
                'top of the board. Try to beat your high score!',
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD66A4A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _infoHeading(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: GoogleFonts.cormorantGaramond(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFF0E5D0),
      ),
    ),
  );
}

Widget _infoParagraph(String text) {
  return Text(
    text,
    style: GoogleFonts.spaceGrotesk(
      fontSize: 13,
      color: const Color(0xDDF7EDD8),
      height: 1.5,
    ),
  );
}

/// Subtle, equal-luminance palette used to recolor the board background
/// at each level-up. Each entry is a different hue family but stays in
/// the same "deep, dim, beautiful" register so the change reads as a
/// gentle mood shift rather than a UI alert.
const List<Color> _levelBoardColors = <Color>[
  Color(0xFF13342F), // L1 — deep teal (original)
  Color(0xFF0E1A33), // L2 — midnight (was L10)
  Color(0xFF253E1C), // L3 — dark olive
  Color(0xFF3D3618), // L4 — warm bronze
  Color(0xFF452A17), // L5 — rust
  Color(0xFF421C28), // L6 — burgundy
  Color(0xFF391A3E), // L7 — plum
  Color(0xFF231C48), // L8 — violet
  Color(0xFF142146), // L9 — navy
  Color(0xFF143E2C), // L10+ — emerald (was L2)
];

Color _boardColorForLevel(int level) {
  final int idx = (level - 1).clamp(0, _levelBoardColors.length - 1);
  return _levelBoardColors[idx];
}

class _LetterValuesGrid extends StatelessWidget {
  const _LetterValuesGrid();

  static const List<List<String>> _groups = <List<String>>[
    <String>['A', 'E', 'I', 'L', 'N', 'O', 'R', 'S', 'T', 'U'],
    <String>['D', 'G'],
    <String>['B', 'C', 'M', 'P'],
    <String>['F', 'H', 'V', 'W', 'Y'],
    <String>['K'],
    <String>['J', 'X'],
    <String>['Q', 'Z'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final List<String> group in _groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  child: Text(
                    '${letterPoints[group.first]}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE9C46A),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final String letter in group)
                        _LetterChip(letter: letter),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1B3A33),
        border: Border.all(color: const Color(0x55F0E5D0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        letter,
        style: GoogleFonts.cormorantGaramond(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF0E5D0),
        ),
      ),
    );
  }
}

class _LevelSpeedTable extends StatelessWidget {
  const _LevelSpeedTable();

  static const List<({String level, String tiles, String tick, String note})>
  _rows = <({String level, String tiles, String tick, String note})>[
    (level: '1', tiles: '0',   tick: '1.00 s',         note: 'Intro pace'),
    (level: '2', tiles: '5',   tick: '0.80 s',         note: ''),
    (level: '3', tiles: '12',  tick: '0.64 s',         note: ''),
    (level: '4', tiles: '21',  tick: '0.51 s',         note: ''),
    (level: '5', tiles: '33',  tick: '0.41 s',         note: ''),
    (level: '6', tiles: '48',  tick: '0.33 s',         note: ''),
    (level: '7', tiles: '66',  tick: '0.27 s',         note: ''),
    (level: '8', tiles: '88',  tick: '0.23 s',         note: ''),
    (level: '9', tiles: '114', tick: '0.20 s',         note: ''),
    (level: '10+', tiles: '144', tick: '\u2193 5 ms/100', note: 'Soft floor'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B3A33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33F0E5D0)),
      ),
      child: Column(
        children: <Widget>[
          _header(),
          for (int i = 0; i < _rows.length; i += 1)
            _row(_rows[i], isEven: i.isEven),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF153029),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(flex: 2, child: _headerText('Level')),
          Expanded(flex: 3, child: _headerText('Words')),
          Expanded(flex: 3, child: _headerText('Fall tick')),
          Expanded(flex: 4, child: _headerText('Note')),
        ],
      ),
    );
  }

  Widget _headerText(String text) {
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: const Color(0xFFE9C46A),
      ),
    );
  }

  Widget _row(
    ({String level, String tiles, String tick, String note}) row, {
    required bool isEven,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isEven ? const Color(0x11000000) : Colors.transparent,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              row.level,
              style: GoogleFonts.cormorantGaramond(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE9C46A),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.tiles,
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                color: const Color(0xDDF7EDD8),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              row.tick,
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                color: const Color(0xDDF7EDD8),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              row.note,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: const Color(0x99F7EDD8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoringExamplesTable extends StatelessWidget {
  const _ScoringExamplesTable();

  static int _wordValue(String word) {
    int total = 0;
    for (final int code in word.codeUnits) {
      total += letterPoints[String.fromCharCode(code).toUpperCase()] ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final List<_ScoringRow> rows = <_ScoringRow>[
      _ScoringRow(
        example: 'CAT',
        formula: '3 + 1 + 1',
        score: _wordValue('CAT'),
        note: '3-letter word',
      ),
      _ScoringRow(
        example: 'HOUSE',
        formula: '4 + 1 + 1 + 1 + 1',
        score: _wordValue('HOUSE'),
        note: '5-letter word',
      ),
      _ScoringRow(
        example: 'QUARTZ',
        formula: '10 + 1 + 1 + 1 + 1 + 10',
        score: _wordValue('QUARTZ'),
        note: 'High-value letters',
      ),
      _ScoringRow(
        example: 'WORD on 2x',
        formula: '(4 + 1 + 1 + 2) × 2',
        score: _wordValue('WORD') * 2,
        note: 'Any letter on a 2x cell',
      ),
      _ScoringRow(
        example: 'WORD on 3x',
        formula: '(4 + 1 + 1 + 2) × 3',
        score: _wordValue('WORD') * 3,
        note: 'Any letter on a 3x cell',
      ),
      _ScoringRow(
        example: 'WORD on 4x',
        formula: '(4 + 1 + 1 + 2) × 4',
        score: _wordValue('WORD') * 4,
        note: 'Roaming 4x bonus cell',
      ),
      _ScoringRow(
        example: 'Cross words',
        formula: '(all unique letters) × 2',
        score: 0,
        showScore: false,
        note: 'DOUBLE WORD when H+V words share a tile',
      ),
      _ScoringRow(
        example: 'LINE CLEAR',
        formula: '(all word scores) × 2',
        score: 0,
        showScore: false,
        note: 'Full row of marked tiles — ×2 everything',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B3A33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33F0E5D0)),
      ),
      child: Column(
        children: <Widget>[
          _scoringHeaderRow(),
          for (int i = 0; i < rows.length; i += 1)
            _scoringRowWidget(rows[i], isEven: i.isEven),
        ],
      ),
    );
  }

  Widget _scoringHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF153029),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(flex: 4, child: _scoringHeaderText('Example')),
          Expanded(flex: 5, child: _scoringHeaderText('Calculation')),
          SizedBox(
            width: 48,
            child: _scoringHeaderText('Pts', align: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _scoringHeaderText(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      textAlign: align,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: const Color(0xFFE9C46A),
      ),
    );
  }

  Widget _scoringRowWidget(_ScoringRow row, {required bool isEven}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isEven ? const Color(0x11000000) : Colors.transparent,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.example,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0E5D0),
                  ),
                ),
                Text(
                  row.note,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: const Color(0x99F7EDD8),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.formula,
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  color: const Color(0xDDF7EDD8),
                  height: 1.4,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.showScore ? '${row.score}' : '—',
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE9C46A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoringRow {
  const _ScoringRow({
    required this.example,
    required this.formula,
    required this.score,
    required this.note,
    this.showScore = true,
  });

  final String example;
  final String formula;
  final int score;
  final String note;
  final bool showScore;
}
