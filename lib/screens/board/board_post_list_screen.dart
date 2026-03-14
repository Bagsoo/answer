import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_localizations.dart';
import '../../services/group_service.dart';
import 'board_post_detail_screen.dart';
import 'board_post_form_screen.dart';

class BoardPostListScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String boardId;
  final String boardName;
  final String boardType;
  final String writePermission;
  final String myRole;

  const BoardPostListScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.boardId,
    required this.boardName,
    required this.boardType,
    required this.writePermission,
    required this.myRole,
  });

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get canWrite {
    if (writePermission == 'all') return true;
    return myRole == 'owner';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = GroupService();

    return Scaffold(
      appBar: AppBar(title: Text(boardName)),
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BoardPostFormScreen(
                  groupId: groupId,
                  boardId: boardId,
                  boardName: boardName,
                  boardType: boardType,
                  myRole: myRole,
                ),
              )),
              child: const Icon(Icons.edit),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.getPosts(groupId, boardId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noPosts,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: posts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final post = posts[i];
              final isPinned = post['is_pinned'] as bool? ?? false;
              final commentCount = post['comment_count'] as int? ?? 0;
              final reactions = post['reactions'] as Map<String, dynamic>? ?? {};
              final createdAt = post['created_at'] as Timestamp?;

              return InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BoardPostDetailScreen(
                    groupId: groupId,
                    groupName: groupName,
                    postId: post['id'] as String,
                    boardName: boardName,
                    boardType: boardType,
                    writePermission: writePermission,
                    myRole: myRole,
                  ),
                )),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 고정 배지 + 제목
                      Row(children: [
                        if (isPinned) ...[
                          Icon(Icons.push_pin, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            post['title'] as String? ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: isPinned
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      // 내용 미리보기
                      Text(
                        post['content'] as String? ?? '',
                        style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.6)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // 작성자 + 날짜 + 댓글/반응 수
                      Row(children: [
                        Text(
                          post['author_name'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.5)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          createdAt != null
                              ? DateFormat('MM/dd HH:mm').format(createdAt.toDate())
                              : '',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.4)),
                        ),
                        const Spacer(),
                        if (reactions.isNotEmpty) ...[
                          Icon(Icons.favorite_outline, size: 13,
                              color: colorScheme.onSurface.withOpacity(0.4)),
                          const SizedBox(width: 2),
                          Text(
                            '${reactions.length}',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withOpacity(0.4)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (commentCount > 0) ...[
                          Icon(Icons.comment_outlined, size: 13,
                              color: colorScheme.onSurface.withOpacity(0.4)),
                          const SizedBox(width: 2),
                          Text(
                            '$commentCount',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withOpacity(0.4)),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}