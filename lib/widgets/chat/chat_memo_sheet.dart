import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_block.dart';
import '../../services/memo_service.dart';
import '../../widgets/post/block_viewer.dart';

class ChatMemoSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String messageId;
  final String groupId;
  final String groupName;
  final String roomId;
  final String roomName;

  const ChatMemoSheet({
    super.key,
    required this.data,
    required this.messageId,
    required this.groupId,
    required this.groupName,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<ChatMemoSheet> createState() => _ChatMemoSheetState();
}

class _ChatMemoSheetState extends State<ChatMemoSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final text = widget.data['text'] as String? ?? '';
    _controller = TextEditingController(text: text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 채팅 메시지에서 첨부파일 추출
  List<Map<String, dynamic>> get _attachments {
    final type = widget.data['type'] as String? ?? 'text';
    final List<Map<String, dynamic>> attachments = [];
    if (type == 'image') {
      final imageUrls =
          List<String>.from(widget.data['image_urls'] as List? ?? []);
      for (final url in imageUrls) {
        attachments.add({
          'type': 'image',
          'url': url,
          'name': 'image',
          'size': 0,
          'mime_type': 'image/jpeg',
        });
      }
    } else if (type == 'video') {
      final videoUrl = widget.data['video_url'] as String? ?? '';
      final thumbnailUrl = widget.data['thumbnail_url'] as String? ?? '';
      if (videoUrl.isNotEmpty) {
        attachments.add({
          'type': 'video',
          'url': videoUrl,
          'thumbnail_url': thumbnailUrl,
          'name': 'video',
          'size': 0,
          'mime_type': 'video/mp4',
        });
      }
    }
    return attachments;
  }

  // 미리보기용 블록 (텍스트 + 첨부파일)
  List<PostBlock> get _previewBlocks {
    final text = widget.data['text'] as String? ?? '';
    return MemoService.blocksFromMemo({
      'content': text,
      'attachments': _attachments,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final senderName = widget.data['sender_name'] as String? ?? '';
    final sentAt = widget.data['created_at'] as Timestamp?;
    final attachments = _attachments;
    final previewBlocks = _previewBlocks;

    // 미리보기에 미디어가 있는지 확인
    final hasMedia = previewBlocks.any((b) => !b.isText);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 핸들 바 ─────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── 헤더 ────────────────────────────────────────────────
            Text(l.memoMessage,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${widget.groupName} › ${widget.roomName} · $senderName',
              style: TextStyle(fontSize: 12, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),

            // ── 원본 미리보기 (미디어 있을 때만 BlockViewer 표시) ────
            if (hasMedia) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.originalMessage,
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withOpacity(0.5),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    BlockViewer(blocks: previewBlocks),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── 메모 내용 입력 ───────────────────────────────────────
            TextField(
              controller: _controller,
              autofocus: !hasMedia,
              maxLines: hasMedia ? 3 : 6,
              minLines: 2,
              maxLength: 2000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: l.memoHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: colorScheme.outline.withOpacity(0.3)),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
              ),
            ),

            const SizedBox(height: 12),

            // ── 저장 버튼 ────────────────────────────────────────────
            FilledButton(
              onPressed: () async {
                final content = _controller.text.trim();
                if (content.isEmpty && attachments.isEmpty) return;

                await context.read<MemoService>().memoFromChat(
                  content: content,
                  groupId: widget.groupId,
                  groupName: widget.groupName,
                  roomId: widget.roomId,
                  roomName: widget.roomName,
                  messageId: widget.messageId,
                  senderName: senderName,
                  originalSentAt: sentAt ?? Timestamp.now(),
                  attachments: attachments,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.memoSaved)));
                }
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}