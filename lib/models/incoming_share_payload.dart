import 'dart:io';

class IncomingSharedFile {
  final String path;
  final String name;
  final String mimeType;
  final int size;

  const IncomingSharedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  factory IncomingSharedFile.fromMap(Map<dynamic, dynamic> map) {
    return IncomingSharedFile(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }

  File get file => File(path);

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isTextFile => mimeType.startsWith('text/');
}

class IncomingSharePayload {
  final String text;
  final String subject;
  final String mimeType;
  final String sourceApp;
  final List<IncomingSharedFile> files;

  const IncomingSharePayload({
    required this.text,
    required this.subject,
    required this.mimeType,
    required this.sourceApp,
    required this.files,
  });

  factory IncomingSharePayload.fromMap(Map<dynamic, dynamic> map) {
    final rawFiles = map['files'] as List? ?? const [];
    return IncomingSharePayload(
      text: map['text'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      sourceApp: map['sourceApp'] as String? ?? '',
      files: rawFiles
          .map((e) => IncomingSharedFile.fromMap(e as Map<dynamic, dynamic>))
          .where((e) => e.path.isNotEmpty)
          .toList(),
    );
  }

  bool get hasFiles => files.isNotEmpty;
  bool get hasText => text.trim().isNotEmpty;
  bool get isImageOnly => hasFiles && files.every((f) => f.isImage);

  String get inferredTitle {
    final subjectTrimmed = subject.trim();
    if (subjectTrimmed.isNotEmpty) return subjectTrimmed;

    final textTrimmed = text.trim();
    if (textTrimmed.isNotEmpty) {
      final firstLine = textTrimmed.split('\n').first.trim();
      if (firstLine.isNotEmpty) {
        return firstLine.length > 40
            ? '${firstLine.substring(0, 40)}...'
            : firstLine;
      }
    }

    if (files.length == 1) return files.first.name;
    if (files.isNotEmpty) return '공유한 항목 ${files.length}개';
    return '외부 공유';
  }

  String get summaryText {
    final textTrimmed = text.trim();
    if (textTrimmed.isNotEmpty) return textTrimmed;
    if (files.length == 1) return files.first.name;
    if (files.isNotEmpty) return '${files.length}개의 파일';
    return '';
  }
}
