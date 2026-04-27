import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/game_controller.dart';
import '../game/sound_manager.dart';

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
                    const _AdBannerPlaceholder(),
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
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(
                Icons.info_outline_rounded,
                color: Color(0x99F0E5D0),
              ),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
          const Spacer(),
          if (controller.nextTile != null)
            _NextTilePreview(tile: controller.nextTile!),
          if (controller.nextTile != null) const SizedBox(width: 14),
          _MiniScore(label: 'SCORE', value: controller.score.toString()),
          const SizedBox(width: 14),
          _MiniScore(label: 'HIGH', value: controller.highScore.toString()),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.label, required this.value});

  final String label;
  final String value;

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
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF7EDD8),
          ),
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
  List<TileDropAnimation> _activeDrops = const <TileDropAnimation>[];
  List<FlashCell> _activeFlashCells = const <FlashCell>[];
  List<ScoreBurstEvent> _activeScoreBursts = const <ScoreBurstEvent>[];

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
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _scoreBurstController.dispose();
    _flashController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final List<ScoreBurstEvent> scoreBursts =
        widget.controller.pendingScoreBursts;
    if (scoreBursts.isNotEmpty) {
      widget.controller.consumeScoreBursts();
      setState(() {
        _activeScoreBursts = scoreBursts;
      });
      _scoreBurstController.forward(from: 0);
    }

    final List<FlashCell> flashCells = widget.controller.pendingFlashCells;
    if (flashCells.isNotEmpty) {
      widget.controller.consumeFlashCells();
      widget.sound.playClear();
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
      setState(() {
        _activeDrops = pending;
        _animatingCells.clear();
        for (final TileDropAnimation drop in pending) {
          _animatingCells.add('${drop.column}:${drop.toRow}');
        }
      });
      _animController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final GameController controller = widget.controller;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF13342F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AspectRatio(
        aspectRatio: boardColumns / boardRows,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cellWidth = constraints.maxWidth / boardColumns;
            final double cellHeight = constraints.maxHeight / boardRows;

            return Stack(
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
                    final FallingTile? activeTile = controller.activeTile;
                    final bool isActiveTile =
                        activeTile != null &&
                        activeTile.row == row &&
                        activeTile.column == column;

                    // Hide tiles that are currently animating into place.
                    final bool isBeingAnimated = _animatingCells.contains(
                      '$column:$row',
                    );

                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: _BoardSquare(
                        multiplier: multiplier,
                        child: (tile != null && !isBeingAnimated)
                            ? _LetterFace(tile: tile)
                            : (isActiveTile && !isBeingAnimated)
                            ? _LetterFace(tile: activeTile)
                            : null,
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
            );
          },
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
  const _BoardSquare({required this.multiplier, this.child});

  final int multiplier;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bool isMultiplier = multiplier > 1;
    final Color baseColor = switch (multiplier) {
      2 => const Color(0xFF2B6459),
      3 => const Color(0xFF5F5530),
      4 => const Color(0xFF76433C),
      _ => const Color(0xFF245248),
    };
    final Color borderColor = switch (multiplier) {
      2 => const Color(0x4DB6F1DF),
      3 => const Color(0x5CE8CF86),
      4 => const Color(0x66F1A58E),
      _ => const Color(0x2C9EE8D4),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child:
          child ??
          (isMultiplier
              ? Center(
                  child: Text(
                    '${multiplier}x',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xB3F7EDD8),
                      letterSpacing: 0.4,
                    ),
                  ),
                )
              : null),
    );
  }
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

class _AdBannerPlaceholder extends StatelessWidget {
  const _AdBannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 58,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x26F7EDD8),
        border: Border.all(color: const Color(0x45F7EDD8)),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        'Google Ad Banner Placeholder',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xB3F7EDD8),
          letterSpacing: 0.3,
        ),
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

class _NextTilePreview extends StatelessWidget {
  const _NextTilePreview({required this.tile});

  final LetterTile tile;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        SizedBox(width: 32, height: 32, child: _LetterFace(tile: tile)),
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
                'Use the arrow buttons to move the letter left or right, '
                'and the drop button to slam it down.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Scoring Words'),
              _infoParagraph(
                'When a letter lands and completes a word of 3+ letters '
                '(horizontally or vertically), the word is cleared and '
                'you earn points based on each letter\'s Scrabble-style value.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Multiplier Squares'),
              _infoParagraph(
                'Two 2x squares are on row 4 and two 3x squares are on row 7 '
                '(counting rows from the bottom). Any letter on those squares '
                'scores with that multiplier when a word or matching run '
                'clears. The 4x square is random and relocates after being '
                'claimed.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Matching Letters'),
              _infoParagraph(
                'A run of 3 or more identical letters in a row or column '
                'also clears and scores using all letters in that run. '
                'Use this strategically when words aren\'t possible.',
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
                'to fill the gaps.',
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
