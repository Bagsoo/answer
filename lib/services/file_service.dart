import 'dart:io';

import 'package:file_picker/file_picker.dart';

class PickedChatFile {
  final File file;
  final String name;
  final String mimeType;
  final int size;

  const PickedChatFile({
    required this.file,
    required this.name,
    required this.mimeType,
    required this.size,
  });
}

class FileService {
  static const int maxSizeBytes = 30 * 1024 * 1024;

  Future<List<PickedChatFile>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return const [];

    final picked = <PickedChatFile>[];
    for (final pf in result.files) {
      if (pf.path == null) continue;

      picked.add(
        PickedChatFile(
          file: File(pf.path!),
          name: pf.name,
          mimeType: guessMimeType(pf.extension ?? ''),
          size: pf.size,
        ),
      );
    }
    return picked;
  }

  bool isSizeExceeded(int sizeInBytes, {int limitBytes = maxSizeBytes}) {
    return sizeInBytes > limitBytes;
  }

  String guessMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
      case 'mov':
      case 'm4v':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'hwp':
        return 'application/x-hwp';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.ms-powerpoint';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }
}
