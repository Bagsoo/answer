import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';

/// Firestore에 저장되는 첨부파일 구조
/// {
///   'type': 'image' | 'video' | 'file' | 'audio',
///   'url': String,
///   'thumbnail_url': String?,   // video만
///   'name': String,             // 원본 파일명
///   'size': int,                // bytes
///   'mime_type': String,
/// }

// ── 첨부파일 목록 표시 위젯 ─────────────────────────────────────────────────
class PostAttachmentsView extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;
  final ColorScheme colorScheme;

  const PostAttachmentsView({
    super.key,
    required this.attachments,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final images = attachments.where((a) => a['type'] == 'image').toList();
    final videos = attachments.where((a) => a['type'] == 'video').toList();
    final files  = attachments.where((a) => a['type'] == 'file').toList();
    final audios = attachments.where((a) => a['type'] == 'audio').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 이미지 그리드 ──────────────────────────────────────────────────
        if (images.isNotEmpty) _ImageGrid(images: images),

        // ── 동영상 썸네일 ──────────────────────────────────────────────────
        if (videos.isNotEmpty)
          ...videos.map((v) => _VideoThumbnail(video: v, colorScheme: colorScheme)),

        // ── 오디오 ────────────────────────────────────────────────────────
        if (audios.isNotEmpty)
          ...audios.map((a) => _AudioPlayer(audio: a, colorScheme: colorScheme)),

        // ── 일반 파일 ─────────────────────────────────────────────────────
        if (files.isNotEmpty)
          ...files.map((f) => _FileTile(file: f, colorScheme: colorScheme)),
      ],
    );
  }
}

// ── 이미지 그리드 ──────────────────────────────────────────────────────────────
class _ImageGrid extends StatelessWidget {
  final List<Map<String, dynamic>> images;

  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => _showImageViewer(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            images[0]['url'] as String,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => _showImageViewer(context, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            images[i]['url'] as String,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
          ),
        ),
      ),
    );
  }

  void _showImageViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewerScreen(
        images: images.map((i) => i['url'] as String).toList(),
        initialIndex: initialIndex,
      ),
      fullscreenDialog: true,
    ));
  }
}

// ── 이미지 풀스크린 뷰어 ───────────────────────────────────────────────────────
class _ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageViewerScreen(
      {required this.images, required this.initialIndex});

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  late PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.images[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 동영상 썸네일 ──────────────────────────────────────────────────────────────
class _VideoThumbnail extends StatelessWidget {
  final Map<String, dynamic> video;
  final ColorScheme colorScheme;

  const _VideoThumbnail(
      {required this.video, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final thumbUrl = video['thumbnail_url'] as String? ?? '';
    final name = video['name'] as String? ?? '동영상';

    return GestureDetector(
      onTap: () => OpenFilex.open(video['url'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumbUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  color: Colors.black45,
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 36),
            ),
            Positioned(
              bottom: 8,
              left: 10,
              child: Text(
                name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 오디오 플레이어 ────────────────────────────────────────────────────────────
class _AudioPlayer extends StatefulWidget {
  final Map<String, dynamic> audio;
  final ColorScheme colorScheme;

  const _AudioPlayer(
      {required this.audio, required this.colorScheme});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _loaded = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _player = AudioPlayer();
    try {
      await _player!.setUrl(widget.audio['url'] as String);
      _duration = _player!.duration ?? Duration.zero;
      _player!.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _player!.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _playing = state.playing);
          if (state.processingState == ProcessingState.completed) {
            _player!.seek(Duration.zero);
            setState(() => _playing = false);
          }
        }
      });
      if (mounted) setState(() => _loaded = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final name = widget.audio['name'] as String? ?? '오디오';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _loaded
                ? () async {
                    if (_playing) {
                      await _player!.pause();
                    } else {
                      await _player!.play();
                    }
                  }
                : null,
            icon: Icon(
              _playing ? Icons.pause_circle : Icons.play_circle,
              color: cs.primary,
              size: 36,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _loaded && _duration.inMilliseconds > 0
                        ? _position.inMilliseconds
                            .clamp(0, _duration.inMilliseconds)
                            .toDouble()
                        : 0,
                    max: _duration.inMilliseconds.toDouble(),
                    onChanged: _loaded
                        ? (v) => _player!
                            .seek(Duration(milliseconds: v.toInt()))
                        : null,
                    activeColor: cs.primary,
                    inactiveColor: cs.outline.withOpacity(0.3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position),
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.4))),
                      Text(_fmt(_duration),
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.4))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 일반 파일 타일 ─────────────────────────────────────────────────────────────
class _FileTile extends StatelessWidget {
  final Map<String, dynamic> file;
  final ColorScheme colorScheme;

  const _FileTile(
      {required this.file, required this.colorScheme});

  IconData _icon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('hwp')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.contains('presentation') || mime.contains('powerpoint')) return Icons.slideshow;
    if (mime.contains('audio')) return Icons.audio_file;
    if (mime.contains('video')) return Icons.video_file;
    if (mime.contains('image')) return Icons.image;
    if (mime.contains('zip') || mime.contains('rar')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _iconColor(String mime, ColorScheme cs) {
    if (mime.contains('pdf')) return Colors.red;
    if (mime.contains('sheet') || mime.contains('excel')) return Colors.green;
    if (mime.contains('presentation') || mime.contains('powerpoint')) return Colors.orange;
    if (mime.contains('word') || mime.contains('hwp')) return Colors.blue;
    return cs.primary;
  }

  String _sizeStr(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final name = file['name'] as String? ?? '파일';
    final size = (file['size'] as num?)?.toInt() ?? 0;
    final mime = file['mime_type'] as String? ?? '';

    return GestureDetector(
      onTap: () => OpenFilex.open(file['url'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(_icon(mime), color: _iconColor(mime, colorScheme), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(_sizeStr(size),
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            ),
            Icon(Icons.download_outlined,
                size: 18, color: colorScheme.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}