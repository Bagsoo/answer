import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_preferences_service.dart';

class VoiceCallJoinResult {
  final String callId;
  final String token;
  final String appId;
  final String channelName;
  final int uid;
  final int expiresInSeconds;

  const VoiceCallJoinResult({
    required this.callId,
    required this.token,
    required this.appId,
    required this.channelName,
    required this.uid,
    required this.expiresInSeconds,
  });
}

class VoiceCallService {
  VoiceCallService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static const MethodChannel _systemChannel =
      MethodChannel('com.answer.messenger/voice_call');

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final ValueNotifier<bool> isInVoiceRoom = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRestoringVoiceRoom = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isVoiceRoomTransitioning = ValueNotifier<bool>(false);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> saveActiveSession({
    required String roomId,
    required String callId,
    required String roomName,
    required String appId,
    required String channelName,
    required int agoraUid,
  }) async {
    if (_uid.isEmpty) return;
    await LocalPreferencesService.setJsonMap(
      LocalPreferencesService.activeVoiceCallSessionKey(_uid),
      <String, dynamic>{
        'roomId': roomId,
        'callId': callId,
        'roomName': roomName,
        'appId': appId,
        'channelName': channelName,
        'agoraUid': agoraUid,
      },
    );
  }

  Future<Map<String, dynamic>?> getSavedActiveSession() async {
    if (_uid.isEmpty) return null;
    return LocalPreferencesService.getJsonMap(
      LocalPreferencesService.activeVoiceCallSessionKey(_uid),
    );
  }

  Future<void> clearActiveSession() async {
    if (_uid.isEmpty) return;
    await LocalPreferencesService.remove(
      LocalPreferencesService.activeVoiceCallSessionKey(_uid),
    );
  }

  Future<bool> hasActiveSession() async {
    final session = await getSavedActiveSession();
    return session != null &&
        (session['roomId'] as String? ?? '').isNotEmpty &&
        (session['callId'] as String? ?? '').isNotEmpty;
  }

  bool tryBeginVoiceRoomTransition() {
    if (isInVoiceRoom.value || isRestoringVoiceRoom.value) return false;
    if (isVoiceRoomTransitioning.value) return false;
    isVoiceRoomTransitioning.value = true;
    return true;
  }

  void endVoiceRoomTransition() {
    isVoiceRoomTransitioning.value = false;
  }

  Future<bool> isCallStillActive({
    required String roomId,
    required String callId,
  }) async {
    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    final activeCallId = roomDoc.data()?['active_call_id'] as String?;
    if (activeCallId != callId) return false;
    final callDoc = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('calls')
        .doc(callId)
        .get();
    return callDoc.exists && callDoc.data()?['status'] == 'active';
  }

  Future<VoiceCallJoinResult?> restoreActiveSession({
    required String device,
  }) async {
    if (isRestoringVoiceRoom.value) return null;
    isRestoringVoiceRoom.value = true;
    try {
      final session = await getSavedActiveSession();
      if (session == null) return null;

      final roomId = session['roomId'] as String? ?? '';
      final callId = session['callId'] as String? ?? '';
      if (roomId.isEmpty || callId.isEmpty) {
        await clearActiveSession();
        return null;
      }

      final isActive = await isCallStillActive(roomId: roomId, callId: callId);
      if (!isActive) {
        await clearActiveSession();
        await stopSystemCallNotification();
        return null;
      }

      final result = await joinVoiceCall(
        roomId: roomId,
        callId: callId,
        device: device,
      );
      await saveActiveSession(
        roomId: roomId,
        callId: callId,
        roomName: session['roomName'] as String? ?? roomId,
        appId: result.appId,
        channelName: result.channelName,
        agoraUid: result.uid,
      );
      return result;
    } finally {
      isRestoringVoiceRoom.value = false;
    }
  }

  Future<String?> getActiveCallId(String roomId) async {
    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    return roomDoc.data()?['active_call_id'] as String?;
  }

  Future<String?> getActiveCallType(String roomId) async {
    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    return roomDoc.data()?['active_call_type'] as String?;
  }

  Future<String> startVoiceCall(String roomId, {String type = 'voice'}) async {
    final callable = _functions.httpsCallable('startVoiceCall');
    final result = await callable.call(<String, dynamic>{
      'roomId': roomId,
      'type': type,
    });
    return (result.data as Map)['callId'] as String;
  }

  Future<VoiceCallJoinResult> joinVoiceCall({
    required String roomId,
    required String callId,
    required String device,
    bool isVideoEnabled = false,
  }) async {
    final callable = _functions.httpsCallable('joinVoiceCall');
    final result = await callable.call(<String, dynamic>{
      'roomId': roomId,
      'callId': callId,
      'device': device,
      'isVideoEnabled': isVideoEnabled,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return VoiceCallJoinResult(
      callId: callId,
      token: data['token'] as String? ?? '',
      appId: data['appId'] as String? ?? '',
      channelName: data['channelName'] as String? ?? '',
      uid: data['uid'] as int? ?? 0,
      expiresInSeconds: data['expiresInSeconds'] as int? ?? 0,
    );
  }

  Future<VoiceCallJoinResult> refreshVoiceToken({
    required String roomId,
    required String callId,
  }) async {
    final callable = _functions.httpsCallable('refreshVoiceToken');
    final result = await callable.call(<String, dynamic>{
      'roomId': roomId,
      'callId': callId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return VoiceCallJoinResult(
      callId: callId,
      token: data['token'] as String? ?? '',
      appId: data['appId'] as String? ?? '',
      channelName: data['channelName'] as String? ?? '',
      uid: data['uid'] as int? ?? 0,
      expiresInSeconds: data['expiresInSeconds'] as int? ?? 0,
    );
  }

  Future<void> leaveVoiceCall({
    required String roomId,
    required String callId,
  }) async {
    final callable = _functions.httpsCallable('leaveVoiceCall');
    await callable.call(<String, dynamic>{
      'roomId': roomId,
      'callId': callId,
    });
  }

  Future<void> updateHeartbeat({
    required String roomId,
    required String callId,
    required String uid,
  }) async {
    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('calls')
        .doc(callId)
        .collection('participants')
        .doc(uid)
        .set({
      'last_seen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setMuted({
    required String roomId,
    required String callId,
    required String uid,
    required bool isMuted,
  }) async {
    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('calls')
        .doc(callId)
        .collection('participants')
        .doc(uid)
        .set({
      'is_muted': isMuted,
      'last_seen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startSystemCallNotification({
    required String roomName,
    required String roomId,
    required String callId,
    required String ongoingText,
    required String returnActionLabel,
    required String endActionLabel,
  }) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _systemChannel.invokeMethod('startVoiceCallService', <String, dynamic>{
        'roomName': roomName,
        'roomId': roomId,
        'callId': callId,
        'ongoingText': ongoingText,
        'returnActionLabel': returnActionLabel,
        'endActionLabel': endActionLabel,
      });
    } catch (_) {}
  }

  Future<void> stopSystemCallNotification() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _systemChannel.invokeMethod('stopVoiceCallService');
    } catch (_) {}
  }

  Future<String?> getAndClearPendingSystemAction() async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final action =
          await _systemChannel.invokeMethod<String>('getAndClearPendingVoiceCallAction');
      if (action == null || action.isEmpty) return null;
      return action;
    } catch (_) {
      return null;
    }
  }

  Future<void> endSavedActiveSessionIfAny() async {
    final session = await getSavedActiveSession();
    if (session == null) {
      await stopSystemCallNotification();
      return;
    }

    final roomId = session['roomId'] as String? ?? '';
    final callId = session['callId'] as String? ?? '';
    try {
      if (roomId.isNotEmpty && callId.isNotEmpty) {
        await leaveVoiceCall(roomId: roomId, callId: callId);
      }
    } catch (_) {
      // Best-effort cleanup if the room already ended.
    } finally {
      await clearActiveSession();
      await stopSystemCallNotification();
      endVoiceRoomTransition();
    }
  }
}
