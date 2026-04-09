import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 현재 보고 있는 채팅방 ID
  String? currentRoomId;
  
  String get currentUserId => _auth.currentUser?.uid ?? '';

  Future<List<String>> _loadSearchMemberNames(
    DocumentReference<Map<String, dynamic>> roomRef,
    Map<String, dynamic> roomData,
  ) async {
    final membersSnap = await roomRef.collection('room_members').get();
    final names = membersSnap.docs
        .map((member) => member.data()['display_name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final memberIds = List<String>.from(roomData['member_ids'] as List? ?? []);
    if (memberIds.isNotEmpty) {
      final userSnaps = await Future.wait(
        memberIds.map((uid) => _db.collection('users').doc(uid).get()),
      );
      for (final userDoc in userSnaps) {
        final userName = userDoc.data()?['name'] as String? ?? '';
        if (userName.isNotEmpty && !names.contains(userName)) {
          names.add(userName);
        }
      }
    }

    return names;
  }

  // ── 채팅방 목록 ────────────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getChatRooms({
    String? refGroupId,
    bool includeSearchMembers = false,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('chat_rooms')
        .where('member_ids', arrayContains: currentUserId);

    if (refGroupId != null) {
      query = query.where('ref_group_id', isEqualTo: refGroupId);
    }

    return query.snapshots().asyncMap((snapshot) async {
      final rooms = await Future.wait(snapshot.docs.map((doc) async {
        final data = {...doc.data(), 'id': doc.id};
        final unreadCounts =
            data['unread_counts'] as Map<String, dynamic>? ?? {};
        data['unread_cnt'] = unreadCounts[currentUserId] as int? ?? 0;

        if (includeSearchMembers) {
          final searchNames = await _loadSearchMemberNames(doc.reference, data);
          final name = data['name'] as String? ?? '';
          if (name.isNotEmpty && !searchNames.contains(name)) {
            searchNames.add(name);
          }
          data['search_member_names'] = searchNames;
        }

        return data;
      }));

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

  // ── 전체 읽지 않은 메시지 수 스트림 ──────────────────────────────────────
  Stream<int> totalUnreadStream() {
    if (currentUserId.isEmpty) return Stream.value(0);
    return _db
        .collection('chat_rooms')
        .where('member_ids', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
      int total = 0;
      for (final doc in snapshot.docs) {
        final unreadCounts =
            doc.data()['unread_counts'] as Map<String, dynamic>? ?? {};
        total += (unreadCounts[currentUserId] as int? ?? 0);
      }
      return total;
    });
  }

  // ── 메시지 스트림 (최신 30개) ──────────────────────────────────────────────
  Stream<QuerySnapshot> getMessages(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();
  }

  // ── 이전 메시지 페이지네이션 ───────────────────────────────────────────────
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

  // ── 채팅방 멤버 스트림 ─────────────────────────────────────────────────────
  Stream<QuerySnapshot> getRoomMembers(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .snapshots();
  }

  // ── 메시지 ID 미리 생성 ───────────────────────────────────────────────────
  String generateMessageId(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc()
        .id;
  }

  // ── 공통: unread_counts 증가 맵 생성 ──────────────────────────────────────
  Future<Map<String, dynamic>> _buildUnreadUpdate(String roomId) async {
    final roomDoc = await _db.collection('chat_rooms').doc(roomId).get();
    final memberIds =
        List<String>.from(roomDoc.data()?['member_ids'] ?? []);

    final unreadUpdate = <String, dynamic>{};
    for (final uid in memberIds) {
      if (uid == currentUserId) continue;
      unreadUpdate['unread_counts.$uid'] = FieldValue.increment(1);
    }
    return unreadUpdate;
  }

  // ── 텍스트 메시지 전송 ─────────────────────────────────────────────────────
  Future<void> sendMessage(
    String roomId,
    String text, {
    required String senderName,
    String? senderPhotoUrl,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    String? pollId,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    final msgData = <String, dynamic>{
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
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
    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': text,
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 이미지 메시지 전송 ─────────────────────────────────────────────────────
  Future<void> sendImageMessage(
    String roomId, {
    required String messageId,
    required List<String> imageUrls,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'image',
      'image_urls': imageUrls,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    final lastMsg = imageUrls.length > 1
        ? '📷 사진 ${imageUrls.length}장'
        : '📷 사진';

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': lastMsg,
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 동영상 메시지 전송 ─────────────────────────────────────────────────────
  Future<void> sendVideoMessage(
    String roomId, {
    required String messageId,
    required String videoUrl,
    required String thumbnailUrl,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'video',
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': '🎥 동영상',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 파일 메시지 전송 ───────────────────────────────────────────────────────
  Future<void> sendFileMessage(
    String roomId, {
    required String messageId,
    required String fileUrl,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'file',
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': 'file',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 연락처(프로필 카드) 메시지 전송 ───────────────────────────────────────
  Future<void> sendContactMessage(
    String roomId, {
    required String sharedUserId,
    required String sharedUserName,
    required String sharedUserPhotoUrl,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'contact',
      'shared_user_id': sharedUserId,
      'shared_user_name': sharedUserName,
      'shared_user_photo_url': sharedUserPhotoUrl,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': 'contact',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 음성 메시지 전송 ───────────────────────────────────────────────────────
  Future<void> sendAudioMessage(
    String roomId, {
    required String messageId,
    required String audioUrl,
    required int durationMs,
    required String fileName,
    required String mimeType,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'audio',
      'audio_url': audioUrl,
      'audio_duration_ms': durationMs,
      'file_name': fileName,
      'mime_type': mimeType,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': 'audio',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  Future<void> sendSharedPostMessage(
    String roomId, {
    required String groupId,
    required String groupName,
    required String boardId,
    required String boardName,
    required String boardType,
    required String postId,
    required String postTitle,
    required String postContent,
    required String authorName,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'shared_post',
      'group_id': groupId,
      'group_name': groupName,
      'board_id': boardId,
      'board_name': boardName,
      'board_type': boardType,
      'post_id': postId,
      'post_title': postTitle,
      'post_content': postContent,
      'post_author_name': authorName,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': '📝 $postTitle',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  Future<void> sendSharedScheduleMessage(
    String roomId, {
    required String groupId,
    required String groupName,
    required String scheduleId,
    required String title,
    required String description,
    required Timestamp? startTime,
    required Timestamp? endTime,
    required String locationName,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'shared_schedule',
      'group_id': groupId,
      'group_name': groupName,
      'schedule_id': scheduleId,
      'schedule_title': title,
      'schedule_description': description,
      'schedule_start_time': startTime,
      'schedule_end_time': endTime,
      'schedule_location_name': locationName,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': '📅 $title',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  Future<void> sendSharedMemoMessage(
    String roomId, {
    required String title,
    required String content,
    required String source,
    required String groupName,
    required String roomName,
    required String boardName,
    required String postTitle,
    required String senderName,
    required String sourceSenderName,
    required String authorName,
    required List<Map<String, dynamic>> attachments,
    required List<dynamic> blocks,
    required List<String> mediaTypes,
    String? senderPhotoUrl,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final batch = _db.batch();

    final msgRef = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .doc();

    batch.set(msgRef, {
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'shared_memo',
      'memo_title': title,
      'memo_content': content,
      'memo_source': source,
      'memo_group_name': groupName,
      'memo_room_name': roomName,
      'memo_board_name': boardName,
      'memo_post_title': postTitle,
      'memo_sender_name': sourceSenderName,
      'memo_author_name': authorName,
      'memo_attachments': attachments,
      'memo_blocks': blocks,
      'memo_media_types': mediaTypes,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    final preview = title.trim().isNotEmpty ? title.trim() : content.trim();
    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': '🗒 ${preview.isNotEmpty ? preview : '메모'}',
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
  }

  // ── 읽음 처리 ─────────────────────────────────────────────────────────────
  Future<void> updateLastReadTime(String roomId) async {
    final batch = _db.batch();

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

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'unread_counts.$currentUserId': 0,
    });

    await batch.commit();
  }
}
