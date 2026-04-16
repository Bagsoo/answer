import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:linkify/linkify.dart';
import 'chat_asset_service.dart';

class _ChatAssetDraft {
  final String docId;
  final String type;
  final Map<String, dynamic> data;

  const _ChatAssetDraft({
    required this.docId,
    required this.type,
    required this.data,
  });
}

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ChatAssetService _chatAssetService = ChatAssetService();
  static const LinkifyOptions _linkifyOptions = LinkifyOptions(
    looseUrl: true,
    defaultToHttps: true,
    humanize: false,
  );

  // 현재 보고 있는 채팅방 ID
  String? currentRoomId;
  
  String get currentUserId => _auth.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> _roomRef(String roomId) =>
      _db.collection('chat_rooms').doc(roomId);

  CollectionReference<Map<String, dynamic>> _messageCollection(String roomId) =>
      _roomRef(roomId).collection('messages');

  CollectionReference<Map<String, dynamic>> _assetCollection(String roomId) =>
      _roomRef(roomId).collection('message_assets');

  List<String> _extractUrls(String text) {
    final elements = linkify(text, options: _linkifyOptions);
    final urls = <String>[];

    for (final element in elements) {
      if (element is! UrlElement) continue;
      final normalized = _normalizeUrl(element.url);
      if (normalized == null || urls.contains(normalized)) continue;
      urls.add(normalized);
    }

    return urls;
  }

  String? _normalizeUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final direct = Uri.tryParse(trimmed);
    if (direct != null && direct.hasScheme) return direct.toString();

    return Uri.tryParse('https://$trimmed')?.toString();
  }

  List<_ChatAssetDraft> _buildAssetDrafts(
    String messageId,
    Map<String, dynamic> messageData,
  ) {
    final createdAt = messageData['created_at'] ?? FieldValue.serverTimestamp();
    final type = messageData['type'] as String? ?? 'text';

    switch (type) {
      case 'image':
        final imageUrls = List<String>.from(
          messageData['image_urls'] as List? ?? [],
        ).where((url) => url.trim().isNotEmpty).toList(growable: false);
        if (imageUrls.isEmpty) return const [];
        return [
          _ChatAssetDraft(
            docId: messageId,
            type: 'image',
            data: {
              'message_id': messageId,
              'type': 'image',
              'bucket': 'media',
              'is_starred': false,
              'created_at': createdAt,
              'primary_url': imageUrls.first,
              'thumb_url': imageUrls.first,
            },
          ),
        ];
      case 'video':
        final videoUrl = (messageData['video_url'] as String? ?? '').trim();
        if (videoUrl.isEmpty) return const [];
        return [
          _ChatAssetDraft(
            docId: messageId,
            type: 'video',
            data: {
              'message_id': messageId,
              'type': 'video',
              'bucket': 'media',
              'is_starred': false,
              'created_at': createdAt,
              'primary_url': videoUrl,
              'thumb_url': (messageData['thumbnail_url'] as String? ?? '').trim(),
            },
          ),
        ];
      case 'file':
        final fileUrl = (messageData['file_url'] as String? ?? '').trim();
        if (fileUrl.isEmpty) return const [];
        return [
          _ChatAssetDraft(
            docId: messageId,
            type: 'file',
            data: {
              'message_id': messageId,
              'type': 'file',
              'bucket': 'file',
              'is_starred': false,
              'created_at': createdAt,
              'primary_url': fileUrl,
              'file_name': (messageData['file_name'] as String? ?? '').trim(),
            },
          ),
        ];
      case 'audio':
        final audioUrl = (messageData['audio_url'] as String? ?? '').trim();
        if (audioUrl.isEmpty) return const [];
        return [
          _ChatAssetDraft(
            docId: messageId,
            type: 'audio',
            data: {
              'message_id': messageId,
              'type': 'audio',
              'bucket': 'file',
              'is_starred': false,
              'created_at': createdAt,
              'primary_url': audioUrl,
              'file_name': (messageData['file_name'] as String? ?? '').trim(),
            },
          ),
        ];
      case 'poll':
        final pollId = (messageData['poll_id'] as String? ?? '').trim();
        if (pollId.isEmpty) return const [];
        return [
          _ChatAssetDraft(
            docId: messageId,
            type: 'poll',
            data: {
              'message_id': messageId,
              'type': 'poll',
              'bucket': 'poll',
              'is_starred': false,
              'created_at': createdAt,
              'poll_id': pollId,
            },
          ),
        ];
      case 'text':
        final urls = _extractUrls(messageData['text'] as String? ?? '');
        return [
          for (var index = 0; index < urls.length; index++)
            _ChatAssetDraft(
              docId: '${messageId}_link_$index',
              type: 'link',
              data: {
                'message_id': messageId,
                'type': 'link',
                'bucket': 'link',
                'is_starred': false,
                'created_at': createdAt,
                'link_url': urls[index],
              },
            ),
        ];
      default:
        return const [];
    }
  }

  Map<String, int> _countAssetDrafts(Iterable<_ChatAssetDraft> drafts) {
    final counts = <String, int>{};
    for (final draft in drafts) {
      counts[draft.type] = (counts[draft.type] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _countAssetDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final counts = <String, int>{};
    for (final doc in docs) {
      final type = (doc.data()['type'] as String? ?? '').trim();
      if (type.isEmpty) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _diffAssetCounts(
    Map<String, int> current,
    Map<String, int> next,
  ) {
    final keys = {...current.keys, ...next.keys};
    final diff = <String, int>{};
    for (final key in keys) {
      final delta = (next[key] ?? 0) - (current[key] ?? 0);
      if (delta != 0) diff[key] = delta;
    }
    return diff;
  }

  void _writeAssetDrafts(
    WriteBatch batch,
    String roomId,
    Iterable<_ChatAssetDraft> drafts,
  ) {
    for (final draft in drafts) {
      batch.set(_assetCollection(roomId).doc(draft.docId), draft.data);
    }
  }

  void _applyAssetCountDelta(
    WriteBatch batch,
    String roomId,
    Map<String, int> deltas,
  ) {
    if (deltas.isEmpty) return;

    final updates = <String, dynamic>{};
    deltas.forEach((type, count) {
      updates['asset_counts.$type'] = FieldValue.increment(count);
    });
    batch.update(_roomRef(roomId), updates);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadMessageAssets(
    String roomId,
    String messageId,
  ) {
    return _assetCollection(roomId).where('message_id', isEqualTo: messageId).get();
  }

  Future<bool> _isLatestMessage(String roomId, String messageId) async {
    final lastSnap = await _messageCollection(roomId)
        .orderBy('created_at', descending: true)
        .limit(1)
        .get();
    return lastSnap.docs.isNotEmpty && lastSnap.docs.first.id == messageId;
  }

  Future<void> _commitMessage(
    String roomId, {
    required DocumentReference<Map<String, dynamic>> msgRef,
    required Map<String, dynamic> msgData,
    required String lastMessage,
  }) async {
    final unreadUpdate = await _buildUnreadUpdate(roomId);
    final drafts = _buildAssetDrafts(msgRef.id, msgData);
    final batch = _db.batch();

    batch.set(msgRef, msgData);
    _writeAssetDrafts(batch, roomId, drafts);
    _applyAssetCountDelta(batch, roomId, _countAssetDrafts(drafts));
    batch.update(_roomRef(roomId), {
      'last_message': lastMessage,
      'last_time': FieldValue.serverTimestamp(),
      ...unreadUpdate,
    });

    await batch.commit();
    _chatAssetService.invalidateRoom(roomId);
  }

  // ── 채팅방 목록 ────────────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getChatRooms({
    String? refGroupId,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('chat_rooms')
        .where('member_ids', arrayContains: currentUserId);

    if (refGroupId != null) {
      query = query.where('ref_group_id', isEqualTo: refGroupId);
    }

    return query.snapshots().map((snapshot) {
      final rooms = snapshot.docs.map((doc) {
        final data = {...doc.data(), 'id': doc.id};
        final unreadCounts =
            data['unread_counts'] as Map<String, dynamic>? ?? {};
        data['unread_cnt'] = unreadCounts[currentUserId] as int? ?? 0;
        return data;
      }).toList();

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
    final msgRef = _messageCollection(roomId).doc();

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

    await _commitMessage(
      roomId,
      msgRef: msgRef,
      msgData: msgData,
      lastMessage: text,
    );
  }

  // ── 이미지 메시지 전송 ─────────────────────────────────────────────────────
  Future<void> sendImageMessage(
    String roomId, {
    required String messageId,
    required List<String> imageUrls,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final msgRef = _messageCollection(roomId).doc(messageId);
    final msgData = <String, dynamic>{
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'image',
      'image_urls': imageUrls,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    };

    final lastMsg = imageUrls.length > 1
        ? '📷 사진 ${imageUrls.length}장'
        : '📷 사진';

    await _commitMessage(
      roomId,
      msgRef: msgRef,
      msgData: msgData,
      lastMessage: lastMsg,
    );
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
    final msgRef = _messageCollection(roomId).doc(messageId);
    final msgData = <String, dynamic>{
      'sender_id': currentUserId,
      'sender_name': senderName,
      'sender_photo_url': senderPhotoUrl ?? '',
      'text': '',
      'type': 'video',
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    };

    await _commitMessage(
      roomId,
      msgRef: msgRef,
      msgData: msgData,
      lastMessage: '🎥 동영상',
    );
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
    final msgRef = _messageCollection(roomId).doc(messageId);
    final msgData = <String, dynamic>{
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
    };

    await _commitMessage(
      roomId,
      msgRef: msgRef,
      msgData: msgData,
      lastMessage: 'file',
    );
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
    final msgRef = _messageCollection(roomId).doc(messageId);
    final msgData = <String, dynamic>{
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
    };

    await _commitMessage(
      roomId,
      msgRef: msgRef,
      msgData: msgData,
      lastMessage: 'audio',
    );
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

  Future<void> sendSettlementMessage(
    String roomId, {
    required String groupId,
    required String groupName,
    required String settlementId,
    required String title,
    required String totalCost,
    required String bankInfo,
    required String creatorUid,
    required List<dynamic> participants,
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
      'sender_name': FirebaseAuth.instance.currentUser?.displayName ?? '',
      'sender_photo_url': FirebaseAuth.instance.currentUser?.photoURL ?? '',
      'text': '',
      'type': 'settlement',
      'group_id': groupId,
      'group_name': groupName,
      'settlement_id': settlementId,
      'settlement_title': title,
      'settlement_total_cost': totalCost,
      'settlement_bank_info': bankInfo,
      'settlement_creator_uid': creatorUid,
      'settlement_participants': participants,
      'is_system': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    batch.update(_db.collection('chat_rooms').doc(roomId), {
      'last_message': '💸 $title',
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

  Future<void> hideMessage(
    String roomId,
    String messageId, {
    required String hiddenBy,
    required String replacementLastMessage,
  }) async {
    final existingAssets = await _loadMessageAssets(roomId, messageId);
    final batch = _db.batch();

    batch.update(_messageCollection(roomId).doc(messageId), {
      'is_system': true,
      'is_hidden': true,
      'hidden_by': hiddenBy,
      'hidden_at': FieldValue.serverTimestamp(),
    });

    for (final assetDoc in existingAssets.docs) {
      batch.delete(assetDoc.reference);
    }
    _applyAssetCountDelta(
      batch,
      roomId,
      _countAssetDocs(existingAssets.docs).map(
        (type, count) => MapEntry(type, -count),
      ),
    );

    if (await _isLatestMessage(roomId, messageId)) {
      batch.update(_roomRef(roomId), {'last_message': replacementLastMessage});
    }

    await batch.commit();
    _chatAssetService.invalidateRoom(roomId);
  }

  Future<void> softDeleteMessage(
    String roomId,
    String messageId, {
    required String replacementLastMessage,
  }) async {
    final existingAssets = await _loadMessageAssets(roomId, messageId);
    final batch = _db.batch();

    batch.update(_messageCollection(roomId).doc(messageId), {
      'is_deleted': true,
      'deleted_at': FieldValue.serverTimestamp(),
    });

    for (final assetDoc in existingAssets.docs) {
      batch.delete(assetDoc.reference);
    }
    _applyAssetCountDelta(
      batch,
      roomId,
      _countAssetDocs(existingAssets.docs).map(
        (type, count) => MapEntry(type, -count),
      ),
    );

    if (await _isLatestMessage(roomId, messageId)) {
      batch.update(_roomRef(roomId), {'last_message': replacementLastMessage});
    }

    await batch.commit();
    _chatAssetService.invalidateRoom(roomId);
  }

  Future<void> editTextMessage(
    String roomId,
    String messageId, {
    required String newText,
  }) async {
    final messageSnap = await _messageCollection(roomId).doc(messageId).get();
    final messageData = messageSnap.data();
    if (messageData == null) return;

    final existingAssets = await _loadMessageAssets(roomId, messageId);
    final nextDrafts = _buildAssetDrafts(
      messageId,
      {...messageData, 'text': newText},
    );
    final countDelta = _diffAssetCounts(
      _countAssetDocs(existingAssets.docs),
      _countAssetDrafts(nextDrafts),
    );

    final batch = _db.batch();
    batch.update(_messageCollection(roomId).doc(messageId), {
      'text': newText,
      'edited': true,
      'updated_at': FieldValue.serverTimestamp(),
    });

    for (final assetDoc in existingAssets.docs) {
      batch.delete(assetDoc.reference);
    }
    _writeAssetDrafts(batch, roomId, nextDrafts);
    _applyAssetCountDelta(batch, roomId, countDelta);

    if (await _isLatestMessage(roomId, messageId)) {
      batch.update(_roomRef(roomId), {'last_message': newText});
    }

    await batch.commit();
    _chatAssetService.invalidateRoom(roomId);
  }
}
