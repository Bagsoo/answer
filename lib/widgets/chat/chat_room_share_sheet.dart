import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';

class ChatRoomShareSheet extends StatelessWidget {
  const ChatRoomShareSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.shareMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '채팅방을 선택하세요',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: context.read<ChatService>().getChatRooms(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rooms = snapshot.data ?? const [];
                  if (rooms.isEmpty) {
                    return Center(
                      child: Text(
                        '공유할 채팅방이 없습니다.',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: colorScheme.outline.withOpacity(0.12),
                    ),
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      final roomId = room['id'] as String? ?? '';
                      final name = room['name'] as String? ?? '';
                      final roomType = room['type'] as String? ?? 'direct';
                      final groupName = room['group_name'] as String? ?? '';
                      final subtitle = switch (roomType) {
                        'group_all' => groupName.isNotEmpty ? groupName : '그룹 채팅',
                        'group_direct' => '단체 채팅',
                        _ => '개인 채팅',
                      };

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            roomType == 'direct'
                                ? Icons.person_outline
                                : Icons.chat_bubble_outline,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          name.isNotEmpty ? name : l.unknown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: FilledButton(
                          onPressed: roomId.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(roomId),
                          child: Text(l.shareMessage),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
