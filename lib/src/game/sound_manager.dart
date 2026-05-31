import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  final AudioPlayer _tapPlayer = AudioPlayer();
  final AudioPlayer _clearPlayer = AudioPlayer();
  final AudioPlayer _dropPlayer = AudioPlayer();
  final AudioPlayer _wordFoundPlayer = AudioPlayer();
  final AudioPlayer _lineClearPlayer = AudioPlayer();
  final AudioPlayer _levelUpPlayer = AudioPlayer();

  static final AssetSource _tapSource = AssetSource('tap.wav');
  static final AssetSource _clearSource = AssetSource('clear.wav');
  static final AssetSource _dropSource = AssetSource('drop.wav');
  static final AssetSource _wordFoundSource = AssetSource('wordfound.wav');
  static final AssetSource _lineClearSource = AssetSource('lineclear.wav');
  static final AssetSource _levelUpSource = AssetSource('levelup.wav');

  Future<void> initialize() async {
    await _tapPlayer.setVolume(0.5);
    await _clearPlayer.setVolume(0.7);
    await _dropPlayer.setVolume(0.5);
    await _wordFoundPlayer.setVolume(0.6);
    await _lineClearPlayer.setVolume(0.9);
    await _levelUpPlayer.setVolume(0.8);
  }

  void playTap() {
    _tapPlayer.play(_tapSource);
  }

  void playClear() {
    _clearPlayer.play(_clearSource);
  }

  void playDrop() {
    _dropPlayer.play(_dropSource);
  }

  void playWordFound() {
    _wordFoundPlayer.play(_wordFoundSource);
  }

  void playLineClear() {
    _lineClearPlayer.play(_lineClearSource);
  }

  void playLevelUp() {
    _levelUpPlayer.play(_levelUpSource);
  }

  void dispose() {
    _tapPlayer.dispose();
    _clearPlayer.dispose();
    _dropPlayer.dispose();
    _wordFoundPlayer.dispose();
    _lineClearPlayer.dispose();
    _levelUpPlayer.dispose();
  }
}
