import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import '../../utils/ads_init_future.dart';
import '../../utils/ads_helper.dart';

enum AdState { loading, loaded, failed }

class AdController extends ChangeNotifier {
  static const _testAdUnitAndroid = 'ca-app-pub-3940256099942544/2247696110'; // 테스트
  static const _testAdUnitIos     = 'ca-app-pub-3940256099942544/3986624511'; // 테스트
  static const _prodAdUnitAndroid = 'ca-app-pub-3027819032479365/6866554616'; // 실제 (Android)
  static const _prodAdUnitIos     = 'ca-app-pub-3940256099942544/3986624511'; // 실제 (iOS) ca-app-pub-3027819032479365/6385223753
  static const _kTimeout          = kDebugMode ? Duration(seconds: 10) : Duration(seconds: 30);

  AdState _state = AdState.loading;
  NativeAd? nativeAd;
  String? lastError;
  String? rawNetResult; // 새 필드 추가
  int _attemptIndex = 0;
  static int _activeLoadCount = 0;
  bool _factoryRegistered = false;
  bool _engineCallbackFired = false;
  bool _implicitEngineCallbackFired = false;
  String? _attStatus;

  AdState get state => _state;
  String get debugAdUnitId => _adUnitId;
  String? get debugInitLog => adsInitErrorLog;
  int get debugAttemptIndex => _attemptIndex;
  int get debugActiveLoadCount => _activeLoadCount;
  bool get debugFactoryRegistered => _factoryRegistered;
  bool get debugEngineCallbackFired => _engineCallbackFired;
  bool get debugImplicitEngineCallbackFired => _implicitEngineCallbackFired;
  String get debugAttStatus => _attStatus ?? 'unknown';
  String get debugRawNetResult => rawNetResult ?? 'not run';

  void markFactoryRegistered(bool value) {
    _factoryRegistered = value;
  }

  void markEngineCallbackFired(bool value) {
    _engineCallbackFired = value;
  }

  void markImplicitEngineCallbackFired(bool value) {
    _implicitEngineCallbackFired = value;
  }

  void updateAttStatus(String? value) {
    _attStatus = value;
  }

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
    // 진단용 임시 코드 (2차 개선형)
    try {
      final sw1 = Stopwatch()..start();
      final res1 = await http
          .get(Uri.parse('https://pagead2.googlesyndication.com/pagead/gen_204?id=mobileads-sdk-core'))
          .timeout(const Duration(seconds: 5));
      sw1.stop();
      
      final sw2 = Stopwatch()..start();
      final res2 = await http
          .get(Uri.parse('https://pubads.g.doubleclick.net/gampad/ads'))
          .timeout(const Duration(seconds: 5));
      sw2.stop();
      
      rawNetResult = 'PageAd:${res1.statusCode}(${sw1.elapsedMilliseconds}ms) | PubAds:${res2.statusCode}(${sw2.elapsedMilliseconds}ms)';
    } catch (e) {
      debugPrint('Raw network test FAILED: $e');
      rawNetResult = 'RawNet FAILED: $e';
    }
    // 여기까지

    _attemptIndex += 1;
    _activeLoadCount += 1;
    _engineCallbackFired = false;

    // iOS 초기화 완료 대기 (시간 제약 없음)
    debugPrint('AdMob: waiting for ads init before loading native ad');
    await AdsInit.ready;
    debugPrint('AdMob: ads init completed, starting native ad load');

    final completer = Completer<bool>();

    // 기존 광고가 있으면 먼저 해제
    nativeAd?.dispose();
    
    final ad = NativeAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      factoryId: factoryId,
      customOptions: customOptions,
      nativeTemplateStyle: factoryId != null ? null : templateStyle,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _engineCallbackFired = true;
          debugPrint('AdMob: native ad loaded for unit=$_adUnitId');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          _engineCallbackFired = true;
          final msg = 'code:${error.code} domain:${error.domain} msg:${error.message}';
          debugPrint('AdMob: native ad failed for unit=$_adUnitId -> $msg');
          lastError = msg;
          ad.dispose();
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    // GC 방지를 위해 인스턴스 변수에 즉시 보관 (강한 참조 유지)
    nativeAd = ad;
    ad.load();

    final success = await completer.future
        .timeout(_kTimeout, onTimeout: () {
          _engineCallbackFired = false;
          debugPrint('AdMob: native ad load timed out for unit=$_adUnitId');
          lastError = 'timeout after ${_kTimeout.inSeconds}s';
          ad.dispose();
          return false;
        });

    _activeLoadCount = (_activeLoadCount > 0) ? _activeLoadCount - 1 : 0;

    if (!_disposed) {
      if (success) {
        _state = AdState.loaded;
      } else {
        nativeAd = null;
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
