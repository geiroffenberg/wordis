import 'package:flutter/foundation.dart';

class AdMobConfig {
  // Use Google's test ads in debug/profile builds. Set to false (or rely on
  // kReleaseMode) to switch to your real unit IDs in release builds.
  static const bool useTestAds = !kReleaseMode;

  // Replace these with your real banner IDs before release.
  static const String _androidProdBanner = 'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';
  static const String _iosProdBanner = 'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';

  // Google-provided test banner IDs. Safe to use during development.
  static const String _androidTestBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _iosTestBanner = 'ca-app-pub-3940256099942544/2934735716';

  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return useTestAds ? _androidTestBanner : _androidProdBanner;
      case TargetPlatform.iOS:
        return useTestAds ? _iosTestBanner : _iosProdBanner;
      default:
        return '';
    }
  }
}
