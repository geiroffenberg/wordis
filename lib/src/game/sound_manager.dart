import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  final AudioPlayer _tapPlayer = AudioPlayer();
  final AudioPlayer _clearPlayer = AudioPlayer();
  final AudioPlayer _dropPlayer = AudioPlayer();

  static final AssetSource _tapSource = AssetSource('tap.wav');
  static final AssetSource _clearSource = AssetSource('clear.wav');
  static final AssetSource _dropSource = AssetSource('drop.wav');

  Future<void> initialize() async {
    await _tapPlayer.setVolume(0.5);
    await _clearPlayer.setVolume(0.7);
    await _dropPlayer.setVolume(0.5);
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

  void dispose() {
    _tapPlayer.dispose();
    _clearPlayer.dispose();
    _dropPlayer.dispose();
  }
}
