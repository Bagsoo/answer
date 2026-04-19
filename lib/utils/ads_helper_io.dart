import 'package:flutter/foundation.dart';

import 'ads_helper_mobile.dart' deferred as mobile;

/// Windows 등에서는 `loadLibrary`를 호출하지 않아 google_mobile_ads가 로드되지 않는다.
Future<void> initializeAds() async {
  if (kIsWeb) return;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      await mobile.loadLibrary();
      await mobile.initializeAds();
      return;
    default:
      return;
  }
}
