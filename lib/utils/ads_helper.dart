import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

String? adsInitErrorLog;

Future<void> _initializeMobileAdsAndLog() async {
  try {
    final status = await MobileAds.instance.initialize();
    final consentStatus = await ConsentInformation.instance.getConsentStatus();
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final adapterDetails = status.adapterStatuses.entries
        .map((e) => '${e.key}:${e.value.state.name}(${e.value.description})')
        .join(",");
    final detailLog = 'Adapters:[$adapterDetails] | UMP:${consentStatus.name} | canRequest:$canRequestAds';
    adsInitErrorLog = (adsInitErrorLog != null) ? '$adsInitErrorLog | $detailLog' : detailLog;
  } catch (e) {
    adsInitErrorLog = (adsInitErrorLog != null) ? '$adsInitErrorLog | AdsInit Exception: $e' : 'AdsInit Exception: $e';
  }
}

Future<void> initializeAds() async {
  final completer = Completer<void>();

  ConsentDebugSettings? debugSettings;
  if (kDebugMode) {
    debugSettings = ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
      testIdentifiers: [
        "4A5E0BAE886C2313F61171F58423CFFF",
        "7A23CED2CDDB2F4B01A0EDD490C64F3A"
      ], // Add your device ID here if testing on a physical device
    );
  }

  final params = ConsentRequestParameters(
    consentDebugSettings: debugSettings,
  );

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () async {
      await Future.delayed(const Duration(milliseconds: 1000));

      ConsentForm.loadAndShowConsentFormIfRequired(
        (FormError? formError) async {
          if (formError != null) {
            debugPrint('ConsentForm error: ${formError.message}');
            adsInitErrorLog = 'ConsentForm error: ${formError.message}';
          }
          await _initializeMobileAdsAndLog();
          completer.complete();
        },
      );
    },
    (FormError error) async {
      debugPrint('requestConsentInfoUpdate error: ${error.message} (${error.errorCode})');
      adsInitErrorLog = 'ConsentUpdate error: ${error.message} (code:${error.errorCode})';
      await _initializeMobileAdsAndLog();
      completer.complete();
    },
  );

  return completer.future;
}