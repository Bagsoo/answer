import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'group_native_ad_tile_stub.dart' as stub;
import 'group_native_ad_tile_mobile.dart' deferred as mobile;

class GroupNativeAdTile extends StatefulWidget {
  const GroupNativeAdTile({super.key});

  @override
  State<GroupNativeAdTile> createState() => _GroupNativeAdTileState();
}

class _GroupNativeAdTileState extends State<GroupNativeAdTile> {
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
      return const stub.GroupNativeAdTile();
    }
    if (!_mobileReady) {
      return const stub.GroupNativeAdTile();
    }
    return mobile.GroupNativeAdTileMobile(key: widget.key);
  }
}
