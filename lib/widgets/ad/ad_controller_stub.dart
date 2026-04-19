import 'package:flutter/material.dart';

enum AdState { loading, loaded, failed }

class AdController extends ChangeNotifier {
  AdState get state => AdState.failed;
  dynamic nativeAd;
  Future<void> load({dynamic templateStyle, String? factoryId, Map<String, Object>? customOptions}) async {}
}