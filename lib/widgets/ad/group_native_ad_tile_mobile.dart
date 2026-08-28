import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../l10n/app_localizations.dart';
import 'ad_controller.dart';

class GroupNativeAdTileMobile extends StatefulWidget {
  const GroupNativeAdTileMobile({super.key});

  @override
  State<GroupNativeAdTileMobile> createState() => _GroupNativeAdTileMobileState();
}

class _GroupNativeAdTileMobileState extends State<GroupNativeAdTileMobile> {
  late AdController _ctrl;
  bool _initialized = false;
  Brightness? _loadedBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_initialized && _loadedBrightness == brightness) return;

    if (_initialized) {
      _ctrl
        ..removeListener(_onChanged)
        ..dispose();
      _initialized = false;
    }

    _initialized = true;
    _loadedBrightness = brightness;
    _ctrl = AdController();
    _ctrl.addListener(_onChanged);
    _ctrl.load(
      factoryId: 'groupTile',
      customOptions: {
        'adLabel': AppLocalizations.of(context).adLabel,
        'themeBrightness': brightness == Brightness.dark ? 'dark' : 'light',
      },
    );
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
      AdState.loaded => SizedBox(
          height: 152,
          width: double.infinity,
          child: AdWidget(ad: _ctrl.nativeAd!),
        ),
      AdState.failed => const SizedBox.shrink(),
      AdState.loading || AdState.idle => const _GroupAdPlaceholder(),
    };
  }
}

class _GroupAdPlaceholder extends StatelessWidget {
  const _GroupAdPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 152,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 96,
                      height: 12,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 34,
                      height: 16,
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 170,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 84,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
