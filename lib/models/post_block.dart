import 'dart:io';

enum BlockType { text, image, video, audio, file }

class PostBlock {
  final String id;   // 업로드 추적용 고유 ID
  final BlockType type;
  final Map<String, dynamic> data;

  PostBlock({
    String? id,
    required this.type,
    required this.data,
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${type.name}';

  // ── 팩토리 생성자 ──────────────────────────────────────────────────────────
  factory PostBlock.text([String value = '']) => PostBlock(
        type: BlockType.text,
        data: {'value': value},
      );

  factory PostBlock.imagePending(File file, String name) => PostBlock(
        type: BlockType.image,
        data: {
          'local_path': file.path,
          'name': name,
          'uploading': true,
        },
      );

  factory PostBlock.videoPending(File file, File thumbnail, String name) =>
      PostBlock(
        type: BlockType.video,
        data: {
          'local_path': file.path,
          'thumbnail_local': thumbnail.path,
          'name': name,
          'uploading': true,
        },
      );

  factory PostBlock.audioPending(File file, String name, String mimeType,
          int size) =>
      PostBlock(
        type: BlockType.audio,
        data: {
          'local_path': file.path,
          'name': name,
          'mime_type': mimeType,
          'size': size,
          'uploading': true,
        },
      );

  factory PostBlock.filePending(
          File file, String name, String mimeType, int size) =>
      PostBlock(
        type: BlockType.file,
        data: {
          'local_path': file.path,
          'name': name,
          'mime_type': mimeType,
          'size': size,
          'uploading': true,
        },
      );

  // ── Firestore 직렬화 ───────────────────────────────────────────────────────
  factory PostBlock.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'text';
    final blockType = BlockType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => BlockType.text,
    );
    return PostBlock(
      id: json['id'] as String?,
      type: blockType,
      data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'data': data,
      };

  // ── 편의 getter ────────────────────────────────────────────────────────────
  bool get isUploading => data['uploading'] == true;
  bool get isText => type == BlockType.text;
  String get textValue => data['value'] as String? ?? '';
  String get url => data['url'] as String? ?? '';
  String get name => data['name'] as String? ?? '';
  String get thumbnailUrl => data['thumbnail_url'] as String? ?? '';
  String get mimeType => data['mime_type'] as String? ?? '';
  int get size => (data['size'] as num?)?.toInt() ?? 0;
  String get localPath => data['local_path'] as String? ?? '';

  // ── 업로드 완료 후 새 블록 반환 (id 유지) ─────────────────────────────────
  PostBlock withUploaded(Map<String, dynamic> uploaded) => PostBlock(
        id: id,   // id 유지 → _replaceBlock에서 정확히 찾을 수 있음
        type: type,
        data: {
          ...data,
          ...uploaded,
          'uploading': false,
          'local_path': null,
          'thumbnail_local': null,
        },
      );

  PostBlock copyWithText(String value) => PostBlock(
        id: id,
        type: BlockType.text,
        data: {'value': value},
      );
}