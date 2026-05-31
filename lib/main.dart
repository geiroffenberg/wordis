import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/ui/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(MobileAds.instance.initialize());
  runApp(const WordisApp());
}

class WordisApp extends StatelessWidget {
  const WordisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScreen();
  }
}
