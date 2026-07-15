import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../utils/ads_init_future.dart';
import '../../utils/ads_helper.dart';

enum AdState { loading, loaded, failed }

class AdController extends ChangeNotifier {
  static const _testAdUnitAndroid = 'ca-app-pub-3940256099942544/2247696110'; // 테스트
  static const _testAdUnitIos     = 'ca-app-pub-3940256099942544/3986624511'; // 테스트
  static const _prodAdUnitAndroid = 'ca-app-pub-3027819032479365/6866554616'; // 실제 (Android)
  static const _prodAdUnitIos     = 'ca-app-pub-3940256099942544/3986624511'; // 실제 (iOS) ca-app-pub-3027819032479365/6385223753
  static const _kTimeout          = Duration(seconds: 15); // iOS는 초기화 완료 대기 필요

  AdState _state = AdState.loading;
  NativeAd? nativeAd;
  String? lastError;

  AdState get state => _state;

  String get _adUnitId {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    if (kReleaseMode) {
      return isIos ? _prodAdUnitIos : _prodAdUnitAndroid;
    } else {
      return isIos ? _testAdUnitIos : _testAdUnitAndroid;
    }
  }

  Future<void> load({
    NativeTemplateStyle? templateStyle,
    String? factoryId,
    Map<String, Object>? customOptions,
  }) async {
    // iOS 초기화 완료 대기 (시간 제약 없음)
    debugPrint('AdMob: waiting for ads init before loading native ad');
    await AdsInit.ready;
    debugPrint('AdMob: ads init completed, starting native ad load');

    final completer = Completer<bool>();

    final ad = NativeAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle,
      factoryId: factoryId,
      customOptions: customOptions,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          debugPrint('AdMob: native ad loaded for unit=$_adUnitId');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          final msg = 'code:${error.code} domain:${error.domain} msg:${error.message}';
          debugPrint('AdMob: native ad failed for unit=$_adUnitId -> $msg');
          lastError = msg;
          ad.dispose();
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    )..load();

    final success = await completer.future
        .timeout(_kTimeout, onTimeout: () {
          debugPrint('AdMob: native ad load timed out for unit=$_adUnitId');
          lastError = 'timeout after ${_kTimeout.inSeconds}s';
          ad.dispose();
          return false;
        });

    if (!_disposed) {
      if (success) {
        nativeAd = ad;
        _state = AdState.loaded;
      } else {
        _state = AdState.failed;
        if (adsInitErrorLog != null) {
          lastError = (lastError == null) 
              ? 'InitLog: $adsInitErrorLog' 
              : '$lastError | InitLog: $adsInitErrorLog';
        }
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