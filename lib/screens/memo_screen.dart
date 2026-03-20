import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_service.dart';
import '../services/image_service.dart';
import '../services/memo_service.dart';
import '../services/storage_service.dart';
import '../services/video_service.dart';
import 'chat_room_screen.dart';
import 'board/board_post_detail_screen.dart';
import '../widgets/group_settings/group_avatar_widget.dart';
import '../widgets/post/post_attachment_widget.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});
  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.read<MemoService>();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: service.memosStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noMemos,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          // 직접 작성 메모
          final directMemos = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['source'] as String? ?? 'direct') == 'direct';
          }).toList();

          // 그룹별 메모
          final Map<String, _GroupMemoGroup> groupMap = {};
          for (final d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final source = data['source'] as String? ?? 'direct';
            if (source == 'direct') continue;
            final groupId = data['group_id'] as String? ?? '__unknown__';
            final groupName =
                data['group_name'] as String? ?? '알 수 없는 그룹';
            groupMap.putIfAbsent(
              groupId,
              () => _GroupMemoGroup(
                  groupId: groupId, groupName: groupName, memos: []),
            );
            groupMap[groupId]!
                .memos
                .add(_MemoEntry(id: d.id, data: data));
          }
          final groupList = groupMap.values.toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              if (directMemos.isNotEmpty)
                _DirectMemoSection(
                  memos: directMemos,
                  service: service,
                  l: l,
                  colorScheme: colorScheme,
                ),
              ...groupList.map((group) => _GroupMemoSection(
                    group: group,
                    service: service,
                    l: l,
                    colorScheme: colorScheme,
                  )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMemoForm(context, service, l, colorScheme),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  void _showMemoForm(
    BuildContext context,
    MemoService service,
    AppLocalizations l,
    ColorScheme colorScheme, {
    String? memoId,
    String initialContent = '',
    List<Map<String, dynamic>> initialAttachments = const [],
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MemoFormSheet(
        memoId: memoId,
        initialContent: initialContent,
        initialAttachments: initialAttachments,
        service: service,
        l: l,
        colorScheme: colorScheme,
      ),
    );
  }
}

class _MemoEntry {
  final String id;
  final Map<String, dynamic> data;
  _MemoEntry({required this.id, required this.data});
}

class _GroupMemoGroup {
  final String groupId;
  final String groupName;
  final List<_MemoEntry> memos;
  _GroupMemoGroup(
      {required this.groupId,
      required this.groupName,
      required this.memos});
}

// ── 직접 작성 메모 섹션 ────────────────────────────────────────────────────────
class _DirectMemoSection extends StatefulWidget {
  final List<QueryDocumentSnapshot> memos;
  final MemoService service;
  final AppLocalizations l;
  final ColorScheme colorScheme;
  const _DirectMemoSection(
      {required this.memos,
      required this.service,
      required this.l,
      required this.colorScheme});
  @override
  State<_DirectMemoSection> createState() => _DirectMemoSectionState();
}

class _DirectMemoSectionState extends State<_DirectMemoSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final l = widget.l;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
              child: Row(children: [
                Icon(Icons.edit_note_outlined,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l.memoSourceDirect,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface.withOpacity(0.7)))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${widget.memos.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary)),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...widget.memos.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return _MemoTile(
                        memoId: d.id,
                        data: data,
                        service: widget.service,
                        l: l,
                        colorScheme: colorScheme);
                  }),
                  const Divider(height: 1),
                ]),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
          ),
        ]);
  }
}

// ── 그룹별 메모 섹션 ───────────────────────────────────────────────────────────
class _GroupMemoSection extends StatefulWidget {
  final _GroupMemoGroup group;
  final MemoService service;
  final AppLocalizations l;
  final ColorScheme colorScheme;
  const _GroupMemoSection(
      {required this.group,
      required this.service,
      required this.l,
      required this.colorScheme});
  @override
  State<_GroupMemoSection> createState() => _GroupMemoSectionState();
}

class _GroupMemoSectionState extends State<_GroupMemoSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final colorScheme = widget.colorScheme;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
              child: Row(children: [
                GroupAvatar(
                  groupId: group.groupId,
                  groupName: group.groupName,
                  radius: 12,
                  fallbackIcon: Icons.group_outlined,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(group.groupName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color:
                                colorScheme.onSurface.withOpacity(0.75)))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: colorScheme.secondary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${group.memos.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.secondary)),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...group.memos.map((entry) => _MemoTile(
                      memoId: entry.id,
                      data: entry.data,
                      service: widget.service,
                      l: widget.l,
                      colorScheme: colorScheme)),
                  const Divider(height: 1),
                ]),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
          ),
        ]);
  }
}

// ── 메모 타일 ─────────────────────────────────────────────────────────────────
class _MemoTile extends StatelessWidget {
  final String memoId;
  final Map<String, dynamic> data;
  final MemoService service;
  final AppLocalizations l;
  final ColorScheme colorScheme;
  const _MemoTile(
      {required this.memoId,
      required this.data,
      required this.service,
      required this.l,
      required this.colorScheme});

  String _subLabel() {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat')
      return '💬 ${data['room_name'] ?? ''} · ${data['sender_name'] ?? ''}';
    if (source == 'board')
      return '📋 ${data['board_name'] ?? ''} › ${data['post_title'] ?? ''}';
    return '';
  }

  Color _sourceColor() {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') return colorScheme.primary;
    if (source == 'board') return colorScheme.tertiary;
    return colorScheme.onSurface.withOpacity(0.4);
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _attachments =>
      List<Map<String, dynamic>>.from(
          (data['attachments'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)));

  @override
  Widget build(BuildContext context) {
    final content = data['content'] as String? ?? '';
    final updatedAt = data['updated_at'] as Timestamp?;
    final source = data['source'] as String? ?? 'direct';
    final subLabel = _subLabel();
    final attachments = _attachments;

    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.isNotEmpty)
              Text(content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14)),
            // 첨부파일 미리보기 (이미지만 썸네일, 나머지는 아이콘)
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildAttachmentPreview(attachments),
            ],
          ],
        ),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: _sourceColor().withOpacity(0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 2),
              Text(_formatDate(updatedAt),
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.35))),
            ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (source != 'direct')
            IconButton(
              icon: Icon(
                  source == 'chat'
                      ? Icons.chat_bubble_outline
                      : Icons.article_outlined,
                  size: 18,
                  color: _sourceColor().withOpacity(0.7)),
              tooltip:
                  source == 'chat' ? '채팅으로 이동' : '게시글로 이동',
              onPressed: () => _navigateToSource(context),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: colorScheme.onSurface.withOpacity(0.35),
                size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ]),
        onTap: () => source == 'direct'
            ? _showEditSheet(context)
            : _showDetailSheet(context),
      ),
      const Divider(height: 1, indent: 16),
    ]);
  }

  // 첨부파일 미리보기 (최대 3개)
  Widget _buildAttachmentPreview(List<Map<String, dynamic>> attachments) {
    final images =
        attachments.where((a) => a['type'] == 'image').take(3).toList();
    final others = attachments
        .where((a) => a['type'] != 'image')
        .take(3)
        .toList();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ...images.map((a) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                a['url'] as String,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 24),
              ),
            )),
        ...others.map((a) {
          final type = a['type'] as String? ?? 'file';
          final thumbUrl = a['thumbnail_url'] as String? ?? '';

          // 동영상이고 썸네일 있으면 썸네일 표시
          if (type == 'video' && thumbUrl.isNotEmpty) {
            return Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    thumbUrl,
                    width: 60, height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 60, height: 60,
                            color: Colors.black54,
                            child: const Icon(Icons.videocam, color: Colors.white, size: 24)),
                  ),
                ),
                const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              ],
            );
          }
          
          final icon = type == 'audio' ? Icons.audio_file : Icons.insert_drive_file;
          return Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 24, color: colorScheme.primary),
          );
        }),
        if (attachments.length > 3)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('+${attachments.length - 3}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary)),
            ),
          ),
      ],
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MemoFormSheet(
        memoId: memoId,
        initialContent: data['content'] as String? ?? '',
        initialAttachments: _attachments,
        service: service,
        l: l,
        colorScheme: colorScheme,
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    final source = data['source'] as String? ?? 'direct';
    final content = data['content'] as String? ?? '';
    final authorName = source == 'chat'
        ? (data['sender_name'] as String? ?? '')
        : (data['author_name'] as String? ?? '');
    final originalDate = source == 'chat'
        ? data['original_sent_at'] as Timestamp?
        : data['original_created_at'] as Timestamp?;
    final sourceColor = _sourceColor();
    final attachments = _attachments;

    final dateStr = originalDate != null
        ? () {
            final d = originalDate.toDate();
            return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }()
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              Expanded(
                  child: Text(_subLabel(),
                      style: TextStyle(
                          fontSize: 12,
                          color: sourceColor.withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _navigateToSource(context);
                },
                icon: Icon(
                    source == 'chat'
                        ? Icons.chat_bubble_outline
                        : Icons.article_outlined,
                    size: 14),
                label: Text(
                    source == 'chat' ? '채팅으로 이동' : '게시글로 이동',
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: sourceColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.person_outline,
                  size: 14,
                  color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(authorName,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(width: 12),
              Icon(Icons.access_time,
                  size: 14,
                  color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(dateStr,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6))),
            ]),
          ),
          const Divider(height: 20),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty)
                    Text(content,
                        style: const TextStyle(
                            fontSize: 15, height: 1.6)),
                  // ── 첨부파일 표시 ──────────────────────────────
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    PostAttachmentsView(
                      attachments: attachments,
                      colorScheme: colorScheme,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _navigateToSource(BuildContext context) {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') {
      final roomId = data['room_id'] as String?;
      final messageId = data['message_id'] as String?;
      if (roomId == null) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
            roomId: roomId,
            initialScrollToMessageId: messageId),
      ));
    } else if (source == 'board') {
      final groupId = data['group_id'] as String?;
      final postId = data['post_id'] as String?;
      if (groupId == null || postId == null) return;
      _navigateToBoard(context, groupId, postId);
    }
  }

  Future<void> _navigateToBoard(
      BuildContext context, String groupId, String postId) async {
    final db = FirebaseFirestore.instance;
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) return;

    final results = await Future.wait([
      db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(authUid)
          .get(),
      db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .get(),
    ]);

    if (!context.mounted) return;

    final myRole =
        (results[0].data())?['role'] as String? ?? 'member';
    final postData =
        results[1].data() as Map<String, dynamic>?;
    final boardId = postData?['board_id'] as String?;

    String writePermission = 'all';
    if (boardId != null) {
      final boardDoc = await db
          .collection('groups')
          .doc(groupId)
          .collection('boards')
          .doc(boardId)
          .get();
      if (!context.mounted) return;
      writePermission = (boardDoc.data())?['write_permission']
              as String? ??
          'all';
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BoardPostDetailScreen(
        groupId: groupId,
        groupName: data['group_name'] as String? ?? '',
        postId: postId,
        boardName: data['board_name'] as String? ?? '',
        boardType: data['board_type'] as String? ?? 'free',
        writePermission: writePermission,
        myRole: myRole,
      ),
    ));
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.deleteMemoConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deleteMemo,
                  style: TextStyle(color: colorScheme.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await service.deleteMemo(memoId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.memoDeleted)));
      }
    }
  }
}

// ── 메모 작성/편집 바텀시트 (첨부파일 지원) ──────────────────────────────────
class _MemoFormSheet extends StatefulWidget {
  final String? memoId;
  final String initialContent;
  final List<Map<String, dynamic>> initialAttachments;
  final MemoService service;
  final AppLocalizations l;
  final ColorScheme colorScheme;

  const _MemoFormSheet({
    required this.memoId,
    required this.initialContent,
    this.initialAttachments = const [],
    required this.service,
    required this.l,
    required this.colorScheme,
  });

  @override
  State<_MemoFormSheet> createState() => _MemoFormSheetState();
}

class _MemoFormSheetState extends State<_MemoFormSheet> {
  late TextEditingController _controller;
  bool _saving = false;

  // 기존 첨부 (수정 시)
  late List<Map<String, dynamic>> _existingAttachments;
  // 새로 추가할 파일
  final List<_PendingAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialContent);
    _existingAttachments =
        List<Map<String, dynamic>>.from(widget.initialAttachments);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _guessMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'mp4': case 'mov': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'aac': return 'audio/aac';
      case 'm4a': return 'audio/mp4';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _pickImages() async {
    final files = await ImageService().pickAndCompressMultipleImages();
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        _pendingAttachments.add(_PendingAttachment(
          type: 'image',
          file: f,
          name: f.path.split('/').last,
          preview: f,
        ));
      }
    });
  }

  Future<void> _pickVideo() async {
    final l = widget.l;
    final videoService = VideoService();
    final file = await videoService.pickVideo();
    if (file == null || !mounted) return;

    if (videoService.isVideoSizeExceeded(file)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.videoSizeExceeded)));
      return;
    }

    setState(() => _saving = true);
    final result = await videoService.compressAndGetThumbnail(file);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.videoProcessingFailed)));
      return;
    }
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        type: 'video',
        file: result['video']!,
        name: file.path.split('/').last,
        thumbnail: result['thumbnail'],
      ));
    });
  }

  Future<void> _pickAudio() async {
    final l = widget.l;
    final result = await AudioService().pickAndValidate();
    if (result == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.audioFileSizeExceeded)));
      }
      return;
    }
    setState(() {
      _pendingAttachments.add(_PendingAttachment(
        type: 'audio',
        file: result['file'] as File,
        name: result['name'] as String,
        mimeType: result['mimeType'] as String,
        size: result['size'] as int,
      ));
    });
  }

  Future<void> _pickFile() async {
    final l = widget.l;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final pf in result.files) {
        if (pf.path == null) continue;
        if ((pf.size / (1024 * 1024)) > 50) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.fileSizeExceeded)));
          continue;
        }
        final file = File(pf.path!);
        final mime = _guessMime(pf.extension ?? '');
        final type =
            mime.startsWith('audio') ? 'audio' : 'file';
        _pendingAttachments.add(_PendingAttachment(
          type: type,
          file: file,
          name: pf.name,
          size: pf.size,
          mimeType: mime,
        ));
      }
    });
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty &&
        _pendingAttachments.isEmpty &&
        _existingAttachments.isEmpty) return;

    setState(() => _saving = true);

    try {
      final storageService = StorageService();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'memo';
      final memoId = widget.memoId ??
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('memos')
              .doc()
              .id;

      // ── 이미지 / 나머지 분리 ──────────────────────────────────────────────
      final imagePendings =
          _pendingAttachments.where((p) => p.type == 'image').toList();
      final otherPendings =
          _pendingAttachments.where((p) => p.type != 'image').toList();

      // ── 이미지 병렬 업로드 ────────────────────────────────────────────────
      final List<Map<String, dynamic>> imageAttachments = [];
      if (imagePendings.isNotEmpty) {
        final urls = await storageService.uploadPostImages(
          groupId: 'memo_$uid',
          postId: memoId,
          files: imagePendings.map((p) => p.file).toList(),
        );
        for (int i = 0; i < imagePendings.length; i++) {
          imageAttachments.add({
            'type': 'image',
            'url': urls[i],
            'name': imagePendings[i].name,
            'size': await imagePendings[i].file.length(),
            'mime_type': 'image/jpeg',
          });
        }
      }

      // ── 동영상 / 오디오 / 파일 순차 업로드 ───────────────────────────────
      final List<Map<String, dynamic>> otherAttachments = [];
      for (final pending in otherPendings) {
        if (pending.type == 'video') {
          String videoUploadUrl = '';
          String thumbUploadUrl = '';
          if (pending.thumbnail != null) {
            final urls = await storageService.uploadPostVideo(
              groupId: 'memo_$uid',
              postId: memoId,
              videoFile: pending.file,
              thumbnailFile: pending.thumbnail!,
            );
            VideoService().clearCache(); // ← await 없이 fire-and-forget
            videoUploadUrl = urls['videoUrl'] ?? '';
            thumbUploadUrl = urls['thumbnailUrl'] ?? '';
          } else {
            final result = await storageService.uploadPostFile(
              groupId: 'memo_$uid',
              postId: memoId,
              file: pending.file,
              fileName: pending.name,
              mimeType: 'video/mp4',
            );
            videoUploadUrl = result['url'] ?? '';
          }
          if (videoUploadUrl.isNotEmpty) {
            otherAttachments.add({
              'type': 'video',
              'url': videoUploadUrl,
              'thumbnail_url': thumbUploadUrl,
              'name': pending.name,
              'size': await pending.file.length(),
              'mime_type': 'video/mp4',
            });
          }
        } else {
          final result = await storageService.uploadPostFile(
            groupId: 'memo_$uid',
            postId: memoId,
            file: pending.file,
            fileName: pending.name,
            mimeType: pending.mimeType ?? 'application/octet-stream',
          );
          otherAttachments.add({
            'type': pending.type,
            'url': result['url']!,
            'name': pending.name,
            'size': pending.size ?? await pending.file.length(),
            'mime_type': pending.mimeType ?? 'application/octet-stream',
          });
        }
      }

      final allAttachments = [
        ..._existingAttachments,
        ...imageAttachments,
        ...otherAttachments,
      ];

      await widget.service.saveMemo(
        memoId: widget.memoId,
        content: content,
        attachments: allAttachments,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.l.memoSaved)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.l.saveError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final colorScheme = widget.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                  borderRadius: BorderRadius.circular(2)),
            )),
            Text(
                widget.memoId != null ? l.editMemo : l.newMemo,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 2000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: l.memoHint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: colorScheme.outline.withOpacity(0.3))),
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withOpacity(0.4),
              ),
            ),

            // ── 기존 첨부파일 ─────────────────────────────────────────
            if (_existingAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('기존 첨부파일',
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _existingAttachments
                    .asMap()
                    .entries
                    .map((entry) {
                  final i = entry.key;
                  final att = entry.value;
                  final type = att['type'] as String? ?? 'file';
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: type == 'image'
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                    att['url'] as String,
                                    fit: BoxFit.cover),
                              )
                            : Icon(
                                type == 'video'
                                    ? Icons.videocam
                                    : type == 'audio'
                                        ? Icons.audio_file
                                        : Icons.insert_drive_file,
                                color: colorScheme.primary,
                                size: 28),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => setState(() =>
                              _existingAttachments.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                                color: colorScheme.error,
                                shape: BoxShape.circle),
                            child: Icon(Icons.close,
                                size: 12,
                                color: colorScheme.onError),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],

            // ── 새 첨부파일 미리보기 ──────────────────────────────────
            if (_pendingAttachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('추가할 파일 (${_pendingAttachments.length})',
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _pendingAttachments
                    .asMap()
                    .entries
                    .map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: p.type == 'image' &&
                                  p.preview != null
                              ? Image.file(p.preview!,
                                  fit: BoxFit.cover)
                              : p.type == 'video' &&
                                      p.thumbnail != null
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Image.file(p.thumbnail!,
                                            fit: BoxFit.cover,
                                            width: 60,
                                            height: 60),
                                        const Icon(Icons.play_arrow,
                                            color: Colors.white,
                                            size: 24),
                                      ],
                                    )
                                  : Icon(
                                      p.type == 'audio'
                                          ? Icons.audio_file
                                          : Icons.insert_drive_file,
                                      color: colorScheme.primary,
                                      size: 28),
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => setState(() =>
                              _pendingAttachments.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                                color: colorScheme.error,
                                shape: BoxShape.circle),
                            child: Icon(Icons.close,
                                size: 12,
                                color: colorScheme.onError),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],

            // ── 첨부 버튼 바 ──────────────────────────────────────────
            const SizedBox(height: 8),
            Row(
              children: [
                _AttachBtn(icon: Icons.photo_outlined, label: '사진', color: Colors.green, onTap: _saving ? null : _pickImages),
                _AttachBtn(icon: Icons.videocam_outlined, label: '동영상', color: Colors.red, onTap: _saving ? null : _pickVideo),
                _AttachBtn(icon: Icons.mic_outlined, label: '오디오', color: Colors.orange, onTap: _saving ? null : _pickAudio),
                _AttachBtn(icon: Icons.attach_file, label: '파일', color: colorScheme.primary, onTap: _saving ? null : _pickFile),
              ],
            ),

            // ── 저장 버튼 ──────────────────────────────────────────────
            const SizedBox(height: 8),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : Text(l.save),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 하단 첨부 버튼 ─────────────────────────────────────────────────────────────
class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachBtn(
      {required this.icon,
      required this.label,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: onTap == null ? Colors.grey : color,
                  size: 22),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: onTap == null
                          ? Colors.grey
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 업로드 대기 첨부파일 모델 ──────────────────────────────────────────────────
class _PendingAttachment {
  final String type;
  final File file;
  final String name;
  final int? size;
  final String? mimeType;
  final File? preview;
  final File? thumbnail;

  _PendingAttachment({
    required this.type,
    required this.file,
    required this.name,
    this.size,
    this.mimeType,
    this.preview,
    this.thumbnail,
  });
}