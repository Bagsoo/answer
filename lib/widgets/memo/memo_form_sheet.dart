import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_block.dart';
import '../../services/memo_service.dart';
import '../../widgets/post/block_editor.dart';

class MemoFormSheet extends StatefulWidget {
  final String? memoId;
  final String initialTitle;
  final String initialContent;
  final List<Map<String, dynamic>> initialAttachments;
  final List<Map<String, dynamic>> initialBlocks;
  final MemoService service;
  final bool embedded;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onSaved;

  const MemoFormSheet({
    super.key,
    required this.memoId,
    this.initialTitle = '',
    required this.initialContent,
    this.initialAttachments = const [],
    this.initialBlocks = const [],
    required this.service,
    this.embedded = false,
    this.onCancel,
    this.onSaved,
  });

  @override
  State<MemoFormSheet> createState() => _MemoFormSheetState();
}

class _MemoFormSheetState extends State<MemoFormSheet> {
  final _titleCtrl = TextEditingController();
  final _editorKey = GlobalKey<BlockEditorState>();
  bool _saving = false;
  late List<PostBlock> _initialBlocks;

  final String _storageGroupId =
      'memo_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.initialTitle;
    if (widget.memoId != null) {
      _initialBlocks = MemoService.blocksFromMemo({
        'blocks': widget.initialBlocks,
        'content': widget.initialContent,
        'attachments': widget.initialAttachments,
      });
    } else {
      _initialBlocks = [PostBlock.text()];
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    if (editorState.hasUploading) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.uploadingMessage)));
      return;
    }

    final blocks = editorState.getBlocks();
    final title = _titleCtrl.text.trim();

    // 제목과 내용 모두 비어있으면 저장 안 함
    final hasContent =
        title.isNotEmpty || blocks.any((b) => !b.isText || b.textValue.isNotEmpty);
    if (!hasContent) return;

    final plainText = blocks
        .where((b) => b.isText)
        .map((b) => b.textValue)
        .join('\n')
        .trim();

    setState(() => _saving = true);

    try {
      final savedId = await widget.service.saveMemo(
        memoId: widget.memoId,
        title: title,
        content: plainText,
        blocks: blocks,
      );
      if (mounted) {
        if (widget.embedded) {
          widget.onSaved?.call(savedId);
        } else {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.memoSaved)));
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

    return Padding(
      padding: widget.embedded
          ? EdgeInsets.zero
          : EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: widget.embedded
              ? double.infinity
              : MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 핸들 바 ───────────────────────────────────────────────
            if (!widget.embedded)
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            // ── 헤더 ──────────────────────────────────────────────────
            Row(children: [
              if (widget.embedded && widget.onCancel != null)
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  tooltip: l.cancel,
                ),
              Expanded(
                child: Text(
                  widget.memoId != null ? l.editMemo : l.newMemo,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (_saving)
                const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: _save,
                  child: Text(l.save,
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),

            // ── 제목 입력 ─────────────────────────────────────────────
            TextField(
              controller: _titleCtrl,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: l.memoTitleHint,
                hintStyle: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.35),
                    fontWeight: FontWeight.w400),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
            Divider(
                height: 12,
                color: colorScheme.outline.withOpacity(0.2)),

            // ── BlockEditor (스크롤 가능) ──────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: BlockEditor(
                  key: _editorKey,
                  groupId: _storageGroupId,
                  initialBlocks: _initialBlocks,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
