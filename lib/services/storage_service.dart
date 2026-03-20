import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── 채팅 단일 이미지 업로드 ────────────────────────────────────────────────
  Future<String> uploadChatImage({
    required String roomId,
    required String messageId,
    required File file,
  }) async {
    final ref = _storage.ref(
      'chat_rooms/$roomId/images/$messageId.jpg',
    );
    try {
      final task = await ref.putFile(
          file, SettableMetadata(contentType: 'image/jpeg'));
      return await task.ref.getDownloadURL();
    } catch (e) {
      throw Exception('이미지 업로드 실패: $e');
    }
  }

  // ── 채팅 여러 장 이미지 병렬 업로드 ──────────────────────────────────────
  Future<List<String>> uploadChatImages({
    required String roomId,
    required String messageId,
    required List<File> files,
  }) async {
    try {
      return await Future.wait(
        files.asMap().entries.map((entry) async {
          final ref = _storage.ref(
            'chat_rooms/$roomId/images/${messageId}_${entry.key}.jpg',
          );
          final task = await ref.putFile(
              entry.value, SettableMetadata(contentType: 'image/jpeg'));
          return task.ref.getDownloadURL();
        }),
      );
    } catch (e) {
      throw Exception('이미지 업로드 실패: $e');
    }
  }

  // ── 채팅 동영상 + 썸네일 병렬 업로드 ─────────────────────────────────────
  Future<Map<String, String>> uploadChatVideo({
    required String roomId,
    required String messageId,
    required File videoFile,
    required File thumbnailFile,
  }) async {
    try {
      final results = await Future.wait([
        _storage
            .ref('chat_rooms/$roomId/videos/$messageId.mp4')
            .putFile(videoFile, SettableMetadata(contentType: 'video/mp4')),
        _storage
            .ref('chat_rooms/$roomId/thumbnails/$messageId.jpg')
            .putFile(
                thumbnailFile, SettableMetadata(contentType: 'image/jpeg')),
      ]);
      return {
        'videoUrl': await results[0].ref.getDownloadURL(),
        'thumbnailUrl': await results[1].ref.getDownloadURL(),
      };
    } catch (e) {
      throw Exception('동영상 업로드 실패: $e');
    }
  }

  // ── 그룹 프로필 이미지 업로드 ─────────────────────────────────────────────
  Future<String> uploadGroupProfileImage({
    required String groupId,
    required File file,
  }) async {
    try {
      final task = await _storage
          .ref('groups/$groupId/profile.jpg')
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      return await task.ref.getDownloadURL();
    } catch (e) {
      throw Exception('그룹 프로필 사진 업로드 실패: $e');
    }
  }

  // ── 게시글 이미지 병렬 업로드 ─────────────────────────────────────────────
  Future<List<String>> uploadPostImages({
    required String groupId,
    required String postId,
    required List<File> files,
  }) async {
    try {
      return await Future.wait(
        files.asMap().entries.map((entry) async {
          final ref = _storage.ref(
            'groups/$groupId/posts/$postId/image_${entry.key}.jpg',
          );
          final task = await ref.putFile(
              entry.value, SettableMetadata(contentType: 'image/jpeg'));
          return task.ref.getDownloadURL();
        }),
      );
    } catch (e) {
      throw Exception('이미지 업로드 실패: $e');
    }
  }

  // ── 게시글 동영상 + 썸네일 병렬 업로드 ───────────────────────────────────
  Future<Map<String, String>> uploadPostVideo({
    required String groupId,
    required String postId,
    required File videoFile,
    required File thumbnailFile,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    try {
      final results = await Future.wait([
        _storage
            .ref('groups/$groupId/posts/$postId/video_$ts.mp4')
            .putFile(videoFile, SettableMetadata(contentType: 'video/mp4')),
        _storage
            .ref('groups/$groupId/posts/$postId/thumb_$ts.jpg')
            .putFile(thumbnailFile,
                SettableMetadata(contentType: 'image/jpeg')),
      ]);
      return {
        'videoUrl': await results[0].ref.getDownloadURL(),
        'thumbnailUrl': await results[1].ref.getDownloadURL(),
      };
    } catch (e) {
      throw Exception('동영상 업로드 실패: $e');
    }
  }

  // ── 범용 파일 업로드 (오디오, 일반파일) ──────────────────────────────────
  Future<Map<String, String>> uploadPostFile({
    required String groupId,
    required String postId,
    required File file,
    required String fileName,
    required String mimeType,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref(
      'groups/$groupId/posts/$postId/${ts}_$fileName',
    );
    try {
      final task = await ref.putFile(
          file, SettableMetadata(contentType: mimeType));
      final url = await task.ref.getDownloadURL();
      return {'url': url, 'name': fileName};
    } catch (e) {
      throw Exception('파일 업로드 실패: $e');
    }
  }
}