import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../l10n/app_localizations.dart';
import 'ad_controller.dart';

class NativeAdTileMobile extends StatefulWidget {
  const NativeAdTileMobile({super.key});

  @override
  State<NativeAdTileMobile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends State<NativeAdTileMobile> {
  late final AdController _ctrl;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    _initialized = true;
    _ctrl = AdController();
    _ctrl.addListener(_onChanged);
    _ctrl.load(
      factoryId: 'listTile',
      customOptions: {'adLabel': AppLocalizations.of(context).adLabel},
    );
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _ctrl
        ..removeListener(_onChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_ctrl.state) {
      AdState.loaded => SizedBox(
          height: 120,
          width: double.infinity,
          child: AdWidget(ad: _ctrl.nativeAd!),
        ),
      AdState.failed => const SizedBox.shrink(),
      AdState.loading || AdState.idle => const _AdPlaceholder(),
    };
  }
}

class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 12,
                        width: 104,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        height: 14,
                        width: 36,
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 150,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 52,
              height: 28,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
