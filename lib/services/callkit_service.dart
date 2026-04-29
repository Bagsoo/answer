import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallkitService {
  CallkitService._();

  static final CallkitService instance = CallkitService._();

  StreamSubscription? _subscription;

  String callkitIdFromCallId(String callId) {
    final bytes = md5.convert(utf8.encode(callId)).bytes;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  Future<void> startOutgoingVoiceCall({
    required String callId,
    required String roomName,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final callkitId = callkitIdFromCallId(callId);
    final params = CallKitParams(
      id: callkitId,
      nameCaller: roomName,
      appName: 'Answer',
      handle: roomName,
      type: 0,
      extra: <String, dynamic>{
        'callId': callId,
      },
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Calling...',
        callbackText: 'Hang Up',
      ),
      missedCallNotification: const NotificationParams(
        showNotification: false,
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowCallID: false,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    final exists = activeCalls.any((dynamic item) {
      if (item is Map) {
        return item['id'] == callkitId;
      }
      return false;
    });
    if (!exists) {
      await FlutterCallkitIncoming.startCall(params);
    }
    await FlutterCallkitIncoming.setCallConnected(callkitId);
  }

  Future<void> endCall(String callId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await FlutterCallkitIncoming.endCall(callkitIdFromCallId(callId));
  }

  void bindEndCallback(Future<void> Function() onEnded) {
    _subscription?.cancel();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _subscription = FlutterCallkitIncoming.onEvent.listen((dynamic event) async {
      final name = event?.event?.toString() ?? '';
      if (name.contains('actionCallEnded') || name.contains('ACTION_CALL_ENDED')) {
        await onEnded();
      }
    });
  }

  Future<void> unbind() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
