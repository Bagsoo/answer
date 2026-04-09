import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_block.dart';

class MemoService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;
  CollectionReference get _memos =>
      _db.collection('users').doc(_uid).collection('memos');

  // ── 메모 목록 스트림 ────────────────────────────────────────────────────────
  Stream<QuerySnapshot> memosStream() =>
      _memos.orderBy('updated_at', descending: true).snapshots();

  // ── 직접 작성 메모 저장/수정 (제목 + 블록 구조) ──────────────────────────
  Future<void> saveMemo({
    String? memoId,
    required String title,       // ← 제목 추가
    required String content,
    required List<PostBlock> blocks,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final now = FieldValue.serverTimestamp();
    final blocksJson = blocks.map((b) => b.toJson()).toList();

    // 미디어 블록 요약 (타일 미리보기용)
    final mediaTypes = blocks
        .where((b) => !b.isText)
        .map((b) => b.type.name)
        .toList();

    if (memoId != null) {
      await _memos.doc(memoId).update({
        'title': title,
        'content': content,
        'blocks': blocksJson,
        'media_types': mediaTypes,   // ← 미리보기용
        'attachments': attachments,
        'updated_at': now,
      });
    } else {
      await _memos.add({
        'title': title,
        'content': content,
        'source': 'direct',
        'blocks': blocksJson,
        'media_types': mediaTypes,
        'attachments': attachments,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ── 채팅 메시지 → 메모 ────────────────────────────────────────────────────
  Future<void> memoFromChat({
    required String content,
    required String groupId,
    required String groupName,
    required String roomId,
    required String roomName,
    required String messageId,
    required String senderName,
    required Timestamp originalSentAt,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final now = FieldValue.serverTimestamp();
    final blocks = _attachmentsToBlocks(content, attachments);
    final mediaTypes = blocks
        .where((b) => !b.isText)
        .map((b) => b.type.name)
        .toList();

    await _memos.add({
      'content': content,
      'source': 'chat',
      'group_id': groupId,
      'group_name': groupName,
      'room_id': roomId,
      'room_name': roomName,
      'message_id': messageId,
      'sender_name': senderName,
      'original_sent_at': originalSentAt,
      'attachments': attachments,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'media_types': mediaTypes,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ── 게시글 → 메모 ─────────────────────────────────────────────────────────
  Future<void> memoFromBoard({
    required String content,
    required String groupId,
    required String groupName,
    required String boardName,
    required String boardType,
    required String postId,
    required String postTitle,
    required String authorName,
    required Timestamp originalCreatedAt,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final now = FieldValue.serverTimestamp();
    final blocks = _attachmentsToBlocks(content, attachments);
    final mediaTypes = blocks
        .where((b) => !b.isText)
        .map((b) => b.type.name)
        .toList();

    await _memos.add({
      'content': content,
      'source': 'board',
      'group_id': groupId,
      'group_name': groupName,
      'board_name': boardName,
      'board_type': boardType,
      'post_id': postId,
      'post_title': postTitle,
      'author_name': authorName,
      'attachments': attachments,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'media_types': mediaTypes,
      'original_created_at': originalCreatedAt,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> memoFromExternal({
    required String title,
    required String content,
    required List<PostBlock> blocks,
    required List<Map<String, dynamic>> attachments,
    required List<String> mediaTypes,
    required String sourceApp,
    required String sharedMimeType,
  }) async {
    final now = FieldValue.serverTimestamp();

    await _memos.add({
      'title': title,
      'content': content,
      'source': 'external',
      'source_app': sourceApp,
      'shared_mime_type': sharedMimeType,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'attachments': attachments,
      'media_types': mediaTypes,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ── 삭제 ──────────────────────────────────────────────────────────────────
  Future<void> deleteMemo(String memoId) async {
    await _memos.doc(memoId).delete();
  }

  // ── Firestore 문서 → PostBlock 리스트 (하위 호환) ────────────────────────
  static List<PostBlock> blocksFromMemo(Map<String, dynamic> data) {
    final rawBlocks = data['blocks'] as List?;
    if (rawBlocks != null && rawBlocks.isNotEmpty) {
      return rawBlocks
          .map((b) => PostBlock.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList();
    }
    final content = data['content'] as String? ?? '';
    final attachments = List<Map<String, dynamic>>.from(
        (data['attachments'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    return _attachmentsToBlocks(content, attachments);
  }

  static List<PostBlock> _attachmentsToBlocks(
      String content, List<Map<String, dynamic>> attachments) {
    final blocks = <PostBlock>[];
    if (content.isNotEmpty) blocks.add(PostBlock.text(content));
    for (final att in attachments) {
      final type = att['type'] as String? ?? 'file';
      switch (type) {
        case 'image':
          blocks.add(PostBlock(type: BlockType.image, data: {
            'url': att['url'], 'name': att['name'] ?? 'image',
            'size': att['size'] ?? 0,
          }));
        case 'video':
          blocks.add(PostBlock(type: BlockType.video, data: {
            'url': att['url'], 'thumbnail_url': att['thumbnail_url'] ?? '',
            'name': att['name'] ?? 'video', 'size': att['size'] ?? 0,
          }));
        case 'audio':
          blocks.add(PostBlock(type: BlockType.audio, data: {
            'url': att['url'], 'name': att['name'] ?? 'audio',
            'size': att['size'] ?? 0, 'mime_type': att['mime_type'] ?? 'audio/mpeg',
          }));
        default:
          blocks.add(PostBlock(type: BlockType.file, data: {
            'url': att['url'], 'name': att['name'] ?? 'file',
            'size': att['size'] ?? 0,
            'mime_type': att['mime_type'] ?? 'application/octet-stream',
          }));
      }
    }
    if (blocks.isEmpty) blocks.add(PostBlock.text());
    return blocks;
  }
}
