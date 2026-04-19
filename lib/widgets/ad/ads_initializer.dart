// lib/utils/ads_initializer.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 모바일에서만 실제 구현이 실행됨
Future<void> initializeAds() async {
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (!isMobile) return;

  // 동적 import로 Windows에서 라이브러리 로드 방지
  await _initMobileAds();
}

Future<void> _initMobileAds() async {
  try {
    // ignore: avoid_dynamic_calls
    final MobileAds = await _loadMobileAds();
    await MobileAds.initialize();
  } catch (e) {
    debugPrint('MobileAds init error: $e');
  }
}

Future<dynamic> _loadMobileAds() async {
  // dart:mirrors 없이 동적 로딩 불가하므로 다른 방식 필요
}