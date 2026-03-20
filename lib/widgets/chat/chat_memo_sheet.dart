import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/memo_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final type = widget.data['type'] as String? ?? 'text';
    final senderName = widget.data['sender_name'] as String? ?? '';
    final sentAt = widget.data['created_at'] as Timestamp?;
    final attachments = _attachments;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(l.memoMessage,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${widget.groupName} › ${widget.roomName} · $senderName',
              style: TextStyle(fontSize: 12, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),
            if (type == 'text' ||
                (widget.data['text'] as String? ?? '').isNotEmpty)
              TextField(
                controller: _controller,
                maxLines: 6,
                minLines: 3,
                maxLength: 2000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outline.withOpacity(0.3)),
                  ),
                  filled: true,
                  fillColor:
                      colorScheme.surfaceContainerHighest.withOpacity(0.4),
                ),
              ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: attachments.map((att) {
                  final attType = att['type'] as String;
                  if (attType == 'image') {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(att['url'] as String,
                          width: 80, height: 80, fit: BoxFit.cover),
                    );
                  } else if (attType == 'video') {
                    final thumb = att['thumbnail_url'] as String? ?? '';
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: thumb.isNotEmpty
                              ? Image.network(thumb,
                                  width: 80, height: 80, fit: BoxFit.cover)
                              : Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.black54,
                                  child: const Icon(Icons.videocam,
                                      color: Colors.white)),
                        ),
                        const Icon(Icons.play_arrow,
                            color: Colors.white, size: 28),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
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