import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드에서는 FCM이 자동으로 알림 표시
  debugPrint('Background FCM: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

    // 1. 로컬 알림 플러그인 초기화
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 2. Android 알림 채널 생성
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_chatChannel);
    await androidPlugin?.createNotificationChannel(_scheduleChannel);
    await androidPlugin?.createNotificationChannel(_joinRequestChannel);
    await androidPlugin?.createNotificationChannel(_marketingChannel);
    await androidPlugin?.requestNotificationsPermission();

    // 3. FCM 권한 요청
    final settings2 = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings2.authorizationStatus}');

    // 4. 백그라운드 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 5. 포그라운드 메시지 수신 처리
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. 앱이 백그라운드에서 열릴 때
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 7. FCM 토큰 저장
    await _saveFcmToken();

    // 8. 토큰 갱신 시 자동 업데이트
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

    final platform = Platform.isAndroid ? 'android' : 'ios';
    // 토큰을 doc ID로 사용해서 중복 저장 방지
    await _db
        .collection('users')
        .doc(uid)
        .collection('fcm_tokens')
        .doc(token.substring(0, 20)) // 토큰 앞 20자를 ID로
        .set({
      'token': token,
      'platform': platform,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  // 로그아웃 시 토큰 삭제 호출
  Future<void> deleteFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
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
    final notification = message.notification;
    final data = message.data;
    if (notification == null) return;

    final channelId = _channelIdFromData(data);

    await _plugin.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelNameFromId(channelId),
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: _payloadFromData(data),
    );
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    // TODO: 딥링크 처리 (채팅방, 그룹 설정 등으로 이동)
    debugPrint('Opened from notification: ${message.data}');
  }

  void _onNotificationTap(NotificationResponse response) {
    // 로컬 알림 탭 처리
    debugPrint('Notification tapped: ${response.payload}');
  }

  String _channelIdFromData(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'chat':         return 'chat_channel';
      case 'join_request': return 'join_request_channel';
      case 'schedule':     return 'schedule_channel';
      case 'marketing':    return 'marketing_channel';
      default:             return 'chat_channel';
    }
  }

  String _channelNameFromId(String id) {
    switch (id) {
      case 'chat_channel':         return '채팅 알림';
      case 'join_request_channel': return '가입 요청 알림';
      case 'schedule_channel':     return '일정 알림';
      case 'marketing_channel':    return '마케팅 알림';
      default:                     return '알림';
    }
  }

  String _payloadFromData(Map<String, dynamic> data) {
    // 예: "chat|roomId", "group|groupId"
    final type = data['type'] ?? '';
    final id = data['roomId'] ?? data['groupId'] ?? '';
    return '$type|$id';
  }

  // ── 알림 설정 로드 / 저장 ──────────────────────────────────────────────────
  Future<Map<String, bool>> loadNotificationSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _defaultSettings();

    final doc = await _db.collection('users').doc(uid).get();
    final raw = doc.data()?['notification_settings'] as Map<String, dynamic>?;
    if (raw == null) return _defaultSettings();

    return {
      'chat_message':  raw['chat_message']  as bool? ?? true,
      'join_request':  raw['join_request']  as bool? ?? true,
      'new_schedule':  raw['new_schedule']  as bool? ?? true,
      'marketing':     raw['marketing']     as bool? ?? false,
    };
  }

  Future<void> saveNotificationSettings(Map<String, bool> settings) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'notification_settings': settings,
    });
  }

  Map<String, bool> _defaultSettings() => {
    'chat_message': true,
    'join_request': true,
    'new_schedule': true,
    'marketing':    false,
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

  Future<void> setGroupNotificationEnabled(String groupId, bool enabled) async {
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
    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .doc(uid)
        .update({'notification_muted': muted});
  }

  // ── 일정 로컬 알림 (기존 유지) ─────────────────────────────────────────────
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
          'schedule_channel', '일정 알림',
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

  static int notificationId(String scheduleId) =>
      scheduleId.hashCode.abs() % 100000;
}