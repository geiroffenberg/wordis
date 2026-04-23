import 'package:flutter/material.dart';

import 'src/ui/game_screen.dart';

void main() {
  runApp(const WordisApp());
}

class WordisApp extends StatelessWidget {
  const WordisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScreen();
  }
}
