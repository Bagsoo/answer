import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/post_block.dart';
import '../../services/memo_service.dart';
import '../../widgets/post/block_editor.dart';

class MemoFormSheet extends StatefulWidget {
  final String? memoId;
  final String initialContent;
  final List<Map<String, dynamic>> initialAttachments;
  final MemoService service;

  const MemoFormSheet({
    super.key,
    required this.memoId,
    required this.initialContent,
    this.initialAttachments = const [],
    required this.service,
  });

  @override
  State<MemoFormSheet> createState() => _MemoFormSheetState();
}

class _MemoFormSheetState extends State<MemoFormSheet> {
  final _editorKey = GlobalKey<BlockEditorState>();
  bool _saving = false;
  late List<PostBlock> _initialBlocks;

  // 메모용 Storage 경로 (uid 대신 타임스탬프 기반)
  final String _storageGroupId =
      'memo_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    if (widget.memoId != null) {
      // 수정 시: 기존 content + attachments → 블록 변환
      _initialBlocks = MemoService.blocksFromMemo({
        'content': widget.initialContent,
        'attachments': widget.initialAttachments,
      });
    } else {
      _initialBlocks = [PostBlock.text()];
    }
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

    // 텍스트 블록만 있고 전부 비어있으면 저장 안 함
    final hasContent =
        blocks.any((b) => !b.isText || b.textValue.isNotEmpty);
    if (!hasContent) return;

    final plainText = blocks
        .where((b) => b.isText)
        .map((b) => b.textValue)
        .join('\n')
        .trim();

    setState(() => _saving = true);

    try {
      await widget.service.saveMemo(
        memoId: widget.memoId,
        content: plainText,
        blocks: blocks,
      );
      if (mounted) {
        Navigator.pop(context);
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 핸들 바 ───────────────────────────────────────────────
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

            // ── 헤더 (제목 + 저장 버튼) ───────────────────────────────
            Row(children: [
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton(
                  onPressed: _save,
                  child: Text(l.save,
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            const Divider(height: 16),

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