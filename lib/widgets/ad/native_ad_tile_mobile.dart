import 'package:flutter/foundation.dart';
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
    if (!_initialized) {
      _initialized = true;
      _ctrl = AdController();
      _ctrl.addListener(_onChanged);
      _ctrl.load(
        factoryId: 'listTile',
        customOptions: {'adLabel': AppLocalizations.of(context).adLabel},
      );
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
      AdState.loading => const _AdPlaceholder(),
      AdState.failed  => const SizedBox.shrink(),
      AdState.loaded  => _AdWrapper(ad: _ctrl.nativeAd!),
    };
  }
}

class _AdWrapper extends StatelessWidget {
  final NativeAd ad;
  const _AdWrapper({required this.ad});

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 72, child: AdWidget(ad: ad));
  }
}

class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12, width: 120,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10, width: 200,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}