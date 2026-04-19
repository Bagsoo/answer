import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/ad/native_ad_tile.dart';

// ── 광고 삽입 상수 ──────────────────────────────────────────────────────────
const int _kMinItemsBeforeFirstAd = 3; // 첫 광고 전 최소 아이템 수
const int _kMinItemsBetweenAds    = 5; // 광고 간 최소 간격
const int _kMaxAdsPerList         = 2; // 전체 최대 광고 수

/// [items] 리스트 사이사이에 [NativeAdTile]을 삽입해 반환.
/// 여러 섹션에서 동일하게 호출할 경우 키 중복을 막기 위해 [keyPrefix]를 사용할 수 있습니다.
List<Widget> interleaveAds(List<Widget> items, {String keyPrefix = 'native_ad'}) {
  // 모바일 플랫폼(Android, iOS)이 아니면 광고 삽입 없이 원본 리스트 반환
  final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  if (!isMobile) return items;

  if (items.length < _kMinItemsBeforeFirstAd) return items;

  final result = <Widget>[];
  int adsInserted = 0;
  int itemsSinceLastAd = 0;

  for (int i = 0; i < items.length; i++) {
    result.add(items[i]);
    itemsSinceLastAd++;

    final isAfterFirstThreshold =
        i + 1 >= _kMinItemsBeforeFirstAd && adsInserted == 0;
    final isAfterInterval =
        itemsSinceLastAd >= _kMinItemsBetweenAds && adsInserted > 0;
    final canInsertMore = adsInserted < _kMaxAdsPerList;
    final isNotLast = i < items.length - 1;

    if (canInsertMore && isNotLast && (isAfterFirstThreshold || isAfterInterval)) {
      result.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeAdTile(key: ValueKey('${keyPrefix}_$adsInserted')),
            const Divider(height: 1),
          ],
        ),
      );
      adsInserted++;
      itemsSinceLastAd = 0;
    }
  }

  return result;
}