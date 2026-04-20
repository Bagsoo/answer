import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

enum NotificationType {
  invite,
  friendRequest,
  system,
}

class UserNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? expiresAt;

  UserNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    this.isRead = false,
    required this.createdAt,
    this.expiresAt,
  });

  factory UserNotification.fromFirestore(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;
    return UserNotification(
      id: doc.id,
      type: NotificationType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => NotificationType.system,
      ),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      data: map['data'] ?? {},
      isRead: map['is_read'] ?? false,
      createdAt: (map['created_at'] as Timestamp).toDate(),
      expiresAt: map['expires_at'] != null 
          ? (map['expires_at'] as Timestamp).toDate() 
          : null,
    );
  }
}

class UserNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  // ── 알림 목록 스트림 (최신순 정렬) ───────────────────────────
  Stream<List<UserNotification>> getNotifications() {
    if (_uid.isEmpty) return Stream.value([]);
    
    return _db
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('expires_at', isGreaterThan: DateTime.now())
        .orderBy('expires_at', descending: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => UserNotification.fromFirestore(doc)).toList());
  }

  // ── 읽지 않은 알림 존재 여부 스트림 (배지용) ───────────────────────────
  Stream<bool> hasUnreadNotifications() {
    if (_uid.isEmpty) return Stream.value(false);
    
    return _db
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('is_read', isEqualTo: false)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  // ── 알림 읽음 처리 ───────────────────────────────────────────────────
  Future<void> markAsRead(String notificationId) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'is_read': true});
  }

  // ── 그룹 초대 보내기 ──────────────────────────────────────────────────
  Future<void> sendGroupInvite({
    required String targetUid,
    required String groupId,
    required String groupName,
    required String inviterName,
    String? groupPhotoUrl,
  }) async {
    final inviteId = 'invite_$groupId';
    final ref = _db.collection('users').doc(targetUid).collection('notifications').doc(inviteId);
    final expiresAt = DateTime.now().add(const Duration(days: 7));

    await ref.set({
      'type': NotificationType.invite.name,
      'title': '그룹 초대',
      'body': '$inviterName님이 $groupName 그룹에 초대했습니다.',
      'data': {
        'group_id': groupId,
        'group_name': groupName,
        'group_photo_url': groupPhotoUrl ?? '',
        'inviter_uid': _uid,
        'inviter_name': inviterName,
      },
      'is_read': false,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(expiresAt),
    }, SetOptions(merge: true));
  }

  // ── 초대 수락 (Cloud Function 호출) ───────────────────────────
  Future<bool> acceptInvite(UserNotification notification) async {
    final groupId = notification.data['group_id'];
    if (groupId == null || _uid.isEmpty) return false;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable('acceptInviteV2');
      await callable.call({
        'notiId': notification.id,
        'groupId': groupId,
      });
      return true;
    } catch (e) {
      debugPrint('acceptInvite error: $e');
      return false;
    }
  }

  // ── 초대 거절 ───────────────────────────────────────────────────────
  Future<void> rejectInvite(String notificationId) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .delete();
  }
}
