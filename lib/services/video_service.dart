import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

class VideoService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickVideo() async {
    final XFile? pickedFile =
        await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile == null) return null;
    return File(pickedFile.path);
  }

  bool isVideoSizeExceeded(File file, {int limitMB = 20}) {
    final length = file.lengthSync();
    final sizeInMB = length / (1024 * 1024);
    return sizeInMB > limitMB;
  }

  Future<Map<String, File>?> compressAndGetThumbnail(File videoFile) async {
    try {
      final thumbnailFile =
          await VideoCompress.getFileThumbnail(videoFile.path);

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.LowQuality,
        deleteOrigin: false,
      );

      if (mediaInfo?.file != null) {
        return {
          'video': mediaInfo!.file!,
          'thumbnail': thumbnailFile,
        };
      }
      return null;
    } catch (e) {
      print('Video compression error: $e');
      return null;
    }
    // ← finally 블록 전체 제거
    // VideoCompress.deleteAllCache()를 여기서 호출하면
    // 업로드 전에 압축 파일이 삭제됨
  }

  /// 업로드 완료 후 호출해서 캐시 정리
  Future<void> clearCache() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (e) {
      // video_compress kotlin.Unit 버그 — 무시해도 됨
      debugPrint('clearCache error (ignored): $e');
    }
  }
}