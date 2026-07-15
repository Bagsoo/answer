import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../l10n/app_localizations.dart';
import 'ad_controller.dart';

class NativeAdTileMobile extends StatefulWidget {
  const NativeAdTileMobile({super.key});

  @override
  State<NativeAdTileMobile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends State<NativeAdTileMobile> {
  static const MethodChannel _debugChannel = MethodChannel('com.answer.messenger/ad_debug');

  late final AdController _ctrl;
  bool _initialized = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    _debugChannel.setMethodCallHandler(_handleDebugMessage);
  }

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

  Future<void> _handleDebugMessage(MethodCall call) async {
    if (!mounted) return;

    switch (call.method) {
      case 'nativeAdFactoryRegistered':
        final args = call.arguments as Map?;
        final registered = args?['factoryRegistered'] as bool? ?? false;
        _ctrl.markFactoryRegistered(registered);
        break;
      case 'attStatus':
        final args = call.arguments as Map?;
        final status = args?['attStatus'] as String?;
        _ctrl.updateAttStatus(status);
        break;
      default:
        break;
    }

    if (_ctrl.state == AdState.failed && !_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showAdFailureDialog();
      });
    }

    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (mounted) {
      if (_ctrl.state == AdState.failed && !_dialogShown) {
        _dialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showAdFailureDialog();
        });
      }
      setState(() {});
    }
  }

  Future<void> _showAdFailureDialog() async {
    final errorText = _ctrl.lastError ?? 'unknown error';
    final unitId = _ctrl.debugAdUnitId;
    final factoryId = 'listTile';
    final initLog = _ctrl.debugInitLog;
    final factoryRegistered = _ctrl.debugFactoryRegistered;
    final engineCallbackFired = _ctrl.debugEngineCallbackFired;
    final attemptIndex = _ctrl.debugAttemptIndex;
    final activeLoadCount = _ctrl.debugActiveLoadCount;
    final attStatus = _ctrl.debugAttStatus;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ad load failed'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Native ad load failed. Details:'),
                const SizedBox(height: 8),
                Text('unitId: $unitId'),
                const SizedBox(height: 4),
                Text('factoryId: $factoryId'),
                const SizedBox(height: 4),
                Text('error: $errorText'),
                const SizedBox(height: 4),
                Text('initLog: ${initLog ?? "none"}'),
                const SizedBox(height: 4),
                Text('factoryRegistered: $factoryRegistered'),
                const SizedBox(height: 4),
                Text('engineCallbackFired: $engineCallbackFired'),
                const SizedBox(height: 4),
                Text('attStatus: $attStatus'),
                const SizedBox(height: 4),
                Text('attemptIndex: $attemptIndex'),
                const SizedBox(height: 4),
                Text('concurrentAdLoads: $activeLoadCount'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
      AdState.failed  => _AdErrorTile(error: _ctrl.lastError),
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

class _AdErrorTile extends StatelessWidget {
  final String? error;
  const _AdErrorTile({required this.error});

  @override
  Widget build(BuildContext context) {
    final message = (error == null || error!.trim().isEmpty)
        ? 'AD FAILED: unknown error'
        : 'AD FAILED: $error';

    return SizedBox(
      height: 72,
      child: Container(
        color: Colors.red.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          message,
          style: const TextStyle(fontSize: 11, color: Colors.red),
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}