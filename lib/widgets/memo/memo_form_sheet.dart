 import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio_service.dart';
import '../../services/image_service.dart';
import '../../services/memo_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';

class MemoFormSheet extends StatefulWidget {
  final String? memoId;
  final String initialContent;
  final List<Map<String, dynamic>> initialAttachments;
  final MemoService service;

  const MemoFormSheet({
    super.key,
    required this.memoId,
    required this.initialContent,
    this.initialAttachments = const [],
    required this.service,
  });

  @override
  State<MemoFormSheet> createState() => _MemoFormSheetState();
}

class _MemoFormSheetState extends State<MemoFormSheet> {
  late TextEditingController _controller;
  bool _saving = false;

  late List<Map<String, dynamic>> _existingAttachments;
  final List<_PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _existingAttachments = List<Map<String, dynamic>>.from(widget.initialAttachments);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _guessMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'mp4':
      case 'mov':
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
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickImages() async {
    final files = await ImageService().pickAndCompressMultipleImages();
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        _pendingAttachments.add(_PendingAttachment(
          type: 'image',
          file: f,
          name: f.path.split('/').last,
          preview: f,
        ));
      }
    });
  }

  Future<void> _pickVideo() async {
    final l = AppLocalizations.of(context);
    final videoService = VideoService();
    final file = await videoService.pickVideo();
    if (file == null || !mounted) return;

    if (videoService.isVideoSizeExceeded(file)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.videoSizeExceeded)));
      return;
    }

    setState(() => _saving = true);
    final result = await videoService.compressAndGetThumbnail(file);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.videoProcessingFailed)));
      return;
    }
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        type: 'video',
        file: result['video']!,
        name: file.path.split('/').last,
        thumbnail: result['thumbnail'],
      ));
    });
  }

  Future<void> _pickAudio() async {
    final l = AppLocalizations.of(context);
    final result = await AudioService().pickAndValidate();
    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.audioFileSizeExceeded)));
      }
      return;
    }
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        type: 'audio',
        file: result['file'] as File,
        name: result['name'] as String,
        mimeType: result['mimeType'] as String,
        size: result['size'] as int,
      ));
    });
  }

  Future<void> _pickFile() async {
    final l = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final pf in result.files) {
        if (pf.path == null) continue;
        if ((pf.size / (1024 * 1024)) > 50) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.fileSizeExceeded)));
          continue;
        }
        final file = File(pf.path!);
        final mime = _guessMime(pf.extension ?? '');
        final type = mime.startsWith('audio') ? 'audio' : 'file';
        _pendingAttachments.add(_PendingAttachment(
          type: type,
          file: file,
          name: pf.name,
          size: pf.size,
          mimeType: mime,
        ));
      }
    });
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final content = _controller.text.trim();
    if (content.isEmpty &&
        _pendingAttachments.isEmpty &&
        _existingAttachments.isEmpty) return;

    setState(() => _saving = true);

    try {
      final storageService = StorageService();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'memo';
      final memoId = widget.memoId ??
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('memos')
              .doc()
              .id;

      final imagePendings =
          _pendingAttachments.where((p) => p.type == 'image').toList();
      final otherPendings =
          _pendingAttachments.where((p) => p.type != 'image').toList();

      // 이미지 병렬 업로드
      final List<Map<String, dynamic>> imageAttachments = [];
      if (imagePendings.isNotEmpty) {
        final urls = await storageService.uploadPostImages(
          groupId: 'memo_$uid',
          postId: memoId,
          files: imagePendings.map((p) => p.file).toList(),
        );
        for (int i = 0; i < imagePendings.length; i++) {
          imageAttachments.add({
            'type': 'image',
            'url': urls[i],
            'name': imagePendings[i].name,
            'size': await imagePendings[i].file.length(),
            'mime_type': 'image/jpeg',
          });
        }
      }

      // 동영상/오디오/파일 순차 업로드
      final List<Map<String, dynamic>> otherAttachments = [];
      for (final pending in otherPendings) {
        if (pending.type == 'video') {
          String videoUploadUrl = '';
          String thumbUploadUrl = '';
          if (pending.thumbnail != null) {
            final urls = await storageService.uploadPostVideo(
              groupId: 'memo_$uid',
              postId: memoId,
              videoFile: pending.file,
              thumbnailFile: pending.thumbnail!,
            );
            VideoService().clearCache();
            videoUploadUrl = urls['videoUrl'] ?? '';
            thumbUploadUrl = urls['thumbnailUrl'] ?? '';
          } else {
            final result = await storageService.uploadPostFile(
              groupId: 'memo_$uid',
              postId: memoId,
              file: pending.file,
              fileName: pending.name,
              mimeType: 'video/mp4',
            );
            videoUploadUrl = result['url'] ?? '';
          }
          if (videoUploadUrl.isNotEmpty) {
            otherAttachments.add({
              'type': 'video',
              'url': videoUploadUrl,
              'thumbnail_url': thumbUploadUrl,
              'name': pending.name,
              'size': await pending.file.length(),
              'mime_type': 'video/mp4',
            });
          }
        } else {
          final result = await storageService.uploadPostFile(
            groupId: 'memo_$uid',
            postId: memoId,
            file: pending.file,
            fileName: pending.name,
            mimeType: pending.mimeType ?? 'application/octet-stream',
          );
          otherAttachments.add({
            'type': pending.type,
            'url': result['url']!,
            'name': pending.name,
            'size': pending.size ?? await pending.file.length(),
            'mime_type': pending.mimeType ?? 'application/octet-stream',
          });
        }
      }

      final allAttachments = [
        ..._existingAttachments,
        ...imageAttachments,
        ...otherAttachments,
      ];

      await widget.service.saveMemo(
        memoId: widget.memoId,
        content: content,
        attachments: allAttachments,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.memoSaved)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.saveError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              widget.memoId != null ? l.editMemo : l.newMemo,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 2000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: l.memoHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outline.withOpacity(0.3))),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withOpacity(0.4),
              ),
            ),

            // 기존 첨부파일
            if (_existingAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l.existingFile,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 4),
              _AttachmentPreviewGrid(
                items: _existingAttachments
                    .asMap()
                    .entries
                    .map((e) => _AttachmentPreviewItem.fromExisting(
                          index: e.key,
                          data: e.value,
                          onRemove: () => setState(
                              () => _existingAttachments.removeAt(e.key)),
                        ))
                    .toList(),
                colorScheme: colorScheme,
              ),
            ],

            // 새 첨부파일
            if (_pendingAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l.pendingAttachments(_pendingAttachments.length),
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 4),
              _AttachmentPreviewGrid(
                items: _pendingAttachments
                    .asMap()
                    .entries
                    .map((e) => _AttachmentPreviewItem.fromPending(
                          index: e.key,
                          pending: e.value,
                          onRemove: () => setState(
                              () => _pendingAttachments.removeAt(e.key)),
                        ))
                    .toList(),
                colorScheme: colorScheme,
              ),
            ],

            // 첨부 버튼 바
            const SizedBox(height: 8),
            Row(
              children: [
                _AttachBtn(
                    icon: Icons.photo_outlined,
                    label: l.attachPhotos,
                    color: Colors.green,
                    onTap: _saving ? null : _pickImages),
                _AttachBtn(
                    icon: Icons.videocam_outlined,
                    label: l.attachVideos,
                    color: Colors.red,
                    onTap: _saving ? null : _pickVideo),
                _AttachBtn(
                    icon: Icons.mic_outlined,
                    label: l.attachVoice,
                    color: Colors.orange,
                    onTap: _saving ? null : _pickAudio),
                _AttachBtn(
                    icon: Icons.attach_file,
                    label: l.attachFile,
                    color: colorScheme.primary,
                    onTap: _saving ? null : _pickFile),
              ],
            ),

            // 저장 버튼
            const SizedBox(height: 8),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(l.save),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 첨부파일 미리보기 그리드 ───────────────────────────────────────────────────
class _AttachmentPreviewGrid extends StatelessWidget {
  final List<_AttachmentPreviewItem> items;
  final ColorScheme colorScheme;

  const _AttachmentPreviewGrid(
      {required this.items, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.buildPreview(colorScheme),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: item.onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                      color: colorScheme.error, shape: BoxShape.circle),
                  child: Icon(Icons.close,
                      size: 12, color: colorScheme.onError),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _AttachmentPreviewItem {
  final String type;
  final String? imageUrl;
  final File? imageFile;
  final File? thumbnailFile;
  final VoidCallback onRemove;

  const _AttachmentPreviewItem({
    required this.type,
    this.imageUrl,
    this.imageFile,
    this.thumbnailFile,
    required this.onRemove,
  });

  factory _AttachmentPreviewItem.fromExisting({
    required int index,
    required Map<String, dynamic> data,
    required VoidCallback onRemove,
  }) {
    return _AttachmentPreviewItem(
      type: data['type'] as String? ?? 'file',
      imageUrl: data['type'] == 'image'
          ? data['url'] as String?
          : data['thumbnail_url'] as String?,
      onRemove: onRemove,
    );
  }

  factory _AttachmentPreviewItem.fromPending({
    required int index,
    required _PendingAttachment pending,
    required VoidCallback onRemove,
  }) {
    return _AttachmentPreviewItem(
      type: pending.type,
      imageFile: pending.type == 'image' ? pending.preview : null,
      thumbnailFile: pending.type == 'video' ? pending.thumbnail : null,
      onRemove: onRemove,
    );
  }

  Widget buildPreview(ColorScheme colorScheme) {
    if (type == 'image') {
      if (imageFile != null) {
        return Image.file(imageFile!, fit: BoxFit.cover);
      }
      if (imageUrl != null) {
        return Image.network(imageUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 24));
      }
    }
    if (type == 'video') {
      final thumb = thumbnailFile;
      if (thumb != null) {
        return Stack(alignment: Alignment.center, children: [
          Image.file(thumb, fit: BoxFit.cover, width: 60, height: 60),
          const Icon(Icons.play_arrow, color: Colors.white, size: 24),
        ]);
      }
      if (imageUrl != null) {
        return Stack(alignment: Alignment.center, children: [
          Image.network(imageUrl!, fit: BoxFit.cover, width: 60, height: 60,
              errorBuilder: (_, __, ___) => Container(
                  width: 60,
                  height: 60,
                  color: Colors.black54,
                  child: const Icon(Icons.videocam,
                      color: Colors.white, size: 24))),
          const Icon(Icons.play_arrow, color: Colors.white, size: 20),
        ]);
      }
      return Icon(Icons.videocam, color: colorScheme.primary, size: 28);
    }
    final icon =
        type == 'audio' ? Icons.audio_file : Icons.insert_drive_file;
    return Icon(icon, color: colorScheme.primary, size: 28);
  }
}

// ── 첨부 버튼 ─────────────────────────────────────────────────────────────────
class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachBtn(
      {required this.icon,
      required this.label,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: onTap == null ? Colors.grey : color, size: 22),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: onTap == null
                          ? Colors.grey
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 업로드 대기 첨부파일 모델 ──────────────────────────────────────────────────
class _PendingAttachment {
  final String type;
  final File file;
  final String name;
  final int? size;
  final String? mimeType;
  final File? preview;
  final File? thumbnail;

  _PendingAttachment({
    required this.type,
    required this.file,
    required this.name,
    this.size,
    this.mimeType,
    this.preview,
    this.thumbnail,
  });
}