import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemoService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;
  CollectionReference get _memos =>
      _db.collection('users').doc(_uid).collection('memos');

  // ── 메모 목록 스트림 ────────────────────────────────────────────────────────
  Stream<QuerySnapshot> memosStream() =>
      _memos.orderBy('updated_at', descending: true).snapshots();

  // ── 직접 작성 메모 저장/수정 (첨부파일 포함) ───────────────────────────────
  Future<void> saveMemo({
    String? memoId,
    required String content,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final now = FieldValue.serverTimestamp();
    if (memoId != null) {
      await _memos.doc(memoId).update({
        'content': content,
        'attachments': attachments,
        'updated_at': now,
      });
    } else {
      await _memos.add({
        'content': content,
        'source': 'direct',
        'attachments': attachments,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ── 채팅 메시지 → 메모 (첨부파일 포함) ───────────────────────────────────
  Future<void> memoFromChat({
    required String content,
    required String groupId,
    required String groupName,
    required String roomId,
    required String roomName,
    required String messageId,
    required String senderName,
    required Timestamp originalSentAt,
    List<Map<String, dynamic>> attachments = const [],  // ← 추가
  }) async {
    final now = FieldValue.serverTimestamp();
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
      'attachments': attachments,   // ← 추가
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
      'original_created_at': originalCreatedAt,
      'created_at': now,
      'updated_at': now,
    });
  }

  // ── 삭제 ──────────────────────────────────────────────────────────────────
  Future<void> deleteMemo(String memoId) async {
    await _memos.doc(memoId).delete();
  }
}