import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/post_block.dart';

/// 블록 뷰어 — PostBlock 리스트를 읽기 전용으로 표시
class BlockViewer extends StatelessWidget {
  final List<PostBlock> blocks;

  const BlockViewer({super.key, required this.blocks});

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) => _buildBlock(context, block)).toList(),
    );
  }

  Widget _buildBlock(BuildContext context, PostBlock block) {
    switch (block.type) {
      case BlockType.text:
        final text = block.textValue;
        if (text.isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text,
              style: const TextStyle(fontSize: 15, height: 1.6)),
        );

      case BlockType.image:
        return _ImageBlock(block: block);

      case BlockType.video:
        return _VideoBlock(block: block);

      case BlockType.audio:
        return _AudioBlock(block: block);

      case BlockType.file:
        return _FileBlock(block: block);
    }
  }
}

// ── 이미지 블록 ───────────────────────────────────────────────────────────────
class _ImageBlock extends StatelessWidget {
  final PostBlock block;

  const _ImageBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final url = block.url;
    if (url.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showFullscreen(context, url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 200,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image)),
            ),
          ),
        ),
      ),
    );
  }

  void _showFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }
}

// ── 동영상 블록 ───────────────────────────────────────────────────────────────
class _VideoBlock extends StatelessWidget {
  final PostBlock block;

  const _VideoBlock({required this.block});

  @override
  Widget build(BuildContext context) {
    final thumbUrl = block.thumbnailUrl;
    final url = block.url;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => OpenFilex.open(url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
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
                  color: Colors.black38,
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 36),
            ),
            Positioned(
              bottom: 8,
              left: 12,
              child: Text(block.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 오디오 블록 ───────────────────────────────────────────────────────────────
class _AudioBlock extends StatefulWidget {
  final PostBlock block;

  const _AudioBlock({required this.block});

  @override
  State<_AudioBlock> createState() => _AudioBlockState();
}

class _AudioBlockState extends State<_AudioBlock> {
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
      await _player!.setUrl(widget.block.url);
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(children: [
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
              Text(widget.block.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                    ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── 파일 블록 ─────────────────────────────────────────────────────────────────
class _FileBlock extends StatelessWidget {
  final PostBlock block;

  const _FileBlock({required this.block});

  IconData _icon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('hwp')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.contains('presentation')) return Icons.slideshow;
    if (mime.contains('audio')) return Icons.audio_file;
    if (mime.contains('video')) return Icons.video_file;
    if (mime.contains('zip')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _color(String mime, ColorScheme cs) {
    if (mime.contains('pdf')) return Colors.red;
    if (mime.contains('sheet') || mime.contains('excel')) return Colors.green;
    if (mime.contains('presentation')) return Colors.orange;
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
    final cs = Theme.of(context).colorScheme;
    final mime = block.mimeType;

    return GestureDetector(
      onTap: () => OpenFilex.open(block.url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(_icon(mime), color: _color(mime, cs), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(block.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (block.size > 0)
                    Text(_sizeStr(block.size),
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.4))),
                ]),
          ),
          Icon(Icons.download_outlined,
              size: 18, color: cs.onSurface.withOpacity(0.4)),
        ]),
      ),
    );
  }
}