import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';

class ChatRoomParticipantsScreen extends StatelessWidget {
  final String roomId;
  final String roomType;    // group_sub인지 확인용
  final String currentUserId;
  final String myRole;      // 내 role (owner 여부)

  const ChatRoomParticipantsScreen({
    super.key,
    required this.roomId,
    required this.roomType,
    required this.currentUserId,
    required this.myRole,
  });

  // group_sub 채팅방 방장 위임
  Future<void> _transferRoomOwnership(
    BuildContext context,
    String newOwnerUid,
    String newOwnerName,
    AppLocalizations l,
    ColorScheme colorScheme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.transferOwnership),
        content: Text(l.transferOwnershipConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(l.transferOwnership),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final roomRef = db.collection('chat_rooms').doc(roomId);

      batch.update(roomRef.collection('room_members').doc(newOwnerUid), {'role': 'owner'});
      batch.update(roomRef.collection('room_members').doc(currentUserId), {'role': 'member'});

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // 참여자 화면 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.transferOwnershipSuccess)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.transferOwnershipFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isGroupSub = roomType == 'group_sub';
    final amOwner = myRole == 'owner';

    return Scaffold(
      appBar: AppBar(title: Text(l.viewParticipants)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(roomId)
            .collection('room_members')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final members = snapshot.data?.docs ?? [];
          if (members.isEmpty) {
            return Center(
              child: Text(l.noMembers,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
            );
          }

          // owner 먼저 정렬
          final sorted = [...members]..sort((a, b) {
              final aRole = (a.data() as Map<String, dynamic>)['role'] as String? ?? '';
              final bRole = (b.data() as Map<String, dynamic>)['role'] as String? ?? '';
              if (aRole == 'owner') return -1;
              if (bRole == 'owner') return 1;
              return 0;
            });

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final data = sorted[index].data() as Map<String, dynamic>;
              final uid = sorted[index].id;
              final role = data['role'] as String? ?? 'member';
              // display_name을 room_members에서 직접 읽음 — users 조회 불필요
              final name = data['display_name'] as String? ?? uid.substring(0, 8);
              final isMe = uid == currentUserId;
              final isOwner = role == 'owner';

              // group_sub 방장 위임 버튼: 내가 owner이고, 상대가 나 자신이 아닐 때
              final canTransfer = isGroupSub && amOwner && !isMe;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isOwner
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOwner ? colorScheme.onPrimary : colorScheme.onSurface,
                    ),
                  ),
                ),
                title: Text(
                  isMe ? '$name (${l.me})' : name,
                  style: TextStyle(
                      fontWeight: isOwner ? FontWeight.bold : FontWeight.normal),
                ),
                subtitle: Text(
                  isOwner ? l.roleOwner : l.roleMember,
                  style: TextStyle(
                    color: isOwner
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                trailing: isOwner
                    ? Icon(Icons.star_rounded, color: colorScheme.primary, size: 18)
                    : canTransfer
                        ? TextButton(
                            onPressed: () => _transferRoomOwnership(
                              context, uid, name, l, colorScheme,
                            ),
                            child: Text(l.transferOwnership,
                                style: TextStyle(
                                    fontSize: 12, color: colorScheme.primary)),
                          )
                        : null,
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          );
        },
      ),
    );
  }
}