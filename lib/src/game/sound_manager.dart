import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  final AudioPlayer _tapPlayer = AudioPlayer();
  final AudioPlayer _clearPlayer = AudioPlayer();
  final AudioPlayer _dropPlayer = AudioPlayer();
  final AudioPlayer _wordFoundPlayer = AudioPlayer();
  final AudioPlayer _lineClearPlayer = AudioPlayer();
  final AudioPlayer _levelUpPlayer = AudioPlayer();
  final AudioPlayer _popPlayer = AudioPlayer();

  static final AssetSource _tapSource = AssetSource('tap.wav');
  static final AssetSource _clearSource = AssetSource('clear.wav');
  static final AssetSource _dropSource = AssetSource('drop.wav');
  static final AssetSource _wordFoundSource = AssetSource('wordfound.wav');
  static final AssetSource _lineClearSource = AssetSource('lineclear.wav');
  static final AssetSource _levelUpSource = AssetSource('levelup.wav');
  static final AssetSource _popSource = AssetSource('pop.wav');

  // Priority levels — higher-priority sounds suppress lower-priority ones
  // that fire within the suppression window.
  static const int _priorityLow = 0;  // tap, pop, clear
  static const int _priorityMid = 1;  // drop, wordFound
  static const int _priorityHigh = 2; // lineClear, levelUp
  static const int _suppressMs = 400;

  int _lastPriority = -1;
  int _lastPlayedAt = 0;

  void _play(AudioPlayer player, AssetSource source, int priority) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (_lastPriority > priority && now - _lastPlayedAt < _suppressMs) return;
    _lastPriority = priority;
    _lastPlayedAt = now;
    player.play(source);
  }

  Future<void> initialize() async {
    await _tapPlayer.setVolume(0.5);
    await _clearPlayer.setVolume(0.7);
    await _dropPlayer.setVolume(0.5);
    await _wordFoundPlayer.setVolume(0.6);
    await _lineClearPlayer.setVolume(0.9);
    await _levelUpPlayer.setVolume(0.8);
    await _popPlayer.setVolume(0.7);
  }

  void playTap()       => _play(_tapPlayer,       _tapSource,       _priorityLow);
  void playClear()     => _play(_clearPlayer,      _clearSource,     _priorityLow);
  void playPop()       => _play(_popPlayer,        _popSource,       _priorityLow);
  void playDrop()      => _play(_dropPlayer,       _dropSource,      _priorityMid);
  void playWordFound() => _play(_wordFoundPlayer,  _wordFoundSource, _priorityMid);
  void playLineClear() => _play(_lineClearPlayer,  _lineClearSource, _priorityHigh);
  void playLevelUp()   => _play(_levelUpPlayer,    _levelUpSource,   _priorityHigh);

  void dispose() {
    _tapPlayer.dispose();
    _clearPlayer.dispose();
    _dropPlayer.dispose();
    _wordFoundPlayer.dispose();
    _lineClearPlayer.dispose();
    _levelUpPlayer.dispose();
    _popPlayer.dispose();
  }
}
