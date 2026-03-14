import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../services/group_service.dart';

class BoardPostFormScreen extends StatefulWidget {
  final String groupId;
  final String boardId;
  final String boardName;
  final String boardType;
  final String myRole;
  final Map<String, dynamic>? post; // null이면 작성, 있으면 수정

  const BoardPostFormScreen({
    super.key,
    required this.groupId,
    required this.boardId,
    required this.boardName,
    required this.boardType,
    required this.myRole,
    this.post,
  });

  @override
  State<BoardPostFormScreen> createState() => _BoardPostFormScreenState();
}

class _BoardPostFormScreenState extends State<BoardPostFormScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _service = GroupService();
  bool _saving = false;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isEditing => widget.post != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _titleCtrl.text = widget.post!['title'] as String? ?? '';
      _contentCtrl.text = widget.post!['content'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postTitleRequired)));
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postContentRequired)));
      return;
    }

    setState(() => _saving = true);

    bool ok;
    if (isEditing) {
      ok = await _service.updatePost(
        widget.groupId,
        widget.post!['id'] as String,
        {'title': title, 'content': content},
      );
    } else {
      final userProvider = context.read<UserProvider>();
      final postId = await _service.createPost(widget.groupId, {
        'board_id': widget.boardId,
        'board_name': widget.boardName,
        'board_type': widget.boardType,
        'title': title,
        'content': content,
        'author_id': currentUserId,
        'author_name': userProvider.name,
        'visible_tags': [], // sub 타입은 board의 allowed_tags와 동일
      });
      ok = postId != null;
    }

    if (mounted) {
      setState(() => _saving = false);
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? (isEditing ? l.postSaved : l.postSaved)
              : l.postSaveFailed)));
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l.editPost : l.createPost),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(
                  onPressed: _save,
                  child: Text(l.save,
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 제목
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: l.postTitle,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          // 내용
          TextField(
            controller: _contentCtrl,
            decoration: InputDecoration(
              labelText: l.postContent,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: 10,
            maxLines: null,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }
}