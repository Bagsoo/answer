import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

class VideoService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickVideo() async {
    final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile == null) return null;
    return File(pickedFile.path);
  }

  /// 비디오 파일 크기가 limitMB를 초과하는지 검사
  bool isVideoSizeExceeded(File file, {int limitMB = 50}) {
    final length = file.lengthSync();
    final sizeInMB = length / (1024 * 1024);
    return sizeInMB > limitMB;
  }

  /// 비디오 압축 및 썸네일 추출 (성공 시 Map 반환, 실패 시 null)
  /// 반환 포맷: {'video': File, 'thumbnail': File}
  Future<Map<String, File>?> compressAndGetThumbnail(File videoFile) async {
    try {
      // 1. 썸네일 추출 (압축 전 원본에서 추출이 더 빠를 수 있음)
      final thumbnailFile = await VideoCompress.getFileThumbnail(videoFile.path);

      // 2. 비디오 압축 (MediumQuality 권장)
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
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
    } finally {
      // 진행중인 임시 파일 정리
      VideoCompress.deleteAllCache();
    }
  }
}
