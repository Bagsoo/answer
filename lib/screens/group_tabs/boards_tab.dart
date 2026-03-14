import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../board/board_post_list_screen.dart';

class BoardsTab extends StatelessWidget {
  const BoardsTab({super.key});

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // GroupProvider에서 groupId, myRole 읽기
    final gp = context.watch<GroupProvider>();
    final groupId = gp.groupId;
    final groupName = gp.name;
    final isOwner = gp.isOwner;
    final groupService = context.read<GroupService>();

    // myTags는 members 문서에만 있으므로 별도 구독 필요
    // (GroupProvider는 그룹 기본정보 + 내 role/perms만 관리)
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(currentUserId)
          .snapshots(),
      builder: (context, mySnap) {
        final myData = mySnap.data?.data() as Map<String, dynamic>?;
        // myRole은 GroupProvider와 동일하지만 myTags를 읽기 위해 이 스트림은 유지
        final myTags =
            List<String>.from(myData?['tags'] as List? ?? []);

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: groupService.getBoards(groupId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allBoards = snap.data ?? [];

            // sub 타입 게시판: 내 태그 기준 필터링
            final boards = allBoards.where((board) {
              final boardType =
                  board['board_type'] as String? ?? 'free';
              if (boardType != 'sub') return true;
              if (isOwner) return true;
              final allowedTags = List<String>.from(
                  board['allowed_tags'] as List? ?? []);
              return allowedTags.any((tag) => myTags.contains(tag));
            }).toList();

            if (boards.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.article_outlined,
                        size: 64,
                        color: colorScheme.onSurface.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text(l.noBoards,
                        style: TextStyle(
                            color:
                                colorScheme.onSurface.withOpacity(0.4))),
                    const SizedBox(height: 8),
                    Text(l.noBoardsHint,
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface
                                .withOpacity(0.3))),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: boards.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final board = boards[i];
                final boardType =
                    board['board_type'] as String? ?? 'free';
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_boardIcon(boardType),
                        color: colorScheme.primary, size: 22),
                  ),
                  title: Text(
                    board['name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _boardTypeLabel(boardType, l),
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: colorScheme.onSurface.withOpacity(0.3)),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BoardPostListScreen(
                      groupId: groupId,
                      groupName: groupName,
                      boardId: board['id'] as String,
                      boardName: board['name'] as String? ?? '',
                      boardType: boardType,
                      writePermission:
                          board['write_permission'] as String? ??
                              'all',
                      myRole: gp.myRole,
                    ),
                  )),
                );
              },
            );
          },
        );
      },
    );
  }

  IconData _boardIcon(String type) {
    switch (type) {
      case 'notice':
        return Icons.campaign_outlined;
      case 'greeting':
        return Icons.waving_hand_outlined;
      case 'sub':
        return Icons.label_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  String _boardTypeLabel(String type, AppLocalizations l) {
    switch (type) {
      case 'notice':
        return l.boardTypeNotice;
      case 'greeting':
        return l.boardTypeGreeting;
      case 'sub':
        return l.boardTypeSub;
      default:
        return l.boardTypeFree;
    }
  }
}