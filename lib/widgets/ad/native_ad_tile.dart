import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'native_ad_tile_stub.dart' as stub;
import 'native_ad_tile_mobile.dart' deferred as mobile;

/// Android/iOS에서만 deferred 라이브러리를 로드해 광고를 띄운다.
/// Windows 등에서는 `loadLibrary`를 호출하지 않아 google_mobile_ads 네이티브가 올라가지 않는다.
class NativeAdTile extends StatefulWidget {
  const NativeAdTile({super.key});

  @override
  State<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends State<NativeAdTile> {
  bool _mobileReady = false;

  bool get _useMobileAds =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_useMobileAds) {
      mobile.loadLibrary().then((_) {
        if (mounted) setState(() => _mobileReady = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useMobileAds) {
      return const stub.NativeAdTile();
    }
    if (!_mobileReady) {
      return const stub.NativeAdTile();
    }
    return mobile.NativeAdTileMobile(key: widget.key);
  }
}
