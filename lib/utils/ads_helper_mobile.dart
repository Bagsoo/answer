import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> initializeAds() async {
  await MobileAds.instance.initialize();
}