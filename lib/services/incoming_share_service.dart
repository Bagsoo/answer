import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/incoming_share_payload.dart';

class IncomingShareService extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.answer.messenger/share');
  static const EventChannel _events =
      EventChannel('com.answer.messenger/share_events');

  StreamSubscription? _subscription;
  IncomingSharePayload? _pendingShare;
  bool _initialized = false;

  IncomingSharePayload? get pendingShare => _pendingShare;
  bool get hasPendingShare => _pendingShare != null;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Windows/데스크톱에서는 아예 채널을 건드리지 않음
    final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (!isMobile) {
      debugPrint('IncomingShareService: Skipping channel init on Windows.');
      return;
    }

    try {
      final raw = await _channel.invokeMethod<dynamic>('getInitialSharedPayload');
      if (raw is Map) {
        _pendingShare =
            IncomingSharePayload.fromMap(Map<dynamic, dynamic>.from(raw));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('IncomingShareService init error: $e');
    }

    _subscription = _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      _pendingShare =
          IncomingSharePayload.fromMap(Map<dynamic, dynamic>.from(event));
      notifyListeners();
    });
  }

  Future<void> clearPendingShare() async {
    _pendingShare = null;
    notifyListeners();
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) return;

    try {
      await _channel.invokeMethod<void>('clearSharedPayload');
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
