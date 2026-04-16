import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'chat_service.dart';
import '../screens/chat_room_screen.dart';
import '../screens/group_detail_screen.dart';
import '../screens/group_tabs/join_requests_screen.dart';

// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background FCM: ${message.messageId}');
  await NotificationService().showNotificationFromRemoteMessage(message);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _lastHandledTarget;
  bool _pluginInitialized = false;

  // ── 알림 채널 ──────────────────────────────────────────────────────────────
  static const _chatChannel = AndroidNotificationChannel(
    'chat_channel', '채팅 알림',
    description: '새 채팅 메시지 알림',
    importance: Importance.high,
  );
  static const _scheduleChannel = AndroidNotificationChannel(
    'schedule_channel', '일정 알림',
    description: '일정 시작 15분 전 알림',
    importance: Importance.high,
  );
  static const _joinRequestChannel = AndroidNotificationChannel(
    'join_request_channel', '가입 요청 알림',
    description: '새 그룹 가입 요청 알림',
    importance: Importance.defaultImportance,
  );
  static const _marketingChannel = AndroidNotificationChannel(
    'marketing_channel', '마케팅 알림',
    description: '이벤트 및 공지 알림',
    importance: Importance.low,
  );

  // ── 초기화 ─────────────────────────────────────────────────────────────────
  Future<void> init() async {
    tz.initializeTimeZones();

    await _ensureLocalNotificationsInitialized();

    final settings2 = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings2.authorizationStatus}');

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNavigationFromData(initialMessage.data);
    }

    await _saveFcmToken();
    _fcm.onTokenRefresh.listen((token) => _saveToken(token));
  }

  // ── FCM 토큰 저장 ───────────────────────────────────────────────────────────
  Future<void> _saveFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      _ => 'unknown',
    };
    await _db
        .collection('users')
        .doc(uid)
        .collection('fcm_tokens')
        .doc(token.substring(0, 20))
        .set({
      'token': token,
      'platform': platform,
      'updated_at': FieldValue.serverTimestamp(),
    });
    // 토큰 저장 후 Cloud Function(onUserTokenChangedV2)이 자동으로
    // 해당 유저가 속한 모든 chat_rooms / groups의 active_fcm_tokens를 갱신함
  }

  // 로그아웃 시 토큰 삭제
  Future<void> deleteFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
    // Firestore 문서 삭제 → onUserTokenChangedV2가 active_fcm_tokens에서도 제거
    await _db
        .collection('users')
        .doc(uid)
        .collection('fcm_tokens')
        .doc(token.substring(0, 20))
        .delete();
    await _fcm.deleteToken();
  }

  // ── 포그라운드 FCM 수신 → 로컬 알림으로 표시 ──────────────────────────────
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;

    // 현재 보고 있는 채팅방이면 알림 무시
    final chatService = ChatService();
    if (data['type'] == 'chat' &&
        data['roomId'] == chatService.currentRoomId) {
      return;
    }

    await showNotificationFromRemoteMessage(message);
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _handleNavigationFromData(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final parts = payload.split('|');
    if (parts.length < 2) return;
    _handleNavigationFromData({
      'type': parts[0],
      'roomId': parts[0] == 'chat' ? parts[1] : '',
      'groupId':
          parts[0] == 'join_request' || parts[0] == 'group_notice' ? parts[1] : '',
    });
  }

  String _channelIdFromData(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'chat':
        return 'chat_channel';
      case 'join_request':
        return 'join_request_channel';
      case 'schedule':
        return 'schedule_channel';
      case 'marketing':
        return 'marketing_channel';
      case 'group_notice':
        return 'chat_channel';
      default:
        return 'chat_channel';
    }
  }

  String _channelNameFromId(String id) {
    switch (id) {
      case 'chat_channel':
        return '채팅 알림';
      case 'join_request_channel':
        return '가입 요청 알림';
      case 'schedule_channel':
        return '일정 알림';
      case 'marketing_channel':
        return '마케팅 알림';
      default:
        return '알림';
    }
  }

  String _payloadFromData(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final id = data['roomId'] ?? data['groupId'] ?? '';
    return '$type|$id';
  }

  Future<void> _ensureLocalNotificationsInitialized() async {
    if (_pluginInitialized) return;

    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_chatChannel);
    await androidPlugin?.createNotificationChannel(_scheduleChannel);
    await androidPlugin?.createNotificationChannel(_joinRequestChannel);
    await androidPlugin?.createNotificationChannel(_marketingChannel);
    await androidPlugin?.requestNotificationsPermission();

    _pluginInitialized = true;
  }

  Future<void> showNotificationFromRemoteMessage(RemoteMessage message) async {
    await _ensureLocalNotificationsInitialized();

    final data = message.data;
    final notification = message.notification;
    final channelId = _channelIdFromData(data);
    final title =
        data['notificationTitle'] as String? ?? notification?.title ?? '';
    final body =
        data['notificationBody'] as String? ?? notification?.body ?? '';
    final avatarUrl = data['avatarUrl'] as String? ?? '';

    if (title.isEmpty && body.isEmpty) return;

    final largeIcon = await _largeIconFromUrl(avatarUrl);

    await _plugin.show(
      message.messageId?.hashCode ?? message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelNameFromId(channelId),
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigTextStyleInformation(body),
          largeIcon: largeIcon,
        ),
      ),
      payload: _payloadFromData(data),
    );
  }

  Future<ByteArrayAndroidBitmap?> _largeIconFromUrl(String url) async {
    if (url.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;
      return ByteArrayAndroidBitmap(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  void _handleNavigationFromData(
    Map<String, dynamic> data, {
    int retryCount = 0,
  }) {
    final nav = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (nav == null || context == null) {
      if (retryCount >= 10) return;
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _handleNavigationFromData(data, retryCount: retryCount + 1),
      );
      return;
    }

    final type = data['type'] as String? ?? '';
    final roomId = data['roomId'] as String? ?? '';
    final groupId = data['groupId'] as String? ?? '';
    final targetKey = '$type:${roomId.isNotEmpty ? roomId : groupId}';

    if (targetKey.isEmpty || targetKey == _lastHandledTarget) {
      return;
    }
    _lastHandledTarget = targetKey;

    Future.delayed(const Duration(seconds: 1), () {
      if (_lastHandledTarget == targetKey) {
        _lastHandledTarget = null;
      }
    });

    if (type == 'chat' && roomId.isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(roomId: roomId),
        ),
      );
      return;
    }

    if (type == 'join_request' && groupId.isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => JoinRequestsScreen(groupId: groupId),
        ),
      );
      return;
    }

    if (type == 'group_notice' && groupId.isNotEmpty) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => GroupDetailScreen(
            groupId: groupId,
            groupName: data['groupName'] as String? ?? '',
          ),
        ),
      );
    }
  }

  // ── 알림 설정 로드 / 저장 ──────────────────────────────────────────────────
  Future<Map<String, bool>> loadNotificationSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _defaultSettings();

    final doc = await _db.collection('users').doc(uid).get();
    final raw =
        doc.data()?['notification_settings'] as Map<String, dynamic>?;
    if (raw == null) return _defaultSettings();

    return {
      'chat_message': raw['chat_message'] as bool? ?? true,
      'join_request': raw['join_request'] as bool? ?? true,
      'new_schedule': raw['new_schedule'] as bool? ?? true,
      'marketing': raw['marketing'] as bool? ?? false,
    };
  }

  Future<void> saveNotificationSettings(Map<String, bool> settings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .update({'notification_settings': settings});
  }

  Map<String, bool> _defaultSettings() => {
        'chat_message': true,
        'join_request': true,
        'new_schedule': true,
        'marketing': false,
      };

  // ── 그룹 알림 ON/OFF ────────────────────────────────────────────────────────
  Future<bool> getGroupNotificationEnabled(String groupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('group_notification_settings')
        .doc(groupId)
        .get();
    return doc.data()?['enabled'] as bool? ?? true;
  }

  Future<void> setGroupNotificationEnabled(
      String groupId, bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('group_notification_settings')
        .doc(groupId)
        .set({'enabled': enabled});
  }

  // ── 채팅방 뮤트 ─────────────────────────────────────────────────────────────
  // 뮤트 ON  → room_members에 기록 + active_fcm_tokens에서 내 토큰 제거
  // 뮤트 OFF → room_members에 기록 + active_fcm_tokens에 내 토큰 다시 추가
  Future<bool> getChatRoomMuted(String roomId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .doc(uid)
        .get();
    return doc.data()?['notification_muted'] as bool? ?? false;
  }

  Future<void> setChatRoomMuted(String roomId, bool muted) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. 내 FCM 토큰 목록 조회
    final tokensSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('fcm_tokens')
        .get();
    final myTokens = tokensSnap.docs.map((d) => d['token'] as String).toList();

    // 2. room_members 뮤트 상태 + active_fcm_tokens 동시 업데이트
    final WriteBatch batch = _db.batch();

    final memberRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .doc(uid);
    batch.update(memberRef, {'notification_muted': muted});

    final roomRef = _db.collection('chat_rooms').doc(roomId);
    if (muted) {
      final updates = <String, dynamic>{
        'muted_uids': FieldValue.arrayUnion([uid]),
      };
      if (myTokens.isNotEmpty) {
        updates['active_fcm_tokens'] = FieldValue.arrayRemove(myTokens);
      }
      batch.update(roomRef, updates);
    } else {
      final updates = <String, dynamic>{
        'muted_uids': FieldValue.arrayRemove([uid]),
      };
      if (myTokens.isNotEmpty) {
        updates['active_fcm_tokens'] = FieldValue.arrayUnion(myTokens);
      }
      batch.update(roomRef, updates);
    }
    
    if (false) {
      final roomRef = _db.collection('chat_rooms').doc(roomId);
      if (muted) {
        // 뮤트: 내 토큰을 active_fcm_tokens에서 제거
        batch.update(roomRef, {
          'active_fcm_tokens': FieldValue.arrayRemove(myTokens),
        });
      } else {
        // 뮤트 해제: 내 토큰을 active_fcm_tokens에 다시 추가
        batch.update(roomRef, {
          'active_fcm_tokens': FieldValue.arrayUnion(myTokens),
        });
      }
    }

    await batch.commit();
  }

  // ── 일정 로컬 알림 ─────────────────────────────────────────────────────────
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final notifyTime = scheduledTime.subtract(const Duration(minutes: 15));
    if (notifyTime.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(notifyTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'schedule_channel',
          '일정 알림',
          channelDescription: '일정 시작 15분 전 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> saveFcmTokenOnLogin() async {
    await _saveFcmToken();
  }

  static int notificationId(String scheduleId) =>
      scheduleId.hashCode.abs() % 100000;
}
