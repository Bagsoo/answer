import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/user_profile_detail_screen.dart';
import 'location_message_bubble.dart';

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool isContinuous;
  final int unreadCount;
  final ColorScheme colorScheme;
  final bool isHighlighted;
  final String searchQuery;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onReplyTap;

  const MessageBubble({
    super.key,
    required this.data,
    required this.isMe,
    required this.isContinuous,
    required this.unreadCount,
    required this.colorScheme,
    this.isHighlighted = false,
    this.searchQuery = '',
    this.onAvatarTap,
    this.onReplyTap,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  static const int _collapseThreshold = 200;
  bool _expanded = false;
  late AnimationController _highlightController;

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isHighlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _highlightController
            .forward()
            .then((_) => _highlightController.reverse());
      });
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _highlightController
          .forward()
          .then((_) => _highlightController.reverse());
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  // ── 검색 키워드 하이라이트 텍스트 ────────────────────────────────────────
  Widget _buildMessageText(String text, ColorScheme colorScheme) {
    final query = widget.searchQuery;
    if (query.isEmpty) {
      return Text(text, style: TextStyle(color: colorScheme.onSurface));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          backgroundColor: colorScheme.primary.withOpacity(0.35),
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
        children: spans,
      ),
    );
  }

  // ── 아바타 ────────────────────────────────────────────────────────────────
  Widget _buildAvatar(String senderName, ColorScheme colorScheme) {
    final photoUrl = widget.data['sender_photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return GestureDetector(
      onTap: widget.onAvatarTap,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.secondaryContainer,
        backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
        onBackgroundImageError: hasPhoto ? (_, __) {} : null,
        child: hasPhoto
            ? null
            : Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
      ),
    );
  }

  // ── 이미지 풀스크린 뷰어 ──────────────────────────────────────────────────
  void _showImageViewer(List<String> urls, int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewerScreen(
        urls: urls,
        initialIndex: initialIndex,
      ),
    ));
  }

  // ── 동영상 플레이어 ────────────────────────────────────────────────────────
  void _showVideoPlayer(String videoUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _VideoPlayerScreen(videoUrl: videoUrl),
    ));
  }

  Future<void> _openFileUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  IconData _fileIcon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('hwp')) return Icons.description;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.contains('presentation') || mime.contains('powerpoint')) {
      return Icons.slideshow;
    }
    if (mime.contains('audio')) return Icons.audio_file;
    if (mime.contains('video')) return Icons.video_file;
    if (mime.contains('image')) return Icons.image;
    if (mime.contains('zip') || mime.contains('rar')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _fileIconColor(String mime, ColorScheme colorScheme) {
    if (mime.contains('pdf')) return Colors.red;
    if (mime.contains('sheet') || mime.contains('excel')) return Colors.green;
    if (mime.contains('presentation') || mime.contains('powerpoint')) {
      return Colors.orange;
    }
    if (mime.contains('word') || mime.contains('hwp')) return Colors.blue;
    return colorScheme.primary;
  }

  String _fileSizeText(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ── 말풍선 내용 빌드 ──────────────────────────────────────────────────────
  Widget _buildBubbleContent({
    required String type,
    required String text,
    required String displayText,
    required bool isLong,
    required List<String> imageUrls,
    required String videoUrl,
    required String thumbnailUrl,
    required String fileUrl,
    required String fileName,
    required int fileSize,
    required String mimeType,
    required String sharedUserId,
    required String sharedUserName,
    required String sharedUserPhotoUrl,
    required Widget? replyBox,
    required ColorScheme colorScheme,
  }) {
    final l = AppLocalizations.of(context);

    // ── 이미지 ──────────────────────────────────────────────────────────────
    if (type == 'image' && imageUrls.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          if (imageUrls.length == 1)
            GestureDetector(
              onTap: () => _showImageViewer(imageUrls, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrls[0],
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 40),
                ),
              ),
            )
          else
            SizedBox(
              width: 200,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: imageUrls.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _showImageViewer(imageUrls, i),
                  child: Image.network(
                    imageUrls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // ── 동영상 ──────────────────────────────────────────────────────────────
    if (type == 'video') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          GestureDetector(
            onTap: videoUrl.isNotEmpty
                ? () => _showVideoPlayer(videoUrl)
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  thumbnailUrl.isNotEmpty
                      ? Image.network(
                          thumbnailUrl,
                          width: 200,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 150,
                            color: Colors.black54,
                            child: const Icon(Icons.videocam,
                                color: Colors.white, size: 40),
                          ),
                        )
                      : Container(
                          width: 200,
                          height: 150,
                          color: Colors.black54,
                          child: const Icon(Icons.videocam,
                              color: Colors.white, size: 40),
                        ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 32),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (type == 'file') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          GestureDetector(
            onTap: fileUrl.isNotEmpty ? () => _openFileUrl(fileUrl) : null,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    _fileIcon(mimeType),
                    color: _fileIconColor(mimeType, colorScheme),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fileName.isNotEmpty ? fileName : l.attachFile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (fileSize > 0)
                          Text(
                            _fileSizeText(fileSize),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.download_outlined,
                    size: 18,
                    color: colorScheme.onSurface.withOpacity(0.45),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (type == 'contact') {
      final hasPhoto = sharedUserPhotoUrl.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          GestureDetector(
            onTap: sharedUserId.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserProfileDetailScreen(
                          uid: sharedUserId,
                          displayName: sharedUserName.isNotEmpty
                              ? sharedUserName
                              : l.unknown,
                          photoUrl: sharedUserPhotoUrl,
                        ),
                      ),
                    ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage:
                        hasPhoto ? NetworkImage(sharedUserPhotoUrl) : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            sharedUserName.isNotEmpty
                                ? sharedUserName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sharedUserName.isNotEmpty
                              ? sharedUserName
                              : l.unknown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l.attachContact,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurface.withOpacity(0.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── 텍스트 (기본) ────────────────────────────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyBox != null) replyBox,
        _buildMessageText(displayText, colorScheme),
        if (isLong) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? '접기' : '더보기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.data['text'] as String? ?? '';
    final createdAt = widget.data['created_at'] as Timestamp?;
    final senderName = widget.data['sender_name'] as String? ?? '';
    final isMe = widget.isMe;
    final isContinuous = widget.isContinuous;
    final colorScheme = widget.colorScheme;

    final type = widget.data['type'] as String? ?? 'text';

    if (type == 'location') {
      return LocationMessageBubble(
        data: widget.data,
        isMe: widget.isMe,
        isContinuous: widget.isContinuous,
        unreadCount: widget.unreadCount,
        colorScheme: widget.colorScheme,
      );
    }

    final imageUrls =
        List<String>.from(widget.data['image_urls'] as List? ?? []);
    final videoUrl = widget.data['video_url'] as String? ?? '';
    final thumbnailUrl = widget.data['thumbnail_url'] as String? ?? '';
    final fileUrl = widget.data['file_url'] as String? ?? '';
    final fileName = widget.data['file_name'] as String? ?? '';
    final fileSize = (widget.data['file_size'] as num?)?.toInt() ?? 0;
    final mimeType = widget.data['mime_type'] as String? ?? '';
    final sharedUserId = widget.data['shared_user_id'] as String? ?? '';
    final sharedUserName = widget.data['shared_user_name'] as String? ?? '';
    final sharedUserPhotoUrl =
        widget.data['shared_user_photo_url'] as String? ?? '';

    // 답장 데이터
    final replyToText = widget.data['reply_to_text'] as String?;
    final replyToSender = widget.data['reply_to_sender'] as String?;
    final hasReply = replyToText != null && replyToText.isNotEmpty;

    final isLong = text.length > _collapseThreshold;
    final displayText = isLong && !_expanded
        ? '${text.substring(0, _collapseThreshold)}...'
        : text;

    final timeStr = createdAt != null
        ? '${createdAt.toDate().hour.toString().padLeft(2, '0')}:'
            '${createdAt.toDate().minute.toString().padLeft(2, '0')}'
        : '';

    final topPadding = isContinuous ? 2.0 : 8.0;

    // 인용 박스
    Widget? replyBox;
    if (hasReply) {
      replyBox = GestureDetector(
        onTap: widget.onReplyTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(color: colorScheme.primary, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyToSender != null && replyToSender.isNotEmpty)
                Text(
                  replyToSender,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              Text(
                replyToText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 말풍선 내용
    final bubbleContent = _buildBubbleContent(
      type: type,
      text: text,
      displayText: displayText,
      isLong: isLong,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      sharedUserId: sharedUserId,
      sharedUserName: sharedUserName,
      sharedUserPhotoUrl: sharedUserPhotoUrl,
      replyBox: replyBox,
      colorScheme: colorScheme,
    );

    // 이미지/동영상은 패딩 줄임
    final isMedia =
        type == 'image' || type == 'video' || type == 'file' || type == 'contact';
    final bubblePadding = isMedia
        ? const EdgeInsets.all(4)
        : const EdgeInsets.symmetric(horizontal: 13, vertical: 9);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      color: widget.isHighlighted
          ? colorScheme.primaryContainer.withOpacity(0.4)
          : Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding,
          bottom: 2,
          left: 8,
          right: 8,
        ),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── 상대방 메시지 ──────────────────────────────────────────
            if (!isMe) ...[
              SizedBox(
                width: 36,
                child: isContinuous
                    ? null
                    : _buildAvatar(senderName, colorScheme),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isContinuous && senderName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                      child: Text(
                        senderName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.62,
                        ),
                        padding: bubblePadding,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft:
                                Radius.circular(isContinuous ? 16 : 4),
                            topRight: const Radius.circular(16),
                            bottomLeft: const Radius.circular(16),
                            bottomRight: const Radius.circular(16),
                          ),
                        ),
                        child: bubbleContent,
                      ),
                      const SizedBox(width: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.unreadCount > 0)
                            Text(
                              widget.unreadCount.toString(),
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  colorScheme.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],

            // ── 내 메시지 ──────────────────────────────────────────────
            if (isMe) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.unreadCount > 0)
                    Text(
                      widget.unreadCount.toString(),
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.62,
                ),
                padding: bubblePadding,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: Radius.circular(isContinuous ? 16 : 4),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                ),
                child: bubbleContent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 이미지 풀스크린 뷰어 ──────────────────────────────────────────────────────
class _ImageViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _ImageViewerScreen(
      {required this.urls, required this.initialIndex});

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: widget.initialIndex),
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 동영상 플레이어 ────────────────────────────────────────────────────────────
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerScreen({required this.videoUrl});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          ..initialize().then((_) {
            if (mounted) {
              setState(() => _initialized = true);
              _controller.play();
            }
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _initialized
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.value.isPlaying
                        ? _controller.pause()
                        : _controller.play();
                  });
                },
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: _initialized
          ? FloatingActionButton(
              backgroundColor: Colors.white24,
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Icon(
                _controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}
