import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
        _highlightController.forward().then((_) => _highlightController.reverse());
      });
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHighlighted && !oldWidget.isHighlighted) {
      _highlightController.forward().then((_) => _highlightController.reverse());
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

  // ── 아바타: 프로필 사진 있으면 사진, 없으면 이니셜 ───────────────────────
  Widget _buildAvatar(String senderName, ColorScheme colorScheme) {
    final photoUrl = widget.data['sender_photo_url'] as String?;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return GestureDetector(
      onTap: widget.onAvatarTap,
      child: CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.secondaryContainer,
        // 프로필 사진이 있으면 NetworkImage, 없으면 이니셜
        backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
        onBackgroundImageError: hasPhoto
            ? (_, __) {} // 이미지 로드 실패 시 이니셜로 폴백
            : null,
        child: hasPhoto
            ? null // 사진 있으면 child 숨김
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

  @override
  Widget build(BuildContext context) {
    final text = widget.data['text'] as String? ?? '';
    final createdAt = widget.data['created_at'] as Timestamp?;
    final senderName = widget.data['sender_name'] as String? ?? '';
    final isMe = widget.isMe;
    final isContinuous = widget.isContinuous;
    final colorScheme = widget.colorScheme;

    // 답장 데이터
    final replyToText = widget.data['reply_to_text'] as String?;
    final replyToSender = widget.data['reply_to_sender'] as String?;
    final hasReply = replyToText != null && replyToText.isNotEmpty;

    final isLong = text.length > _collapseThreshold;
    final displayText =
        isLong && !_expanded ? '${text.substring(0, _collapseThreshold)}...' : text;

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
    Widget bubbleContent = Column(
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
            // ── 상대방 메시지 ────────────────────────────────────────────
            if (!isMe) ...[
              SizedBox(
                width: 36,
                // 연속 메시지면 아바타 숨김 (공간만 유지)
                child: isContinuous ? null : _buildAvatar(senderName, colorScheme),
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
                          maxWidth: MediaQuery.of(context).size.width * 0.62,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 9),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isContinuous ? 16 : 4),
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
                              color: colorScheme.onSurface.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],

            // ── 내 메시지 ────────────────────────────────────────────────
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
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