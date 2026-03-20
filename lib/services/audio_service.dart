import 'dart:io';
import 'package:file_picker/file_picker.dart';

class AudioService {
  static const int _maxSizeMB = 20;

  bool isSizeExceeded(File file, {int limitMB = _maxSizeMB}) {
    return file.lengthSync() > limitMB * 1024 * 1024;
  }

  Future<Map<String, dynamic>?> pickAndValidate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final pf = result.files.first;
    if (pf.path == null) return null;

    final file = File(pf.path!);
    if (isSizeExceeded(file)) return null;

    return {
      'file': file,
      'name': pf.name,
      'mimeType': _mimeFromExt(pf.extension?.toLowerCase() ?? 'mp3'),
      'size': pf.size,
    };
  }

  String _mimeFromExt(String ext) {
    switch (ext) {
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'aac': return 'audio/aac';
      case 'm4a': return 'audio/mp4';
      default: return 'audio/mpeg';
    }
  }
}