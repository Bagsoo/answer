import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/post_block.dart';
import '../../services/image_service.dart';
import '../../services/storage_service.dart';
import '../../services/video_service.dart';
import '../../services/audio_service.dart';
import '../../l10n/app_localizations.dart';

/// 블록 에디터 — _blocks를 완전히 내부에서 관리
/// 부모는 GlobalKey<BlockEditorState>로 getBlocks() 호출만 함
class BlockEditor extends StatefulWidget {
  final String groupId;
  final List<PostBlock> initialBlocks;
  final VoidCallback? onChanged;

  const BlockEditor({
    super.key,
    required this.groupId,
    required this.initialBlocks,
    this.onChanged,
  });

  @override
  State<BlockEditor> createState() => BlockEditorState();
}

class BlockEditorState extends State<BlockEditor> {
  late List<PostBlock> _blocks;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {};
  final _storageService = StorageService();

  // 저장 시 부모가 호출
  List<PostBlock> getBlocks() => List.from(_blocks);

  bool get hasUploading => _blocks.any((b) => b.isUploading);

  @override
  void initState() {
    super.initState();
    _blocks = List.from(widget.initialBlocks);
    _ensureTrailingText();
    _buildControllers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    for (final f in _focusNodes.values) f.dispose();
    super.dispose();
  }

  // ── 컨트롤러 재빌드 (구조 변경 시에만 호출) ──────────────────────────────
  void _buildControllers() {
    for (final c in _controllers.values) c.dispose();
    for (final f in _focusNodes.values) f.dispose();
    _controllers.clear();
    _focusNodes.clear();

    for (int i = 0; i < _blocks.length; i++) {
      if (_blocks[i].isText) {
        _controllers[i] = TextEditingController(text: _blocks[i].textValue);
        _focusNodes[i] = FocusNode();
      }
    }
  }

  void _ensureTrailingText() {
    if (_blocks.isEmpty || !_blocks.last.isText) {
      _blocks.add(PostBlock.text());
    }
  }

  // ── 텍스트 변경 — setState 없이 내부만 업데이트 ──────────────────────────
  void _onTextChanged(int index, String value) {
    _blocks[index] = _blocks[index].copyWithText(value);
    widget.onChanged?.call();
    // setState 호출 안 함 → 포커스 유지
  }

  // ── 미디어 블록 삭제 ──────────────────────────────────────────────────────
  void _removeBlock(int index) {
    setState(() {
      _blocks.removeAt(index);
      _mergeAdjacentText();
      _ensureTrailingText();
      _buildControllers();
    });
    widget.onChanged?.call();
  }

  void _mergeAdjacentText() {
    for (int i = _blocks.length - 1; i > 0; i--) {
      if (_blocks[i].isText && _blocks[i - 1].isText) {
        final merged = '${_blocks[i - 1].textValue}\n${_blocks[i].textValue}';
        _blocks[i - 1] = PostBlock.text(merged);
        _blocks.removeAt(i);
      }
    }
  }

  // ── 미디어 삽입 시트 ──────────────────────────────────────────────────────
  void showMediaPicker(int insertIndex) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _PickerTile(icon: Icons.photo_outlined, label: l.attachPhoto,
                color: Colors.green, onTap: () { Navigator.pop(ctx); _pickImages(insertIndex); }),
            _PickerTile(icon: Icons.videocam_outlined, label: l.attachVideo,
                color: Colors.red, onTap: () { Navigator.pop(ctx); _pickVideo(insertIndex); }),
            _PickerTile(icon: Icons.mic_outlined, label: l.attachAudio,
                color: Colors.orange, onTap: () { Navigator.pop(ctx); _pickAudio(insertIndex); }),
            _PickerTile(icon: Icons.attach_file, label: l.attachFile,
                color: cs.primary, onTap: () { Navigator.pop(ctx); _pickFile(insertIndex); }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  // ── 블록 삽입 헬퍼 ────────────────────────────────────────────────────────
  void _insertMediaBlock(int index, PostBlock block) {
    setState(() {
      // 텍스트 블록 커서 위치에서 분리
      if (index > 0 && index <= _blocks.length &&
          _blocks[index - 1].isText) {
        // 이전 텍스트 블록의 현재 컨트롤러 값 반영
        final ctrl = _controllers[index - 1];
        if (ctrl != null) {
          _blocks[index - 1] = _blocks[index - 1].copyWithText(ctrl.text);
        }
      }
      _blocks.insert(index, block);
      _ensureTrailingText();
      _buildControllers();
    });
    widget.onChanged?.call();
  }

  void _replaceBlock(String blockId, PostBlock uploaded) {
    setState(() {
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i != -1) _blocks[i] = uploaded;
    });
    widget.onChanged?.call();
  }

  // ── 이미지 ────────────────────────────────────────────────────────────────
  Future<void> _pickImages(int insertIndex) async {
    final files = await ImageService().pickAndCompressMultipleImages();
    if (files.isEmpty || !mounted) return;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final name = file.path.split('/').last;
      final pending = PostBlock.imagePending(file, name);
      _insertMediaBlock(insertIndex + i, pending);
      _uploadImage(pending.id, file); // 백그라운드 업로드
    }
  }

  Future<void> _uploadImage(String blockId, File file) async {
    try {
      final postId = _getTempPostId();
      final urls = await _storageService.uploadPostImages(
        groupId: widget.groupId,
        postId: postId,
        files: [file],
      );
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({
        'url': urls[0],
        'size': await file.length(),
      }));
    } catch (e) {
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({'error': e.toString()}));
    }
  }

  // ── 동영상 ────────────────────────────────────────────────────────────────
  Future<void> _pickVideo(int insertIndex) async {
    final l = AppLocalizations.of(context);
    final videoService = VideoService();
    final file = await videoService.pickVideo();
    if (file == null || !mounted) return;

    // 20MB 제한
    final sizeMb = await file.length() / (1024 * 1024);
    if (sizeMb > 20) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.fileSizeExceeded)));
      return;
    }

    // 썸네일 먼저 생성 후 즉시 UI 표시
    final result = await videoService.compressAndGetThumbnail(file);
    if (!mounted || result == null) return;

    final name = file.path.split('/').last;
    final pending = PostBlock.videoPending(result['video']!, result['thumbnail']!, name);
    _insertMediaBlock(insertIndex, pending);

    // 백그라운드 업로드
    _uploadVideo(pending.id, result['video']!, result['thumbnail']!);
  }

  Future<void> _uploadVideo(String blockId, File video, File thumbnail) async {
    try {
      final postId = _getTempPostId();
      final urls = await _storageService.uploadPostVideo(
        groupId: widget.groupId,
        postId: postId,
        videoFile: video,
        thumbnailFile: thumbnail,
      );
      VideoService().clearCache();
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({
        'url': urls['videoUrl']!,
        'thumbnail_url': urls['thumbnailUrl']!,
        'size': await video.length(),
      }));
    } catch (e) {
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({'error': e.toString()}));
    }
  }

  // ── 오디오 ────────────────────────────────────────────────────────────────
  Future<void> _pickAudio(int insertIndex) async {
    final l = AppLocalizations.of(context);
    final result = await AudioService().pickAndValidate();
    if (result == null) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.audioFileSizeExceeded)));
      return;
    }
    final file = result['file'] as File;
    final name = result['name'] as String;
    final mime = result['mimeType'] as String;
    final size = result['compressedSize'] as int;
    final pending = PostBlock.audioPending(file, name, mime, size);
    _insertMediaBlock(insertIndex, pending);
    _uploadFile(pending.id, file, name, mime);
  }

  // ── 파일 ──────────────────────────────────────────────────────────────────
  Future<void> _pickFile(int insertIndex) async {
    final l = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final pf in result.files) {
      if (pf.path == null) continue;
      if ((pf.size / (1024 * 1024)) > 50) {
        if (mounted) ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.fileSizeExceeded)));
        continue;
      }
      final file = File(pf.path!);
      final mime = _guessMime(pf.extension ?? '');
      final pending = PostBlock.filePending(file, pf.name, mime, pf.size);
      _insertMediaBlock(insertIndex, pending);
      _uploadFile(pending.id, file, pf.name, mime);
    }
  }

  Future<void> _uploadFile(
      String blockId, File file, String name, String mime) async {
    try {
      final postId = _getTempPostId();
      final result = await _storageService.uploadPostFile(
        groupId: widget.groupId,
        postId: postId,
        file: file,
        fileName: name,
        mimeType: mime,
      );
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({
        'url': result['url']!,
        'size': await file.length(),
      }));
    } catch (e) {
      if (!mounted) return;
      final i = _blocks.indexWhere((b) => b.id == blockId);
      if (i == -1) return;
      _replaceBlock(blockId, _blocks[i].withUploaded({'error': e.toString()}));
    }
  }

  String? _tempPostId;
  String _getTempPostId() {
    _tempPostId ??= DateTime.now().millisecondsSinceEpoch.toString();
    return _tempPostId!;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(_blocks.length, (i) {
        final block = _blocks[i];
        if (block.isText) {
          return _TextBlock(
            key: ValueKey(block.id),
            index: i,
            controller: _controllers[i]!,
            focusNode: _focusNodes[i]!,
            onChanged: (v) => _onTextChanged(i, v),
            onAddMedia: () => showMediaPicker(i + 1),
            colorScheme: cs,
          );
        } else {
          return _MediaBlock(
            key: ValueKey(block.id),
            block: block,
            onRemove: () => _removeBlock(i),
            colorScheme: cs,
          );
        }
      }),
    );
  }
}

// ── 텍스트 블록 ───────────────────────────────────────────────────────────────
class _TextBlock extends StatelessWidget {
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddMedia;
  final ColorScheme colorScheme;

  const _TextBlock({
    super.key,
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onAddMedia,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            maxLines: null,
            minLines: 2,
            decoration: InputDecoration(
              hintText: index == 0 ? '내용을 입력하세요...' : '텍스트를 입력하세요...',
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            ),
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 6),
          child: GestureDetector(
            onTap: onAddMedia,
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, size: 15,
                  color: colorScheme.onSurface.withOpacity(0.45)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 미디어 블록 ───────────────────────────────────────────────────────────────
class _MediaBlock extends StatelessWidget {
  final PostBlock block;
  final VoidCallback onRemove;
  final ColorScheme colorScheme;

  const _MediaBlock({
    super.key,
    required this.block,
    required this.onRemove,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildPreview(context),
          ),
        ),
        // 삭제 버튼
        Positioned(
          top: 16, right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
        // 업로드 중 오버레이
        if (block.isUploading)
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 8),
                  Text('업로드 중...',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    switch (block.type) {
      case BlockType.image:
        final localPath = block.localPath;
        final url = block.url;

        Widget imageWidget;
        if (localPath.isNotEmpty) {
          // 로컬 파일 우선 표시 (업로드 중일 때 즉시 보임)
          imageWidget = Image.file(
            File(localPath),
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              // 로컬 파일 접근 실패 시 URL로 폴백
              if (url.isNotEmpty) {
                return Image.network(url,
                    width: double.infinity, height: 220, fit: BoxFit.cover);
              }
              return _placeholder(Icons.image, block.name);
            },
          );
        } else if (url.isNotEmpty) {
          imageWidget = Image.network(
            url,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 220,
                color: colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (_, __, ___) =>
                _placeholder(Icons.broken_image, block.name),
          );
        } else {
          imageWidget = _placeholder(Icons.image, block.name);
        }
        return imageWidget;

      case BlockType.video:
        final thumbLocal = block.data['thumbnail_local'] as String? ?? '';
        final thumbUrl = block.thumbnailUrl;

        Widget thumb;
        if (thumbLocal.isNotEmpty) {
          thumb = Image.file(
            File(thumbLocal),
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => thumbUrl.isNotEmpty
                ? Image.network(thumbUrl,
                    width: double.infinity, height: 180, fit: BoxFit.cover)
                : Container(height: 180, width: double.infinity,
                    color: Colors.black87),
          );
        } else if (thumbUrl.isNotEmpty) {
          thumb = Image.network(thumbUrl,
              width: double.infinity, height: 180, fit: BoxFit.cover);
        } else {
          thumb = Container(height: 180, width: double.infinity,
              color: Colors.black87);
        }

        return Stack(alignment: Alignment.center, children: [
          thumb,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
          Positioned(
            bottom: 8, left: 12,
            child: Text(block.name,
                style: const TextStyle(color: Colors.white, fontSize: 12,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
          ),
        ]);

      case BlockType.audio:
        return _fileTile(Icons.audio_file, Colors.orange,
            block.name, block.size);

      case BlockType.file:
        return _fileTile(_mimeIcon(block.mimeType),
            _mimeColor(block.mimeType), block.name, block.size);

      default:
        return _placeholder(Icons.attach_file, block.name);
    }
  }

  Widget _placeholder(IconData icon, String label) {
    return Container(
      height: 80,
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: colorScheme.onSurface.withOpacity(0.4)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
              fontSize: 12, color: colorScheme.onSurface.withOpacity(0.4))),
        ]),
      ),
    );
  }

  Widget _fileTile(IconData icon, Color color, String name, int size) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Row(children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (size > 0)
              Text(_sizeStr(size), style: TextStyle(
                  fontSize: 11, color: colorScheme.onSurface.withOpacity(0.4))),
          ]),
        ),
      ]),
    );
  }

  IconData _mimeIcon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('hwp')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.contains('presentation')) return Icons.slideshow;
    if (mime.contains('audio')) return Icons.audio_file;
    if (mime.contains('zip')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _mimeColor(String mime) {
    if (mime.contains('pdf')) return Colors.red;
    if (mime.contains('sheet') || mime.contains('excel')) return Colors.green;
    if (mime.contains('presentation')) return Colors.orange;
    if (mime.contains('word') || mime.contains('hwp')) return Colors.blue;
    return colorScheme.primary;
  }

  String _sizeStr(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

// ── 미디어 선택 타일 ───────────────────────────────────────────────────────────
class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}
