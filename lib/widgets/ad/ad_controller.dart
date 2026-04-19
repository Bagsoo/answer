import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdState { loading, loaded, failed }

class AdController extends ChangeNotifier {
  static const _adUnitAndroid = 'ca-app-pub-3940256099942544/2247696110'; // 테스트
  static const _adUnitIos     = 'ca-app-pub-3940256099942544/3986624511'; // 테스트
  static const _kTimeout      = Duration(seconds: 3);

  AdState _state = AdState.loading;
  NativeAd? nativeAd;

  AdState get state => _state;

  String get _adUnitId => defaultTargetPlatform == TargetPlatform.iOS 
      ? _adUnitIos
      : _adUnitAndroid;

  Future<void> load({
    NativeTemplateStyle? templateStyle,
    String? factoryId,
    Map<String, Object>? customOptions,
  }) async {
    final completer = Completer<bool>();

    final ad = NativeAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle,
      factoryId: factoryId,
      customOptions: customOptions,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    )..load();

    final success = await completer.future
        .timeout(_kTimeout, onTimeout: () {
          ad.dispose();
          return false;
        });

    if (!_disposed) {
      if (success) {
        nativeAd = ad;
        _state = AdState.loaded;
      } else {
        _state = AdState.failed;
      }
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    nativeAd?.dispose();
    super.dispose();
  }
}