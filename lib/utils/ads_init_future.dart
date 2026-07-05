import 'ads_helper.dart';

/// iOS에서 MobileAds 초기화 완료를 보장하는 전역 Future
class AdsInit {
  static final Future<void> ready = initializeAds();
}
