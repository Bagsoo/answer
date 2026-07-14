import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

String? adsInitErrorLog;

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
          // canRequestAds가 false여도 SDK 초기화 자체는 진행하여 ad.load()가 무한 대기(Timeout)에 빠지지 않게 합니다.
          try {
            final status = await MobileAds.instance.initialize();
            adsInitErrorLog = (adsInitErrorLog != null) 
                ? '${adsInitErrorLog} | AdsInit OK: ${status.adapterStatuses.keys.join(",")}' 
                : 'AdsInit OK: ${status.adapterStatuses.keys.join(",")}';
          } catch (e) {
            adsInitErrorLog = (adsInitErrorLog != null) ? '${adsInitErrorLog} | AdsInit Exception: $e' : 'AdsInit Exception: $e';
          }
          completer.complete();
        },
      );
    },
    (FormError error) async {
      debugPrint('requestConsentInfoUpdate error: ${error.message} (${error.errorCode})');
      adsInitErrorLog = 'ConsentUpdate error: ${error.message} (code:${error.errorCode})';
      
      try {
        final status = await MobileAds.instance.initialize();
        adsInitErrorLog = '${adsInitErrorLog} | AdsInit OK: ${status.adapterStatuses.keys.join(",")}';
      } catch (e) {
        adsInitErrorLog = '${adsInitErrorLog} | AdsInit Exception: $e';
      }
      completer.complete();
    },
  );

  return completer.future;
}