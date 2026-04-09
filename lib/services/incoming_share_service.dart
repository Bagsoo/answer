import 'dart:async';

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

    try {
      final raw = await _channel.invokeMethod<dynamic>('getInitialSharedPayload');
      if (raw is Map) {
        _pendingShare =
            IncomingSharePayload.fromMap(Map<dynamic, dynamic>.from(raw));
        notifyListeners();
      }
    } catch (_) {}

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
