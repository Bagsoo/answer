import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/incoming_share_payload.dart';
import '../models/post_block.dart';
import '../providers/user_provider.dart';
import '../services/chat_service.dart';
import '../services/memo_service.dart';
import '../services/storage_service.dart';
import '../widgets/chat/chat_room_share_sheet.dart';

class IncomingShareScreen extends StatefulWidget {
  final IncomingSharePayload payload;

  const IncomingShareScreen({
    super.key,
    required this.payload,
  });

  @override
  State<IncomingShareScreen> createState() => _IncomingShareScreenState();
}

class _IncomingShareScreenState extends State<IncomingShareScreen> {
  bool _submitting = false;

  Future<void> _shareToChat() async {
    final roomId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const ChatRoomShareSheet(),
    );
    if (!mounted || roomId == null || roomId.isEmpty) return;

    setState(() => _submitting = true);
    final l = AppLocalizations.of(context);
    final chatService = context.read<ChatService>();
    final user = context.read<UserProvider>();
    final senderName = user.name.trim().isNotEmpty ? user.name : l.unknown;

    try {
      final text = widget.payload.text.trim();
      if (text.isNotEmpty) {
        await chatService.sendMessage(
          roomId,
          text,
          senderName: senderName,
          senderPhotoUrl: user.photoUrl,
        );
      }

      final imageFiles = widget.payload.files.where((f) => f.isImage).toList();
      final otherFiles = widget.payload.files.where((f) => !f.isImage).toList();

      if (imageFiles.isNotEmpty) {
        final messageId = FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(roomId)
            .collection('messages')
            .doc()
            .id;
        final urls = await StorageService().uploadChatImages(
          roomId: roomId,
          messageId: messageId,
          files: imageFiles.map((f) => File(f.path)).toList(),
        );
        await chatService.sendImageMessage(
          roomId,
          messageId: messageId,
          imageUrls: urls,
          senderName: senderName,
          senderPhotoUrl: user.photoUrl,
        );
      }

      for (final sharedFile in otherFiles) {
        final file = File(sharedFile.path);
        if (!await file.exists()) continue;
        final messageId = FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(roomId)
            .collection('messages')
            .doc()
            .id;
        final uploaded = await StorageService().uploadChatFile(
          roomId: roomId,
          messageId: messageId,
          file: file,
          fileName: sharedFile.name,
          mimeType: sharedFile.mimeType,
        );
        await chatService.sendFileMessage(
          roomId,
          messageId: messageId,
          fileUrl: uploaded['url'] ?? '',
          fileName: sharedFile.name,
          fileSize: sharedFile.size > 0 ? sharedFile.size : await file.length(),
          mimeType: sharedFile.mimeType,
          senderName: senderName,
          senderPhotoUrl: user.photoUrl,
        );
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
          .showSnackBar(const SnackBar(content: Text('채팅방에 공유했습니다.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('공유 중 오류가 발생했습니다.')));
    }
  }

  Future<void> _saveToMemo() async {
    setState(() => _submitting = true);

    try {
      final payload = widget.payload;
      final blocks = <PostBlock>[];
      final attachments = <Map<String, dynamic>>[];
      final mediaTypes = <String>[];

      final text = payload.text.trim();
      if (text.isNotEmpty) {
        blocks.add(PostBlock.text(text));
      }

      final imageFiles = payload.files.where((f) => f.isImage).toList();
      final otherFiles = payload.files.where((f) => !f.isImage).toList();
      final storage = StorageService();

      if (imageFiles.isNotEmpty) {
        final messageId = 'memo_${DateTime.now().millisecondsSinceEpoch}';
        final urls = await storage.uploadChatImages(
          roomId: 'memo_${context.read<UserProvider>().uid}',
          messageId: messageId,
          files: imageFiles.map((f) => File(f.path)).toList(),
        );
        for (var i = 0; i < imageFiles.length; i++) {
          final item = imageFiles[i];
          final size = item.size > 0 ? item.size : await File(item.path).length();
          blocks.add(PostBlock(
            type: BlockType.image,
            data: {
              'url': urls[i],
              'name': item.name,
              'size': size,
            },
          ));
          attachments.add({
            'type': 'image',
            'url': urls[i],
            'name': item.name,
            'size': size,
          });
          mediaTypes.add(BlockType.image.name);
        }
      }

      for (final item in otherFiles) {
        final file = File(item.path);
        if (!await file.exists()) continue;
        final messageId =
            'memo_${DateTime.now().microsecondsSinceEpoch}_${item.name.hashCode}';
        final uploaded = await storage.uploadChatFile(
          roomId: 'memo_${context.read<UserProvider>().uid}',
          messageId: messageId,
          file: file,
          fileName: item.name,
          mimeType: item.mimeType,
        );
        final size = item.size > 0 ? item.size : await file.length();
        blocks.add(PostBlock(
          type: BlockType.file,
          data: {
            'url': uploaded['url'] ?? '',
            'name': item.name,
            'size': size,
            'mime_type': item.mimeType,
          },
        ));
        attachments.add({
          'type': 'file',
          'url': uploaded['url'] ?? '',
          'name': item.name,
          'size': size,
          'mime_type': item.mimeType,
        });
        mediaTypes.add(BlockType.file.name);
      }

      await context.read<MemoService>().memoFromExternal(
            title: payload.inferredTitle,
            content: text,
            blocks: blocks,
            attachments: attachments,
            mediaTypes: mediaTypes,
            sourceApp: payload.sourceApp,
            sharedMimeType: payload.mimeType,
          );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
          .showSnackBar(const SnackBar(content: Text('메모에 저장했습니다.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('메모 저장 중 오류가 발생했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final payload = widget.payload;

    return Scaffold(
      appBar: AppBar(
        title: const Text('공유받기'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.inferredTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (payload.sourceApp.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        payload.sourceApp,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.58),
                        ),
                      ),
                    ],
                    if (payload.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        payload.text.trim(),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ],
                  ],
                ),
              ),
              if (payload.files.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '첨부 ${payload.files.length}개',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: payload.files.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = payload.files[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.14),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                file.isImage
                                    ? Icons.image_outlined
                                    : Icons.insert_drive_file_outlined,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    file.mimeType.isNotEmpty
                                        ? file.mimeType
                                        : 'application/octet-stream',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _shareToChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('채팅방으로 보내기'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _saveToMemo,
                icon: const Icon(Icons.note_alt_outlined),
                label: const Text('메모로 저장'),
              ),
              if (_submitting) ...[
                const SizedBox(height: 14),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
