import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> initializeAds() async {
  final completer = Completer<void>();

  ConsentDebugSettings? debugSettings;
  if (kDebugMode) {
    debugSettings = ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
      testIdentifiers: ["4A5E0BAE886C2313F61171F58423CFFF", "7A23CED2CDDB2F4B01A0EDD490C64F3A"], // Add your device ID here if testing on a physical device
    );
  }

  final params = ConsentRequestParameters(
    consentDebugSettings: debugSettings,
  );
  await ConsentInformation.instance.reset();

  ConsentInformation.instance.requestConsentInfoUpdate(
    params,
    () async {
      await Future.delayed(const Duration(milliseconds: 1000));
      
      ConsentForm.loadAndShowConsentFormIfRequired(
        (FormError? formError) async {
          if (formError != null) {
            debugPrint('ConsentForm error: ${formError.message}');
          }
          if (await ConsentInformation.instance.canRequestAds()) {
            await MobileAds.instance.initialize();
          }
          completer.complete();
        },
      );
    },
    (FormError error) async {
      debugPrint('requestConsentInfoUpdate error: ${error.message}');
      if (await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
      }
      completer.complete();
    },
  );

  return completer.future;
}