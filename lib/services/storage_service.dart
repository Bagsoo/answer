import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── 단일 이미지 업로드 (messageId 기반) ───────────────────────────────────
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
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      throw Exception('이미지 업로드 실패: $e');
    }
  }

  // ── 여러 장 이미지 병렬 업로드 (messageId_index 기반) ─────────────────────
  Future<List<String>> uploadChatImages({
    required String roomId,
    required String messageId,
    required List<File> files,
  }) async {
    final futures = files.asMap().entries.map((entry) {
      final index = entry.key;
      final file = entry.value;

      final ref = _storage.ref(
        'chat_rooms/$roomId/images/${messageId}_$index.jpg',
      );

      return ref
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'))
          .then((task) => task.ref.getDownloadURL())
          .catchError((e) {
        throw Exception('이미지 $index 업로드 실패: $e');
      });
    });

    try {
      return await Future.wait(futures);
    } catch (e) {
      throw Exception('이미지 업로드 실패: $e');
    }
  }

  // ── 동영상 + 썸네일 병렬 업로드 (messageId 기반, 경로 분리) ──────────────
  Future<Map<String, String>> uploadChatVideo({
    required String roomId,
    required String messageId,
    required File videoFile,
    required File thumbnailFile,
  }) async {
    final videoRef = _storage.ref(
      'chat_rooms/$roomId/videos/$messageId.mp4',
    );
    final thumbRef = _storage.ref(
      'chat_rooms/$roomId/thumbnails/$messageId.jpg',
    );

    try {
      // 동영상 + 썸네일 병렬 업로드
      final results = await Future.wait([
        videoRef.putFile(
          videoFile,
          SettableMetadata(contentType: 'video/mp4'),
        ),
        thumbRef.putFile(
          thumbnailFile,
          SettableMetadata(contentType: 'image/jpeg'),
        ),
      ]);

      final videoUrl = await results[0].ref.getDownloadURL();
      final thumbnailUrl = await results[1].ref.getDownloadURL();

      return {
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
      };
    } catch (e) {
      throw Exception('동영상 업로드 실패: $e');
    }
  }
}