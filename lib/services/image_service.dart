import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickAndCompressImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) return null;

    final dir = await getTemporaryDirectory();
    final targetPath =
        "${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg";

    final XFile? compressedFile =
        await FlutterImageCompress.compressAndGetFile(
      pickedFile.path,
      targetPath,
      quality: 65,
      minWidth: 500,
      minHeight: 500,
      format: CompressFormat.jpeg,
      keepExif: true,
    );

    return compressedFile != null ? File(compressedFile.path) : null;
  }
}
