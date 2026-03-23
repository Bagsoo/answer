import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/post_block.dart';

class BoardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── 게시글 스트림 ──────────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getPosts(
      String groupId, String boardId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .where('board_id', isEqualTo: boardId)
        .orderBy('is_pinned', descending: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Stream<Map<String, dynamic>?> getPost(String groupId, String postId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final data = snap.data()!;
      data['id'] = snap.id;
      return data;
    });
  }

  // ── 게시글 생성 (블록 구조) ────────────────────────────────────────────────
  Future<String?> createPost({
    required String groupId,
    required String boardId,
    required String boardName,
    required String boardType,
    required String title,
    required List<PostBlock> blocks,
    required String authorId,
    required String authorName,
  }) async {
    try {
      // 하위 호환: content 필드는 text 블록들을 이어붙인 plain text
      final plainText = blocks
          .where((b) => b.isText)
          .map((b) => b.textValue)
          .join('\n')
          .trim();

      final ref = _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc();

      await ref.set({
        'board_id': boardId,
        'board_name': boardName,
        'board_type': boardType,
        'title': title,
        'content': plainText,         // 하위 호환용
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'author_id': authorId,
        'author_name': authorName,
        'attachments': [],            // 하위 호환용 (빈 배열)
        'is_pinned': false,
        'reactions': {},
        'comment_count': 0,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (e) {
      debugPrint('createPost error: $e');
      return null;
    }
  }

  // ── 게시글 수정 (블록 구조) ────────────────────────────────────────────────
  Future<bool> updatePost({
    required String groupId,
    required String postId,
    required String title,
    required List<PostBlock> blocks,
  }) async {
    try {
      final plainText = blocks
          .where((b) => b.isText)
          .map((b) => b.textValue)
          .join('\n')
          .trim();

      await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .update({
        'title': title,
        'content': plainText,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('updatePost error: $e');
      return false;
    }
  }

  // ── 게시글 삭제 ───────────────────────────────────────────────────────────
  Future<bool> deletePost(String groupId, String postId) async {
    try {
      final commentsSnap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();
      final batch = _db.batch();
      for (final doc in commentsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('deletePost error: $e');
      return false;
    }
  }

  // ── 고정/해제 ─────────────────────────────────────────────────────────────
  Future<bool> togglePinPost(
      String groupId, String postId, bool currentPin) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .update({'is_pinned': !currentPin});
      return true;
    } catch (e) {
      debugPrint('togglePinPost error: $e');
      return false;
    }
  }

  // ── 반응 토글 ─────────────────────────────────────────────────────────────
  Future<void> toggleReaction(
      String groupId, String postId, String emoji) async {
    final ref = _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId);
    final snap = await ref.get();
    final reactions = Map<String, dynamic>.from(
        snap.data()?['reactions'] as Map? ?? {});
    if (reactions[currentUserId] == emoji) {
      reactions.remove(currentUserId);
    } else {
      reactions[currentUserId] = emoji;
    }
    await ref.update({'reactions': reactions});
  }

  // ── 댓글 스트림 ───────────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getComments(
      String groupId, String postId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // ── 댓글 추가 ─────────────────────────────────────────────────────────────
  Future<bool> addComment(String groupId, String postId, String content,
      String authorName) async {
    try {
      final batch = _db.batch();
      final commentRef = _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc();
      batch.set(commentRef, {
        'content': content,
        'author_id': currentUserId,
        'author_name': authorName,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('posts')
            .doc(postId),
        {'comment_count': FieldValue.increment(1)},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('addComment error: $e');
      return false;
    }
  }

  // ── 댓글 삭제 ─────────────────────────────────────────────────────────────
  Future<bool> deleteComment(
      String groupId, String postId, String commentId) async {
    try {
      final batch = _db.batch();
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId));
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('posts')
            .doc(postId),
        {'comment_count': FieldValue.increment(-1)},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('deleteComment error: $e');
      return false;
    }
  }

  // ── Firestore → PostBlock 리스트 변환 (하위 호환 포함) ────────────────────
  static List<PostBlock> blocksFromPost(Map<String, dynamic> post) {
    // 새 포맷: blocks 필드 있으면 우선 사용
    final rawBlocks = post['blocks'] as List?;
    if (rawBlocks != null && rawBlocks.isNotEmpty) {
      return rawBlocks
          .map((b) => PostBlock.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList();
    }

    // 구 포맷 하위 호환: content + attachments → 블록으로 변환
    final blocks = <PostBlock>[];
    final content = post['content'] as String? ?? '';
    if (content.isNotEmpty) blocks.add(PostBlock.text(content));

    final attachments =
        List<Map<String, dynamic>>.from(post['attachments'] as List? ?? []);
    for (final att in attachments) {
      final type = att['type'] as String? ?? 'file';
      switch (type) {
        case 'image':
          blocks.add(PostBlock(type: BlockType.image, data: {
            'url': att['url'],
            'name': att['name'],
            'size': att['size'],
          }));
        case 'video':
          blocks.add(PostBlock(type: BlockType.video, data: {
            'url': att['url'],
            'thumbnail_url': att['thumbnail_url'],
            'name': att['name'],
            'size': att['size'],
          }));
        case 'audio':
          blocks.add(PostBlock(type: BlockType.audio, data: {
            'url': att['url'],
            'name': att['name'],
            'size': att['size'],
            'mime_type': att['mime_type'],
          }));
        default:
          blocks.add(PostBlock(type: BlockType.file, data: {
            'url': att['url'],
            'name': att['name'],
            'size': att['size'],
            'mime_type': att['mime_type'],
          }));
      }
    }

    if (blocks.isEmpty) blocks.add(PostBlock.text());
    return blocks;
  }
}