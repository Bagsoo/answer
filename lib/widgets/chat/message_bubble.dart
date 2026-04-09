import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:linkify/linkify.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../l10n/app_localizations.dart';
import '../../services/memo_service.dart';
import '../../utils/shared_content_navigator.dart';
import '../post/block_viewer.dart';
import '../../providers/user_provider.dart';
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
  static const LinkifyOptions _linkifyOptions = LinkifyOptions(
    looseUrl: true,
    defaultToHttps: true,
    humanize: false,
  );

  // ── 번역 상태 ──────────────────────────────────────────────────────────────
  String? _translatedText;
  bool _translating = false;
  // 이 메시지에 번역 버튼을 보여줄지 여부 (언어 감지 후 결정)
  bool _showTranslateButton = false;
  bool _languageChecked = false; // 중복 감지 방지

  bool _expanded = false;
  late AnimationController _highlightController;

  // ML Kit 언어 감지 신뢰도 최소값
  static const double _minConfidence = 0.7;

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

    // 텍스트 타입 메시지만 언어 감지
    final type = widget.data['type'] as String? ?? 'text';
    final text = widget.data['text'] as String? ?? '';
    if (type == 'text' && text.trim().isNotEmpty) {
      _checkLanguage(text);
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

  // ── ML Kit 언어 코드 → TranslateLanguage 변환 ─────────────────────────────
  TranslateLanguage? _toTranslateLanguage(String bcp47) {
    // ML Kit 언어 감지는 BCP-47 코드 반환 (예: 'ko', 'en', 'ja', 'zh')
    // TranslateLanguage enum과 매핑
    switch (bcp47.split('-').first.toLowerCase()) {
      case 'ko': return TranslateLanguage.korean;
      case 'en': return TranslateLanguage.english;
      case 'ja': return TranslateLanguage.japanese;
      case 'zh': return TranslateLanguage.chinese;
      case 'es': return TranslateLanguage.spanish;
      case 'fr': return TranslateLanguage.french;
      case 'de': return TranslateLanguage.german;
      case 'pt': return TranslateLanguage.portuguese;
      case 'ru': return TranslateLanguage.russian;
      case 'ar': return TranslateLanguage.arabic;
      case 'hi': return TranslateLanguage.hindi;
      case 'id': return TranslateLanguage.indonesian;
      case 'th': return TranslateLanguage.thai;
      case 'vi': return TranslateLanguage.vietnamese;
      case 'tr': return TranslateLanguage.turkish;
      case 'it': return TranslateLanguage.italian;
      case 'nl': return TranslateLanguage.dutch;
      case 'pl': return TranslateLanguage.polish;
      case 'sv': return TranslateLanguage.swedish;
      default: return null;
    }
  }

  // ── 내 locale → TranslateLanguage 변환 ───────────────────────────────────
  TranslateLanguage _myTranslateLanguage(String locale) {
    return _toTranslateLanguage(locale) ?? TranslateLanguage.english;
  }

  // ── 언어 감지: 내 언어와 다를 때만 버튼 표시 ──────────────────────────────
  Future<void> _checkLanguage(String text) async {
    if (_languageChecked) return;
    _languageChecked = true;

    final textForDetection = _extractTranslatableText(text);

    // 너무 짧은 텍스트는 감지 정확도가 낮으므로 스킵
    if (textForDetection.length < 4) return;

    final myLocale = context.read<UserProvider>().locale;

    try {
      final languageIdentifier = LanguageIdentifier(confidenceThreshold: _minConfidence);
      final result = await languageIdentifier.identifyLanguage(textForDetection);
      languageIdentifier.close();

      // 'und' = 감지 불가 (undetermined)
      if (result == 'und' || result.isEmpty) return;

      final detectedLang = result.split('-').first.toLowerCase();
      final myLang = myLocale.split('-').first.toLowerCase();

      if (detectedLang != myLang && mounted) {
        setState(() => _showTranslateButton = true);
      }
    } catch (e) {
      debugPrint('언어 감지 실패: $e');
    }
  }

  // ── 번역 실행 ─────────────────────────────────────────────────────────────
  Future<void> _translate(String text) async {
    if (_translating) return;

    // 이미 번역됐으면 토글 (번역 숨기기)
    if (_translatedText != null) {
      setState(() => _translatedText = null);
      return;
    }

    setState(() => _translating = true);

    final myLocale = context.read<UserProvider>().locale;
    final targetLang = _myTranslateLanguage(myLocale);
    final textForTranslation = _extractTranslatableText(text);

    if (textForTranslation.length < 4) {
      if (mounted) setState(() => _translating = false);
      return;
    }

    try {
      final languageIdentifier = LanguageIdentifier(confidenceThreshold: _minConfidence);
      final sourceLangCode = await languageIdentifier.identifyLanguage(textForTranslation);
      languageIdentifier.close();

      final sourceLang = _toTranslateLanguage(sourceLangCode);
      if (sourceLang == null) {
        if (mounted) setState(() => _translating = false);
        return;
      }

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );

      // 언어 모델 다운로드 확인 및 다운로드
      final modelManager = OnDeviceTranslatorModelManager();      
      final String sourceCode = sourceLang.bcpCode;
      final String targetCode = targetLang.bcpCode;

      if (!await modelManager.isModelDownloaded(sourceCode)) {
        debugPrint('📥 Downloading source model: $sourceCode');
        await modelManager.downloadModel(sourceCode);
      }

      if (!await modelManager.isModelDownloaded(targetCode)) {
        debugPrint('📥 Downloading target model: $targetCode');
        await modelManager.downloadModel(targetCode);
      }

      final translated = await translator.translateText(textForTranslation);
      translator.close();

      if (mounted) {
        setState(() {
          _translatedText = translated;
          _translating = false;
        });
      }
    } catch (e) {
      debugPrint('번역 실패: $e');
      if (mounted) setState(() => _translating = false);
    }
  }

  String _extractTranslatableText(String text) {
    final elements = linkify(text, options: _linkifyOptions);
    final buffer = StringBuffer();

    for (final element in elements) {
      if (element is UrlElement || element is EmailElement) {
        continue;
      }
      final value = element.text.trim();
      if (value.isEmpty) continue;
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(value);
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── 검색 키워드 하이라이트 텍스트 ────────────────────────────────────────
  Widget _buildMessageText(String text, ColorScheme colorScheme) {
    final query = widget.searchQuery;
    final textStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
      height: 1.4,
    );
    final linkStyle = textStyle.copyWith(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );

    if (query.isEmpty) {
      return Linkify(
        text: text,
        options: _linkifyOptions,
        style: textStyle,
        linkStyle: linkStyle,
        onOpen: _handleLinkOpen,
      );
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
        style: textStyle,
        children: spans,
      ),
    );
  }

  Future<void> _handleLinkOpen(LinkableElement link) async {
    final uri = _normalizeUri(link.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Uri? _normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final direct = Uri.tryParse(trimmed);
    if (direct != null && direct.hasScheme) {
      return direct;
    }

    return Uri.tryParse('https://$trimmed');
  }

  String? _extractPreviewUrl(String text) {
    final elements = linkify(text, options: _linkifyOptions);
    for (final element in elements) {
      if (element is UrlElement) {
        final normalized = _normalizeUri(element.url);
        if (normalized == null) continue;
        final normalizedText = normalized.toString();
        if (AnyLinkPreview.isValidLink(normalizedText)) {
          return normalizedText;
        }
      }
    }
    return null;
  }

  Widget _buildLinkPreview(String text, ColorScheme colorScheme) {
    final previewUrl = _extractPreviewUrl(text);
    if (previewUrl == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnyLinkPreview(
          link: previewUrl,
          displayDirection: UIDirection.uiDirectionVertical,
          backgroundColor: colorScheme.surface,
          borderRadius: 12,
          removeElevation: true,
          showMultimedia: true,
          bodyMaxLines: 3,
          bodyTextOverflow: TextOverflow.ellipsis,
          titleStyle: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          bodyStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.72),
            fontSize: 12,
            height: 1.35,
          ),
          errorWidget: const SizedBox.shrink(),
          placeholderWidget: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    previewUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.65),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          onTap: () async {
            final uri = Uri.parse(previewUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
      ),
    );
  }

  // ── 번역 버튼 + 번역 결과 ─────────────────────────────────────────────────
  Widget _buildTranslationSection(String text, ColorScheme colorScheme) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 번역 결과
        if (_translatedText != null) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            height: 1,
            color: colorScheme.onSurface.withOpacity(0.08),
          ),
          const SizedBox(height: 6),
          Text(
            _translatedText!,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.75),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        // 번역 버튼
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _translating ? null : () => _translate(text),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_translating)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colorScheme.primary.withOpacity(0.6),
                  ),
                )
              else
                Icon(
                  Icons.translate_rounded,
                  size: 11,
                  color: colorScheme.primary.withOpacity(0.6),
                ),
              const SizedBox(width: 3),
              Text(
                _translating
                    ? l.translating        // '번역 중...'
                    : _translatedText != null
                        ? l.hideTranslation // '번역 숨기기'
                        : l.translate,     // '번역'
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildSharedCard({
    required IconData icon,
    required Color accentColor,
    required String label,
    required String title,
    required String body,
    required ColorScheme colorScheme,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withOpacity(0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (body.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.68),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showSharedMemoPreview() async {
    final memoData = {
      'content': widget.data['memo_content'] ?? '',
      'blocks': widget.data['memo_blocks'] ?? const [],
      'attachments': widget.data['memo_attachments'] ?? const [],
    };
    final blocks = MemoService.blocksFromMemo(memoData);
    final title = widget.data['memo_title'] as String? ?? '';
    final source = widget.data['memo_source'] as String? ?? 'direct';
    final subtitle = switch (source) {
      'chat' => '💬 ${widget.data['memo_room_name'] as String? ?? ''}',
      'board' =>
        '📋 ${widget.data['memo_board_name'] as String? ?? ''} › ${widget.data['memo_post_title'] as String? ?? ''}',
      _ => '메모 공유',
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: widget.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.trim().isNotEmpty ? title : '공유된 메모',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: BlockViewer(blocks: blocks),
              ),
            ),
          ],
        ),
      ),
    );
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

    if (type == 'audio') {
      final durationMs =
          (widget.data['audio_duration_ms'] as num?)?.toInt() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          _AudioMessagePlayer(
            audioUrl: widget.data['audio_url'] as String? ?? fileUrl,
            durationMs: durationMs,
            colorScheme: colorScheme,
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

    if (type == 'shared_post') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          _buildSharedCard(
            icon: Icons.article_outlined,
            accentColor: colorScheme.primary,
            label: widget.data['board_name'] as String? ?? '게시글 공유',
            title: widget.data['post_title'] as String? ?? '',
            body: widget.data['post_content'] as String? ?? '',
            colorScheme: colorScheme,
            onTap: () {
              SharedContentNavigator.openSharedPost(context, widget.data);
            },
          ),
        ],
      );
    }

    if (type == 'shared_schedule') {
      final start = (widget.data['schedule_start_time'] as Timestamp?)?.toDate();
      final end = (widget.data['schedule_end_time'] as Timestamp?)?.toDate();
      final locationName =
          widget.data['schedule_location_name'] as String? ?? '';
      final bodyParts = <String>[
        if (start != null)
          '${start.month}/${start.day} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
        if (end != null)
          '- ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
        if (locationName.isNotEmpty) locationName,
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          _buildSharedCard(
            icon: Icons.event_outlined,
            accentColor: Colors.teal,
            label: widget.data['group_name'] as String? ?? '일정 공유',
            title: widget.data['schedule_title'] as String? ?? '',
            body: bodyParts.join(' '),
            colorScheme: colorScheme,
            onTap: () {
              SharedContentNavigator.openSharedSchedule(context, widget.data);
            },
          ),
        ],
      );
    }

    if (type == 'shared_memo') {
      final source = widget.data['memo_source'] as String? ?? 'direct';
      final label = switch (source) {
        'chat' => widget.data['memo_room_name'] as String? ?? '메모 공유',
        'board' => widget.data['memo_board_name'] as String? ?? '메모 공유',
        _ => '메모 공유',
      };

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyBox != null) replyBox,
          _buildSharedCard(
            icon: Icons.note_outlined,
            accentColor: Colors.deepOrange,
            label: label,
            title: (widget.data['memo_title'] as String? ?? '').trim().isNotEmpty
                ? widget.data['memo_title'] as String? ?? ''
                : '공유된 메모',
            body: widget.data['memo_content'] as String? ?? '',
            colorScheme: colorScheme,
            onTap: () {
              _showSharedMemoPreview();
            },
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
        _buildLinkPreview(text, colorScheme),
        if (isLong) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? l.collapse : l.showMore,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
        // 번역 버튼 + 결과 (내 메시지 아닐 때 + 텍스트 타입 + 언어 감지 완료 시)
        if (_showTranslateButton)
          _buildTranslationSection(text, colorScheme),
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

    final isEdited = widget.data['edited'] == true;
    final l = AppLocalizations.of(context);
    final timeStr = createdAt != null
        ? '${createdAt.toDate().hour.toString().padLeft(2, '0')}:'
            '${createdAt.toDate().minute.toString().padLeft(2, '0')}${isEdited ? ' ${l.messageEdited}' : ''}'
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
        type == 'image' ||
        type == 'video' ||
        type == 'file' ||
        type == 'contact' ||
        type == 'audio';
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

// ── 오디오 메시지 플레이어 ─────────────────────────────────────────────────────
class _AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int durationMs;
  final ColorScheme colorScheme;

  const _AudioMessagePlayer({
    required this.audioUrl,
    required this.durationMs,
    required this.colorScheme,
  });

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _init();
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing &&
            state.processingState != ProcessingState.completed;
      });

      if (state.processingState == ProcessingState.completed) {
        Future.microtask(() async {
          await _player.pause();
          await _player.seek(Duration.zero);
          if (!mounted) return;
          setState(() => _playing = false);
        });
      }
    });
  }

  Future<void> _init() async {
    if (widget.audioUrl.isEmpty) return;
    await _player.setUrl(widget.audioUrl);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_player.playing) {
      await _player.pause();
      return;
    }
    final total = _player.duration;
    if (total != null && _player.position >= total) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final total = _player.duration ??
                    Duration(milliseconds: widget.durationMs);
                final progress = total.inMilliseconds <= 0
                    ? 0.0
                    : position.inMilliseconds / total.inMilliseconds;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: cs.outline.withOpacity(0.12),
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_format(position)} / ${_format(total)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
