import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ── 채팅방 목록 (비동기 없음, 단일 쿼리) ────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getChatRooms() {
    return _db
        .collection('chat_rooms')
        .where('member_ids', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
      final rooms = snapshot.docs.map((doc) {
        final data = {...doc.data(), 'id': doc.id};

        // unread_counts 맵에서 내 카운트만 추출
        final unreadCounts = data['unread_counts'] as Map<String, dynamic>? ?? {};
        data['unread_cnt'] = unreadCounts[currentUserId] as int? ?? 0;

        return data;
      }).toList();

      // last_time 기준 내림차순 정렬
      rooms.sort((a, b) {
        final aTime = a['last_time'] as Timestamp?;
        final bTime = b['last_time'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return rooms;
    });
  }

  // ── 메시지 스트림 (최신 30개, 실시간) ────────────────────────────────────────
  Stream<QuerySnapshot> getMessages(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();
  }

  // ── 이전 메시지 추가 로드 (페이지네이션) ────────────────────────────────────
  Future<List<QueryDocumentSnapshot>> loadMoreMessages(
    String roomId,
    DocumentSnapshot lastDoc, {
    int pageSize = 30,
  }) async {
    final snap = await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .startAfterDocument(lastDoc)
        .limit(pageSize)
        .get();
    return snap.docs;
  }

  // ── 채팅방 멤버 스트림 ────────────────────────────────────────────────────────
  Stream<QuerySnapshot> getRoomMembers(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .snapshots();
  }

  // ── 메시지 전송 ───────────────────────────────────────────────────────────────
  Future<void> sendMessage(
    String roomId,
    String text, {
    required String senderName,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    String? pollId,
  }) async {
    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    final memberIds = List<String>.from(roomDoc.data()?['member_ids'] ?? []);

    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    final msgData = <String, dynamic>{
      'sender_id': currentUserId,
      'sender_name': senderName,
      'text': text,
      'type': pollId != null ? 'poll' : 'text',
      'is_system': pollId != null,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (replyToId != null) {
      msgData['reply_to_id'] = replyToId;
      msgData['reply_to_text'] = replyToText ?? '';
      msgData['reply_to_sender'] = replyToSender ?? '';
    }
    if (pollId != null) {
      msgData['poll_id'] = pollId;
    }

    batch.set(msgRef, msgData);

    // 채팅방 last_message + unread_counts 업데이트
    // 나를 제외한 모든 멤버의 카운트를 +1
    final unreadUpdate = <String, dynamic>{};
    for (final uid in memberIds) {
      if (uid == currentUserId) continue;
      unreadUpdate['unread_counts.$uid'] = FieldValue.increment(1);
    }

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': text,
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 읽음 처리 (내 unread_count 초기화) ──────────────────────────────────────
  Future<void> updateLastReadTime(String roomId) async {
    final batch = _db.batch();

    // room_members 업데이트 (last_read_time, unread_cnt)
    final memberRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .doc(currentUserId);
    batch.set(memberRef, {
      'user_id': currentUserId,
      'last_read_time': FieldValue.serverTimestamp(),
      'unread_cnt': 0,
    }, SetOptions(merge: true));

    // chat_rooms 문서의 unread_counts 초기화
    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'unread_counts.$currentUserId': 0,
    });

    await batch.commit();
  }
}