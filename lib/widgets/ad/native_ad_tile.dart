// Web: io 라이브러리 없음 → stub. VM(Windows 포함): io 구현은 deferred로
// google_mobile_ads를 기동 시 로드하지 않는다.
export 'native_ad_tile_stub.dart'
    if (dart.library.io) 'native_ad_tile_io.dart';
