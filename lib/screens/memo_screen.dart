import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/memo_service.dart';
import 'chat_room_screen.dart';
import 'board/board_post_detail_screen.dart';

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

          // ── 직접 작성 메모
          final directMemos = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['source'] as String? ?? 'direct') == 'direct';
          }).toList();

          // ── 그룹별 메모
          final Map<String, _GroupMemoGroup> groupMap = {};
          for (final d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final source = data['source'] as String? ?? 'direct';
            if (source == 'direct') continue;
            final groupId = data['group_id'] as String? ?? '__unknown__';
            final groupName = data['group_name'] as String? ?? '알 수 없는 그룹';
            groupMap.putIfAbsent(groupId, () => _GroupMemoGroup(
              groupId: groupId, groupName: groupName, memos: [],
            ));
            groupMap[groupId]!.memos.add(_MemoEntry(id: d.id, data: data));
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
                group: group, service: service, l: l, colorScheme: colorScheme,
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

  void _showMemoForm(BuildContext context, MemoService service, AppLocalizations l, ColorScheme colorScheme, {String? memoId, String initialContent = ''}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MemoFormSheet(memoId: memoId, initialContent: initialContent, service: service, l: l, colorScheme: colorScheme),
    );
  }
}

class _MemoEntry { final String id; final Map<String, dynamic> data; _MemoEntry({required this.id, required this.data}); }
class _GroupMemoGroup { final String groupId; final String groupName; final List<_MemoEntry> memos; _GroupMemoGroup({required this.groupId, required this.groupName, required this.memos}); }

// ── 섹션 헤더 ─────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon; final String title; final ColorScheme colorScheme; final int? count;
  const _SectionHeader({required this.icon, required this.title, required this.colorScheme, this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      child: Row(children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface.withOpacity(0.7)))),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary)),
          ),
      ]),
    );
  }
}

// ── 그룹 메모 섹션 (펼치기/접기) ───────────────────────────────────────────────
// ── 직접 작성 메모 섹션 ────────────────────────────────────────────────────────
class _DirectMemoSection extends StatefulWidget {
  final List<QueryDocumentSnapshot> memos;
  final MemoService service;
  final AppLocalizations l;
  final ColorScheme colorScheme;
  const _DirectMemoSection({required this.memos, required this.service, required this.l, required this.colorScheme});
  @override State<_DirectMemoSection> createState() => _DirectMemoSectionState();
}

class _DirectMemoSectionState extends State<_DirectMemoSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final l = widget.l;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
          child: Row(children: [
            Icon(Icons.edit_note_outlined, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(l.memoSourceDirect,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface.withOpacity(0.7)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${widget.memos.length}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: colorScheme.primary)),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _expanded ? 0.0 : -0.25,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 20,
                  color: colorScheme.onSurface.withOpacity(0.4)),
            ),
          ]),
        ),
      ),
      AnimatedCrossFade(
        firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...widget.memos.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return _MemoTile(memoId: d.id, data: data, service: widget.service, l: l, colorScheme: colorScheme);
          }),
          const Divider(height: 1),
        ]),
        secondChild: const SizedBox.shrink(),
        crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 220),
      ),
    ]);
  }
}

// ── 그룹별 메모 섹션 ───────────────────────────────────────────────────────────
class _GroupMemoSection extends StatefulWidget {
  final _GroupMemoGroup group; final MemoService service; final AppLocalizations l; final ColorScheme colorScheme;
  const _GroupMemoSection({required this.group, required this.service, required this.l, required this.colorScheme});
  @override State<_GroupMemoSection> createState() => _GroupMemoSectionState();
}

class _GroupMemoSectionState extends State<_GroupMemoSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final colorScheme = widget.colorScheme;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 그룹 헤더
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
          child: Row(children: [
            Icon(Icons.group_outlined, size: 16, color: colorScheme.secondary),
            const SizedBox(width: 8),
            Expanded(child: Text(group.groupName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface.withOpacity(0.75)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: colorScheme.secondary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Text('${group.memos.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.secondary)),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _expanded ? 0.0 : -0.25,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 20, color: colorScheme.onSurface.withOpacity(0.4)),
            ),
          ]),
        ),
      ),
      // 메모 목록
      AnimatedCrossFade(
        firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...group.memos.map((entry) => _MemoTile(memoId: entry.id, data: entry.data, service: widget.service, l: widget.l, colorScheme: colorScheme)),
          const Divider(height: 1),
        ]),
        secondChild: const SizedBox.shrink(),
        crossFadeState: _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 220),
      ),
    ]);
  }
}

// ── 메모 타일 ─────────────────────────────────────────────────────────────────
class _MemoTile extends StatelessWidget {
  final String memoId; final Map<String, dynamic> data; final MemoService service; final AppLocalizations l; final ColorScheme colorScheme;
  const _MemoTile({required this.memoId, required this.data, required this.service, required this.l, required this.colorScheme});

  String _subLabel() {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') return '💬 ${data['room_name'] ?? ''} · ${data['sender_name'] ?? ''}';
    if (source == 'board') return '📋 ${data['board_name'] ?? ''} › ${data['post_title'] ?? ''}';
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
    return '${d.year}.${d.month.toString().padLeft(2,'0')}.${d.day.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final content = data['content'] as String? ?? '';
    final updatedAt = data['updated_at'] as Timestamp?;
    final source = data['source'] as String? ?? 'direct';
    final subLabel = _subLabel();

    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        title: Text(content, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subLabel, style: TextStyle(fontSize: 11, color: _sourceColor().withOpacity(0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 2),
          Text(_formatDate(updatedAt), style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(0.35))),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (source != 'direct')
            IconButton(
              icon: Icon(source == 'chat' ? Icons.chat_bubble_outline : Icons.article_outlined, size: 18, color: _sourceColor().withOpacity(0.7)),
              tooltip: source == 'chat' ? '채팅으로 이동' : '게시글로 이동',
              onPressed: () => _navigateToSource(context),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colorScheme.onSurface.withOpacity(0.35), size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ]),
        onTap: () => source == 'direct' ? _showEditSheet(context) : _showDetailSheet(context),
      ),
      const Divider(height: 1, indent: 16),
    ]);
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MemoFormSheet(memoId: memoId, initialContent: data['content'] as String? ?? '', service: service, l: l, colorScheme: colorScheme),
    );
  }

  void _showDetailSheet(BuildContext context) {
    final source = data['source'] as String? ?? 'direct';
    final content = data['content'] as String? ?? '';
    final authorName = source == 'chat' ? (data['sender_name'] as String? ?? '') : (data['author_name'] as String? ?? '');
    final originalDate = source == 'chat' ? data['original_sent_at'] as Timestamp? : data['original_created_at'] as Timestamp?;
    final sourceColor = _sourceColor();

    final dateStr = originalDate != null ? () {
      final d = originalDate.toDate();
      return '${d.year}.${d.month.toString().padLeft(2,'0')}.${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }() : '';

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.92, expand: false,
        builder: (_, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 36, height: 4,
            decoration: BoxDecoration(color: colorScheme.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(children: [
              Expanded(child: Text(_subLabel(), style: TextStyle(fontSize: 12, color: sourceColor.withOpacity(0.8)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              TextButton.icon(
                onPressed: () { Navigator.pop(ctx); _navigateToSource(context); },
                icon: Icon(source == 'chat' ? Icons.chat_bubble_outline : Icons.article_outlined, size: 14),
                label: Text(source == 'chat' ? '채팅으로 이동' : '게시글로 이동', style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: sourceColor, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.person_outline, size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(authorName, style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(width: 12),
              Icon(Icons.access_time, size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(dateStr, style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.6))),
            ]),
          ),
          const Divider(height: 20),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Text(content, style: const TextStyle(fontSize: 15, height: 1.6)),
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
        builder: (_) => ChatRoomScreen(roomId: roomId, initialScrollToMessageId: messageId),
      ));
    } else if (source == 'board') {
      final groupId = data['group_id'] as String?;
      final postId = data['post_id'] as String?;
      if (groupId == null || postId == null) return;
      _navigateToBoard(context, groupId, postId);
    }
  }

  Future<void> _navigateToBoard(BuildContext context, String groupId, String postId) async {
    final db = FirebaseFirestore.instance;
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) return;

    // 내 role 조회 + post 조회 (board_id, board write_permission 확인용) 병렬
    final results = await Future.wait([
      db.collection('groups').doc(groupId).collection('members').doc(authUid).get(),
      db.collection('groups').doc(groupId).collection('posts').doc(postId).get(),
    ]);

    if (!context.mounted) return;

    final myRole = (results[0].data())?['role'] as String? ?? 'member';
    final postData = results[1].data() as Map<String, dynamic>?;
    final boardId = postData?['board_id'] as String?;

    String writePermission = 'all';
    if (boardId != null) {
      final boardDoc = await db
          .collection('groups').doc(groupId)
          .collection('boards').doc(boardId)
          .get();
      if (!context.mounted) return;
      writePermission = (boardDoc.data())?['write_permission'] as String? ?? 'all';
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.deleteMemo, style: TextStyle(color: colorScheme.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await service.deleteMemo(memoId);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.memoDeleted)));
    }
  }
}

// ── 메모 작성/편집 바텀시트 ──────────────────────────────────────────────────
class _MemoFormSheet extends StatefulWidget {
  final String? memoId; final String initialContent; final MemoService service; final AppLocalizations l; final ColorScheme colorScheme;
  const _MemoFormSheet({required this.memoId, required this.initialContent, required this.service, required this.l, required this.colorScheme});
  @override State<_MemoFormSheet> createState() => _MemoFormSheetState();
}

class _MemoFormSheetState extends State<_MemoFormSheet> {
  late TextEditingController _controller;
  bool _saving = false;

  @override void initState() { super.initState(); _controller = TextEditingController(text: widget.initialContent); }
  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l = widget.l; final colorScheme = widget.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: colorScheme.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(2)))),
          Text(widget.memoId != null ? l.editMemo : l.newMemo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller, autofocus: true, maxLines: 8, minLines: 4, maxLength: 2000,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: InputDecoration(
              hintText: l.memoHint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3))),
              filled: true, fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : () async {
              final content = _controller.text.trim();
              if (content.isEmpty) return;
              setState(() => _saving = true);
              await widget.service.saveMemo(memoId: widget.memoId, content: content);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.memoSaved)));
              }
            },
            child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l.save),
          ),
        ]),
      ),
    );
  }
}