import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_block.dart';
import '../../providers/user_provider.dart';
import '../../services/board_service.dart';
import '../../services/local_preferences_service.dart';
import '../../widgets/post/block_editor.dart';

class BoardPostFormScreen extends StatefulWidget {
  final String groupId;
  final String boardId;
  final String boardName;
  final String boardType;
  final String myRole;
  final Map<String, dynamic>? post;

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
  final _boardService = BoardService();

  // GlobalKey로 BlockEditor 내부 상태 접근
  final _editorKey = GlobalKey<BlockEditorState>();

  bool _saving = false;
  bool _draftReady = false;
  Timer? _draftDebounce;

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isEditing => widget.post != null;
  String get _draftKey => LocalPreferencesService.boardPostDraftKey(
        currentUserId,
        widget.groupId,
        widget.boardId,
        postId: widget.post?['id'] as String?,
      );

  late List<PostBlock> _initialBlocks;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _titleCtrl.text = widget.post!['title'] as String? ?? '';
      _initialBlocks = BoardService.blocksFromPost(widget.post!);
    } else {
      _initialBlocks = [PostBlock.text()];
    }
    _titleCtrl.addListener(_schedulePersistDraft);
    _loadDraft();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _persistDraft();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await LocalPreferencesService.getJsonMap(_draftKey);
    if (!mounted) return;
    if (draft == null) {
      setState(() => _draftReady = true);
      return;
    }

    final draftTitle = draft['title'] as String? ?? '';
    final draftContent = draft['content'] as String? ?? '';

    if (draftTitle.isEmpty && draftContent.isEmpty) {
      setState(() => _draftReady = true);
      return;
    }

    setState(() {
      _titleCtrl.text = draftTitle;
      _titleCtrl.selection =
          TextSelection.collapsed(offset: draftTitle.length);
      _initialBlocks = [
        PostBlock.text(draftContent),
      ];
      _draftReady = true;
    });
  }

  void _schedulePersistDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(
      const Duration(milliseconds: 300),
      _persistDraft,
    );
  }

  Future<void> _persistDraft() async {
    final blocks = _editorKey.currentState?.getBlocks() ?? _initialBlocks;
    final plainText = blocks
        .where((b) => b.isText)
        .map((b) => b.textValue)
        .join('\n')
        .trim();
    if (_titleCtrl.text.trim().isEmpty && plainText.isEmpty) {
      await _clearDraft();
      return;
    }
    await LocalPreferencesService.setJsonMap(_draftKey, {
      'title': _titleCtrl.text,
      'content': plainText,
    });
  }

  Future<void> _clearDraft() async {
    await LocalPreferencesService.remove(_draftKey);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final title = _titleCtrl.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postTitleRequired)));
      return;
    }

    // 업로드 중인 블록 확인
    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    if (editorState.hasUploading) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.uploadingMessage)));
      return;
    }

    final blocks = editorState.getBlocks();

    setState(() => _saving = true);

    try {
      bool ok;
      if (isEditing) {
        ok = await _boardService.updatePost(
          groupId: widget.groupId,
          postId: widget.post!['id'] as String,
          title: title,
          blocks: blocks,
        );
      } else {
        final userProvider = context.read<UserProvider>();
        final newId = await _boardService.createPost(
          groupId: widget.groupId,
          boardId: widget.boardId,
          boardName: widget.boardName,
          boardType: widget.boardType,
          title: title,
          blocks: blocks,
          authorId: currentUserId,
          authorName: userProvider.name,
        );
        ok = newId != null;
      }

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? l.postSaved : l.postSaveFailed)));
        if (ok) {
          await _clearDraft();
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.saveError)));
      }
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
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(l.save,
                  style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: !_draftReady
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 제목 ──────────────────────────────────────────────────────
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: l.postTitle,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // ── 블록 에디터 ────────────────────────────────────────────────
            // GroupId만 전달 — 미디어 추가/업로드 모두 BlockEditor 내부 처리
            BlockEditor(
              key: _editorKey,
              groupId: widget.groupId,
              initialBlocks: _initialBlocks,
              onChanged: _schedulePersistDraft,
            ),
          ],
        ),
      ),
    );
  }
}
