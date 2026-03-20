import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ── 전화번호로 유저 검색 ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> searchByPhone(String phoneNumber) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return null;

    String normalized;
    if (cleaned.startsWith('+')) {
      normalized = cleaned;
    } else if (cleaned.startsWith('0')) {
      normalized = '+82${cleaned.substring(1)}';
    } else {
      normalized = cleaned;
    }

    final snap = await _db
        .collection('users')
        .where('phone_number', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    if (doc.id == currentUserId) return null;

    final data = doc.data();
    data['uid'] = doc.id;
    return data;
  }

  // ── 친구 추가 ─────────────────────────────────────────────────────────────
  // profile_image 파라미터 추가 — 양쪽 friends 서브컬렉션에 저장
  Future<bool> addFriend(
    String friendUid,
    String friendName, {
    required String myName,
    String myPhoneNumber = '',
    String myProfileImage = '',       // ← 추가: 내 프로필 사진
    String friendPhoneNumber = '',
    String friendProfileImage = '',   // ← 추가: 상대방 프로필 사진
  }) async {
    if (currentUserId.isEmpty) return false;
    try {
      final existing = await _db
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .doc(friendUid)
          .get();
      if (existing.exists) return false;

      final batch = _db.batch();

      // 내 friends에 상대방 저장 (상대방 프로필 사진 포함)
      batch.set(
        _db
            .collection('users')
            .doc(currentUserId)
            .collection('friends')
            .doc(friendUid),
        {
          'uid': friendUid,
          'display_name': friendName,
          'phone_number': friendPhoneNumber,
          'profile_image': friendProfileImage, // ← 추가
          'added_at': FieldValue.serverTimestamp(),
        },
      );

      // 상대방 friends에 나 저장 (내 프로필 사진 포함)
      batch.set(
        _db
            .collection('users')
            .doc(friendUid)
            .collection('friends')
            .doc(currentUserId),
        {
          'uid': currentUserId,
          'display_name': myName,
          'phone_number': myPhoneNumber,
          'profile_image': myProfileImage, // ← 추가
          'added_at': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('addFriend error: $e');
      return false;
    }
  }

  // ── 친구 삭제 ─────────────────────────────────────────────────────────────
  Future<void> removeFriend(String friendUid) async {
    final batch = _db.batch();
    batch.delete(
      _db
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .doc(friendUid),
    );
    batch.delete(
      _db
          .collection('users')
          .doc(friendUid)
          .collection('friends')
          .doc(currentUserId),
    );
    await batch.commit();
  }

  // ── 친구 목록 스트림 ──────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getFriends() {
    if (currentUserId.isEmpty) return Stream.value([]);
    return _db
        .collection('users')
        .doc(currentUserId)
        .collection('friends')
        .orderBy('added_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['uid'] = doc.id;
              return data;
            }).toList());
  }

  // ── 친구 여부 확인 ────────────────────────────────────────────────────────
  Future<bool> isFriend(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(currentUserId)
        .collection('friends')
        .doc(uid)
        .get();
    return doc.exists;
  }

  // ── DM 채팅방 가져오기 or 생성 ────────────────────────────────────────────
  Future<String> getOrCreateDmRoom(
    String friendUid,
    String friendName, {
    required String myName,
  }) async {
    final ids = [currentUserId, friendUid]..sort();
    final dmKey = '${ids[0]}_${ids[1]}';

    final existing = await _db
        .collection('chat_rooms')
        .where('dm_key', isEqualTo: dmKey)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final batch = _db.batch();
    final roomRef = _db.collection('chat_rooms').doc();

    batch.set(roomRef, {
      'type': 'direct',
      'dm_key': dmKey,
      'ref_group_id': null,
      'name': friendName,
      'member_ids': [currentUserId, friendUid],
      'last_message': '',
      'last_time': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'unread_counts': {currentUserId: 0, friendUid: 0},
    });

    batch.set(roomRef.collection('room_members').doc(currentUserId), {
      'uid': currentUserId,
      'display_name': myName,
      'role': 'member',
      'joined_at': FieldValue.serverTimestamp(),
      'last_read_time': FieldValue.serverTimestamp(),
      'unread_cnt': 0,
    });

    batch.set(roomRef.collection('room_members').doc(friendUid), {
      'uid': friendUid,
      'display_name': friendName,
      'role': 'member',
      'joined_at': FieldValue.serverTimestamp(),
      'last_read_time': FieldValue.serverTimestamp(),
      'unread_cnt': 0,
    });

    await batch.commit();
    return roomRef.id;
  }

  // ── 단체톡방 생성 ──────────────────────────────────────────────────────────
  Future<String> createGroupDirectRoom({
    required String roomName,
    required List<String> memberUids,
    required List<String> memberNames,
    required String myName,
  }) async {
    if (currentUserId.isEmpty) return '';

    final allUids = [currentUserId, ...memberUids];
    final allNames = [myName, ...memberNames];

    final roomRef = _db.collection('chat_rooms').doc();
    final batch = _db.batch();

    batch.set(roomRef, {
      'type': 'group_direct',
      'name': roomName.isNotEmpty ? roomName : allNames.take(4).join(', '),
      'member_ids': allUids,
      'last_message': '',
      'last_time': FieldValue.serverTimestamp(),
      'ref_group_id': null,
      'created_by': currentUserId,
      'created_at': FieldValue.serverTimestamp(),
      'member_limit': 100,
      'unread_counts': {for (final uid in allUids) uid: 0},
    });

    for (int i = 0; i < allUids.length; i++) {
      final uid = allUids[i];
      batch.set(roomRef.collection('room_members').doc(uid), {
        'uid': uid,
        'display_name': allNames[i],
        'role': 'member',
        'joined_at': FieldValue.serverTimestamp(),
        'last_read_time': FieldValue.serverTimestamp(),
        'unread_cnt': 0,
        'notification_muted': false,
      });
    }

    await batch.commit();

    final names = allNames.take(4).join(', ');
    final suffix =
        allNames.length > 4 ? ' 외 ${allNames.length - 4}명' : '';
    await roomRef.collection('messages').add({
      'text': '$names$suffix 님이 채팅방에 입장했습니다.',
      'is_system': true,
      'created_at': FieldValue.serverTimestamp(),
    });

    return roomRef.id;
  }
}