import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  // ── 단일 이미지 선택 + 압축 ────────────────────────────────────────────────
  Future<File?> pickAndCompressImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return null;
    return _compress(File(xfile.path));
  }

  // ── 여러 장 선택 + 병렬 압축 ──────────────────────────────────────────────
  Future<List<File>> pickAndCompressMultipleImages() async {
    final pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isEmpty) return [];

    final compressed = await Future.wait(
      pickedFiles.map((xfile) => _compress(File(xfile.path))),
    );
    return compressed.whereType<File>().toList();
  }

  Future<File?> _compress(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,  // ← absolutePath → absolute.path
        targetPath,
        minWidth: 400,
        minHeight: 400,
        quality: 60,
        format: CompressFormat.jpeg,
      );
      return result != null ? File(result.path) : file;
    } catch (e) {
      return file;
    }
  }
}