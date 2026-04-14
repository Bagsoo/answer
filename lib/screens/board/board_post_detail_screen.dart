import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../models/post_block.dart';
import '../../services/board_service.dart';
import '../../services/chat_service.dart';
import '../../services/memo_service.dart';
import '../../services/report_service.dart';
import '../../widgets/post/block_viewer.dart';
import '../../widgets/chat/chat_room_share_sheet.dart';
import '../../widgets/common/link_text.dart';
import '../report_dialog.dart';
import 'board_post_form_screen.dart';

class BoardPostDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String postId;
  final String boardName;
  final String boardType;
  final String writePermission;
  final String myRole;

  const BoardPostDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.postId,
    required this.boardName,
    required this.boardType,
    required this.writePermission,
    required this.myRole,
  });

  @override
  State<BoardPostDetailScreen> createState() => _BoardPostDetailScreenState();
}

class _BoardPostDetailScreenState extends State<BoardPostDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _boardService = BoardService();
  bool _submittingComment = false;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isOwner => widget.myRole == 'owner';
  bool get canWrite {
    if (widget.writePermission == 'all') return true;
    return isOwner;
  }

  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitComment(String authorName) async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submittingComment = true);
    final ok = await _boardService.addComment(
        widget.groupId, widget.postId, text, authorName);
    if (mounted) {
      setState(() => _submittingComment = false);
      if (ok) {
        _commentCtrl.clear();
      } else {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.commentSaveFailed)));
      }
    }
  }

  void _showReactionPicker(Map<String, dynamic> reactions) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: _emojis.map((emoji) {
                final isSelected = reactions[currentUserId] == emoji;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _boardService.toggleReaction(
                        widget.groupId, widget.postId, emoji);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            if (reactions[currentUserId] != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _boardService.toggleReaction(widget.groupId,
                      widget.postId, reactions[currentUserId]!);
                },
                child: Text(l.remove,
                    style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBoardMemoSheet(
      Map<String, dynamic> post, AppLocalizations l, ColorScheme colorScheme) {
    final content = post['content'] as String? ?? '';
    final title = post['title'] as String? ?? '';
    final authorName = post['author_name'] as String? ?? '';
    final createdAt = post['created_at'] as Timestamp?;
    final controller = TextEditingController(text: content);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(l.memoMessage,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '${widget.groupName} › ${widget.boardName} › $title · $authorName',
                style:
                    TextStyle(fontSize: 12, color: colorScheme.tertiary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 6,
                minLines: 3,
                maxLength: 2000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                  ),
                  filled: true,
                  fillColor:
                      colorScheme.surfaceContainerHighest.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final memoContent = controller.text.trim();
                  if (memoContent.isEmpty) return;

                  // blocks에서 첨부파일 정보 추출
                  final blocks = BoardService.blocksFromPost(post);
                  final attachments = blocks
                      .where((b) => !b.isText)
                      .map((b) => {
                            'type': b.type.name,
                            'url': b.url,
                            'name': b.name,
                            'size': b.size,
                            'mime_type': b.mimeType,
                            if (b.type == BlockType.video)
                              'thumbnail_url': b.thumbnailUrl,
                          })
                      .toList();

                  await context.read<MemoService>().memoFromBoard(
                    content: memoContent,
                    groupId: widget.groupId,
                    groupName: widget.groupName,
                    boardName: widget.boardName,
                    boardType: widget.boardType,
                    postId: widget.postId,
                    postTitle: title,
                    authorName: authorName,
                    originalCreatedAt: createdAt ?? Timestamp.now(),
                    attachments: attachments,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.memoSaved)),
                    );
                  }
                },
                child: Text(l.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPostOptions(Map<String, dynamic> post, AppLocalizations l) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMyPost = post['author_id'] == currentUserId;
    final isPinned = post['is_pinned'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.note_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.memoMessage),
              onTap: () {
                Navigator.pop(ctx);
                _showBoardMemoSheet(post, l, colorScheme);
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.shareMessage),
              onTap: () async {
                Navigator.pop(ctx);
                await _sharePostToChat(post);
              },
            ),
            if (isOwner)
              ListTile(
                leading: Icon(Icons.push_pin_outlined,
                    color: colorScheme.primary),
                title: Text(isPinned ? l.unpinPost : l.pinPost),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _boardService.togglePinPost(
                      widget.groupId, widget.postId, isPinned);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            isPinned ? l.postUnpinned : l.postPinned)));
                  }
                },
              ),
            if (isMyPost || isOwner)
              ListTile(
                leading:
                    Icon(Icons.edit_outlined, color: colorScheme.primary),
                title: Text(l.editPost),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BoardPostFormScreen(
                      groupId: widget.groupId,
                      boardId: post['board_id'] as String,
                      boardName: widget.boardName,
                      boardType: widget.boardType,
                      myRole: widget.myRole,
                      post: post,
                    ),
                  ));
                },
              ),
            if (isMyPost || isOwner)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(l.deletePost,
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeletePost(l, colorScheme);
                },
              ),
            if (!isMyPost)
              ListTile(
                leading:
                    Icon(Icons.flag_outlined, color: colorScheme.error),
                title: Text(l.reportPost,
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportDialog(
                    context: context,
                    onSubmit: (reason, otherText) =>
                        context.read<ReportService>().reportPost(
                      postId: widget.postId,
                      targetOwnerId:
                          post['author_id'] as String? ?? '',
                      groupId: widget.groupId,
                      reason: reason,
                      otherText: otherText,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePostToChat(Map<String, dynamic> post) async {
    final user = context.read<UserProvider>();
    final chatService = context.read<ChatService>();
    final messenger = ScaffoldMessenger.of(context);
    final roomId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ChatRoomShareSheet(),
    );
    if (roomId == null || !mounted) return;

    await chatService.sendSharedPostMessage(
      roomId,
      groupId: widget.groupId,
      groupName: widget.groupName,
      boardId: post['board_id'] as String? ?? '',
      boardName: widget.boardName,
      boardType: widget.boardType,
      postId: widget.postId,
      postTitle: post['title'] as String? ?? '',
      postContent: post['content'] as String? ?? '',
      authorName: post['author_name'] as String? ?? '',
      senderName: user.name,
      senderPhotoUrl: user.photoUrl,
    );
    await chatService.updateLastReadTime(roomId);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('채팅방에 게시글을 공유했습니다.')),
    );
  }

  void _confirmDeletePost(AppLocalizations l, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deletePost),
        content: Text(l.deletePostConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _boardService.deletePost(
                  widget.groupId, widget.postId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:
                        Text(ok ? l.postDeleted : l.postSaveFailed)));
                if (ok) Navigator.pop(context);
              }
            },
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.boardName)),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _boardService.getPost(widget.groupId, widget.postId),
        builder: (context, postSnap) {
          if (postSnap.connectionState == ConnectionState.waiting &&
              !postSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final post = postSnap.data;
          if (post == null) {
            return Center(child: Text(l.noSearchResults));
          }

          final isPinned = post['is_pinned'] as bool? ?? false;
          final reactions =
              post['reactions'] as Map<String, dynamic>? ?? {};
          final createdAt = post['created_at'] as Timestamp?;
          final updatedAt = post['updated_at'] as Timestamp?;
          final myReaction = reactions[currentUserId] as String?;

          // 반응 집계
          final reactionCounts = <String, int>{};
          for (final emoji in reactions.values) {
            reactionCounts[emoji as String] =
                (reactionCounts[emoji] ?? 0) + 1;
          }

          // 블록 변환 (신규 포맷 + 하위 호환)
          final blocks = BoardService.blocksFromPost(post);

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 제목 + 고정 + 더보기 ────────────────────────────
                      Row(children: [
                        if (isPinned) ...[
                          Icon(Icons.push_pin,
                              size: 16, color: colorScheme.primary),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            post['title'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _showPostOptions(post, l),
                        ),
                      ]),

                      // ── 작성자 + 날짜 ───────────────────────────────────
                      Row(children: [
                        Text(
                          post['author_name'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                                  colorScheme.onSurface.withOpacity(0.7)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          createdAt != null
                              ? DateFormat('yyyy.MM.dd HH:mm')
                                  .format(createdAt.toDate())
                              : '',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  colorScheme.onSurface.withOpacity(0.4)),
                        ),
                        if (updatedAt != null &&
                            createdAt != null &&
                            updatedAt.seconds - createdAt.seconds > 5) ...[
                          const SizedBox(width: 4),
                          Text('(수정됨)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurface
                                      .withOpacity(0.3))),
                        ],
                      ]),

                      const Divider(height: 24),

                      // ── 블록 뷰어 (인라인 미디어 포함) ─────────────────
                      BlockViewer(blocks: blocks),

                      const Divider(height: 32),

                      // ── 반응 ────────────────────────────────────────────
                      Row(children: [
                        GestureDetector(
                          onTap: () => _showReactionPicker(reactions),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color:
                                      colorScheme.outline.withOpacity(0.4)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_reaction_outlined,
                                      size: 16,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.5)),
                                  if (myReaction != null) ...[
                                    const SizedBox(width: 4),
                                    Text(myReaction,
                                        style: const TextStyle(
                                            fontSize: 14)),
                                  ],
                                ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...reactionCounts.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: myReaction == e.key
                                      ? colorScheme.primary.withOpacity(0.1)
                                      : colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('${e.key} ${e.value}',
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            )),
                      ]),

                      const Divider(height: 32),

                      // ── 댓글 섹션 ────────────────────────────────────────
                      Row(children: [
                        Icon(Icons.comment_outlined,
                            size: 18, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(l.comments,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ]),
                      const SizedBox(height: 12),

                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _boardService.getComments(
                            widget.groupId, widget.postId),
                        builder: (context, commentSnap) {
                          final comments = commentSnap.data ?? [];
                          if (comments.isEmpty) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              child: Text(l.noComments,
                                  style: TextStyle(
                                      color: colorScheme.onSurface
                                          .withOpacity(0.4))),
                            );
                          }
                          return Column(
                            children: comments.map((comment) {
                              final isMyComment =
                                  comment['author_id'] == currentUserId;
                              final commentAt =
                                  comment['created_at'] as Timestamp?;
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          colorScheme.primary.withOpacity(0.15),
                                      child: Text(
                                        (comment['author_name'] as String? ?? '?')
                                            .characters
                                            .first,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.primary),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Text(
                                              comment['author_name']
                                                      as String? ??
                                                  '',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              commentAt != null
                                                  ? DateFormat('MM/dd HH:mm')
                                                      .format(
                                                          commentAt.toDate())
                                                  : '',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: colorScheme
                                                      .onSurface
                                                      .withOpacity(0.4)),
                                            ),
                                          ]),
                                          const SizedBox(height: 2),
                                          LinkText(
                                            text: comment['content']
                                                    as String? ??
                                                '',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isMyComment || isOwner)
                                      GestureDetector(
                                        onTap: () =>
                                            _confirmDeleteComment(
                                                comment['id'] as String,
                                                l,
                                                colorScheme),
                                        child: Icon(Icons.close,
                                            size: 16,
                                            color: colorScheme.onSurface
                                                .withOpacity(0.3)),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── 댓글 입력창 ───────────────────────────────────────────
              SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                        top: BorderSide(
                            color: colorScheme.outline.withOpacity(0.2))),
                  ),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 8,
                    top: 8,
                    bottom: MediaQuery.of(context).viewInsets.bottom > 0
                        ? MediaQuery.of(context).viewInsets.bottom + 8
                        : 8,
                  ),
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('groups')
                        .doc(widget.groupId)
                        .collection('members')
                        .doc(currentUserId)
                        .snapshots(),
                    builder: (context, mySnap) {
                      final myData = mySnap.data?.data()
                          as Map<String, dynamic>?;
                      final myName =
                          myData?['display_name'] as String? ?? '';
                      return Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _commentCtrl,
                            decoration: InputDecoration(
                              hintText: l.commentHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide(
                                    color: colorScheme.outline
                                        .withOpacity(0.3)),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                              isDense: true,
                            ),
                            maxLines: 3,
                            minLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _submittingComment
                            ? const SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : IconButton(
                                onPressed: () => _submitComment(myName),
                                icon: Icon(Icons.send,
                                    color: colorScheme.primary),
                              ),
                      ]);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteComment(
      String commentId, AppLocalizations l, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteComment),
        content: Text(l.deleteCommentConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await _boardService.deleteComment(
                  widget.groupId, widget.postId, commentId);
              if (mounted && !ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.commentSaveFailed)));
              }
            },
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }
}
