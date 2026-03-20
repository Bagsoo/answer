import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../services/group_service.dart';
import '../../services/image_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../services/audio_service.dart';

class BoardPostFormScreen extends StatefulWidget {
  final String groupId;
  final String boardId;
  final String boardName;
  final String boardType;
  final String myRole;
  final Map<String, dynamic>? post;

  const BoardPostFormScreen({
    super.key,
    required this.groupId,
    required this.boardId,
    required this.boardName,
    required this.boardType,
    required this.myRole,
    this.post,
  });

  @override
  State<BoardPostFormScreen> createState() => _BoardPostFormScreenState();
}

class _BoardPostFormScreenState extends State<BoardPostFormScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _service = GroupService();
  bool _saving = false;

  List<Map<String, dynamic>> _existingAttachments = [];
  final List<_PendingAttachment> _pendingAttachments = [];

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isEditing => widget.post != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _titleCtrl.text = widget.post!['title'] as String? ?? '';
      _contentCtrl.text = widget.post!['content'] as String? ?? '';
      _existingAttachments = List<Map<String, dynamic>>.from(
          widget.post!['attachments'] as List? ?? []);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // ── 사진 선택 ──────────────────────────────────────────────────────────────
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

  // ── 동영상 선택 ────────────────────────────────────────────────────────────
  Future<void> _pickVideo() async {
    final l = AppLocalizations.of(context);
    final videoService = VideoService();
    final file = await videoService.pickVideo();
    if (file == null || !mounted) return;

    if (videoService.isVideoSizeExceeded(file)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.fileSizeExceeded)));
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
    // clearCache는 _save()에서 업로드 후 호출
  }

  // ── 오디오 선택 ────────────────────────────────────────────────────────────
  Future<void> _pickAudio() async {
    final l = AppLocalizations.of(context);
    final result = await AudioService().pickAndValidate();
    if (result == null) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.audioFileSizeExceeded)));
      return;
    }
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        type: 'audio',
        file: result['file'] as File,
        name: result['name'] as String,
        mimeType: result['mimeType'] as String,
        size: result['compressedSize'] as int,
      ));
    });
  }

  // ── 일반 파일 선택 ─────────────────────────────────────────────────────────
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
        final mime = _guessMime(pf.extension ?? '');
        final type = mime.startsWith('audio') ? 'audio' : 'file';
        _pendingAttachments.add(_PendingAttachment(
          type: type,
          file: File(pf.path!),
          name: pf.name,
          size: pf.size,
          mimeType: mime,
        ));
      }
    });
  }

  String _guessMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'mp4': case 'mov': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'aac': return 'audio/aac';
      case 'm4a': return 'audio/mp4';
      case 'pdf': return 'application/pdf';
      case 'doc': case 'docx': return 'application/msword';
      case 'hwp': return 'application/x-hwp';
      case 'xls': case 'xlsx': return 'application/vnd.ms-excel';
      case 'ppt': case 'pptx': return 'application/vnd.ms-powerpoint';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  // ── 저장 ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postTitleRequired)));
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postContentRequired)));
      return;
    }

    setState(() => _saving = true);

    try {
      final tempPostId = isEditing
          ? widget.post!['id'] as String
          : FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('posts')
              .doc()
              .id;

      final storageService = StorageService();

      // ── 이미지 병렬 업로드 ────────────────────────────────────────────────
      final imagePendings =
          _pendingAttachments.where((p) => p.type == 'image').toList();
      final otherPendings =
          _pendingAttachments.where((p) => p.type != 'image').toList();

      // 이미지 전체를 한 번의 Future.wait으로 병렬 처리
      final List<Map<String, dynamic>> imageAttachments = [];
      if (imagePendings.isNotEmpty) {
        final allImageFiles = imagePendings.map((p) => p.file).toList();
        final urls = await storageService.uploadPostImages(
          groupId: widget.groupId,
          postId: tempPostId,
          files: allImageFiles,
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

      // ── 동영상/오디오/파일 순차 업로드 ───────────────────────────────────
      final List<Map<String, dynamic>> otherAttachments = [];
      for (final pending in otherPendings) {
        if (pending.type == 'video') {
          if (pending.thumbnail == null) continue;
          final urls = await storageService.uploadPostVideo(
            groupId: widget.groupId,
            postId: tempPostId,
            videoFile: pending.file,
            thumbnailFile: pending.thumbnail!,
          );
          VideoService().clearCache(); // fire-and-forget
          otherAttachments.add({
            'type': 'video',
            'url': urls['videoUrl']!,
            'thumbnail_url': urls['thumbnailUrl']!,
            'name': pending.name,
            'size': await pending.file.length(),
            'mime_type': 'video/mp4',
          });
        } else {
          // audio / file
          final result = await storageService.uploadPostFile(
            groupId: widget.groupId,
            postId: tempPostId,
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

      final userProvider = context.read<UserProvider>();

      bool ok;
      if (isEditing) {
        ok = await _service.updatePost(
          widget.groupId,
          widget.post!['id'] as String,
          {
            'title': title,
            'content': content,
            'attachments': allAttachments,
          },
        );
      } else {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('posts')
            .doc(tempPostId)
            .set({
          'board_id': widget.boardId,
          'board_name': widget.boardName,
          'board_type': widget.boardType,
          'title': title,
          'content': content,
          'author_id': currentUserId,
          'author_name': userProvider.name,
          'attachments': allAttachments,
          'visible_tags': [],
          'is_pinned': false,
          'reactions': {},
          'comment_count': 0,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
        ok = true;
      }

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? l.postSaved : l.postSaveFailed)));
        if (ok) Navigator.pop(context);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l.editPost : l.createPost),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(
                  onPressed: _save,
                  child: Text(l.save,
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 제목 ──────────────────────────────────────────────────
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: l.postTitle,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // ── 내용 ──────────────────────────────────────────────────
                TextField(
                  controller: _contentCtrl,
                  decoration: InputDecoration(
                    labelText: l.postContent,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines: 6,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 16),

                // ── 기존 첨부파일 (수정 시) ───────────────────────────────
                if (_existingAttachments.isNotEmpty) ...[
                  Text(l.existingFile,
                      style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  ..._existingAttachments.asMap().entries.map((entry) {
                    final i = entry.key;
                    final att = entry.value;
                    return ListTile(
                      dense: true,
                      leading: _typeIcon(
                          att['type'] as String? ?? 'file', colorScheme),
                      title: Text(att['name'] as String? ?? '파일',
                          style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        icon: Icon(Icons.close,
                            size: 16,
                            color: colorScheme.onSurface.withOpacity(0.4)),
                        onPressed: () => setState(
                            () => _existingAttachments.removeAt(i)),
                      ),
                    );
                  }),
                  const Divider(),
                ],

                // ── 새 첨부파일 미리보기 ──────────────────────────────────
                if (_pendingAttachments.isNotEmpty) ...[
                  Text(l.pendingAttachments(_pendingAttachments.length),
                      style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _pendingAttachments
                        .asMap()
                        .entries
                        .map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: p.type == 'image' && p.preview != null
                                  ? Image.file(p.preview!, fit: BoxFit.cover)
                                  : p.type == 'video' && p.thumbnail != null
                                      ? Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Image.file(p.thumbnail!,
                                                fit: BoxFit.cover,
                                                width: 80,
                                                height: 80),
                                            const Icon(Icons.play_arrow,
                                                color: Colors.white,
                                                size: 28),
                                          ],
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _typeIcon(p.type, colorScheme),
                                            const SizedBox(height: 4),
                                            Text(
                                              p.name.length > 8
                                                  ? '${p.name.substring(0, 8)}…'
                                                  : p.name,
                                              style: const TextStyle(
                                                  fontSize: 9),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _pendingAttachments.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close,
                                    size: 12, color: colorScheme.onError),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),

          // ── 하단 첨부 버튼 바 ────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                    top: BorderSide(
                        color: colorScheme.outline.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  _AttachBtn(
                    icon: Icons.photo_outlined,
                    label: '사진',
                    color: Colors.green,
                    onTap: _saving ? null : _pickImages,
                  ),
                  _AttachBtn(
                    icon: Icons.videocam_outlined,
                    label: '동영상',
                    color: Colors.red,
                    onTap: _saving ? null : _pickVideo,
                  ),
                  _AttachBtn(
                    icon: Icons.mic_outlined,
                    label: '오디오',
                    color: Colors.orange,
                    onTap: _saving ? null : _pickAudio,
                  ),
                  _AttachBtn(
                    icon: Icons.attach_file,
                    label: '파일',
                    color: colorScheme.primary,
                    onTap: _saving ? null : _pickFile,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeIcon(String type, ColorScheme cs) {
    switch (type) {
      case 'image':
        return const Icon(Icons.image, color: Colors.green, size: 28);
      case 'video':
        return const Icon(Icons.videocam, color: Colors.red, size: 28);
      case 'audio':
        return const Icon(Icons.audio_file, color: Colors.orange, size: 28);
      default:
        return Icon(Icons.insert_drive_file, color: cs.primary, size: 28);
    }
  }
}

// ── 하단 첨부 버튼 ─────────────────────────────────────────────────────────────
class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

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