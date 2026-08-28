import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdState { idle, loading, loaded, failed }

class AdController extends ChangeNotifier {
  static const _testAdUnitAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testAdUnitIos = 'ca-app-pub-3940256099942544/3986624511';
  static const _prodAdUnitAndroid = 'ca-app-pub-3027819032479365/6866554616';
  static const _prodAdUnitIos = 'ca-app-pub-3940256099942544/3986624511'; // ca-app-pub-3027819032479365/6385223753
  static const _timeout = Duration(seconds: 8);

  AdState _state = AdState.idle;
  AdState get state => _state;

  NativeAd? nativeAd;
  String? lastError;

  String get _adUnitId {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (kReleaseMode) {
      return isIos ? _prodAdUnitIos : _prodAdUnitAndroid;
    }
    return isIos ? _testAdUnitIos : _testAdUnitAndroid;
  }

  Timer? _timeoutTimer;
  bool _disposed = false;

  Future<void> load({
    NativeTemplateStyle? templateStyle,
    String? factoryId,
    Map<String, Object>? customOptions,
  }) async {
    if (_disposed || _state == AdState.loading || _state == AdState.loaded) {
      return;
    }

    _timeoutTimer?.cancel();
    _state = AdState.loading;
    notifyListeners();

    final ad = NativeAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      factoryId: factoryId,
      customOptions: customOptions,
      nativeTemplateStyle: factoryId != null ? null : templateStyle,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          if (_disposed) {
            ad.dispose();
            return;
          }
          nativeAd = ad as NativeAd;
          _state = AdState.loaded;
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          _timeoutTimer?.cancel();
          _timeoutTimer = null;
          ad.dispose();
          if (_disposed) {
            return;
          }
          nativeAd = null;
          lastError = error.toString();
          _state = AdState.failed;
          notifyListeners();
        },
      ),
    );

    nativeAd = ad;
    _timeoutTimer = Timer(_timeout, () {
      if (_disposed || _state != AdState.loading) {
        return;
      }
      nativeAd?.dispose();
      nativeAd = null;
      lastError = 'timeout after ${_timeout.inSeconds}s';
      _state = AdState.failed;
      notifyListeners();
    });

    ad.load();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    nativeAd?.dispose();
    nativeAd = null;
    super.dispose();
  }
}
