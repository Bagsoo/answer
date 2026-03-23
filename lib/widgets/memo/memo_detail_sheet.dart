import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/memo_service.dart';
import '../../widgets/post/block_viewer.dart';
import 'memo_form_sheet.dart';
import 'memo_navigator.dart';

class MemoDetailSheet extends StatelessWidget {
  final String memoId;
  final Map<String, dynamic> data;
  final MemoService service;

  const MemoDetailSheet({
    super.key,
    required this.memoId,
    required this.data,
    required this.service,
  });

  String _subLabel(AppLocalizations l) {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') {
      return '💬 ${data['room_name'] ?? ''} · ${data['sender_name'] ?? ''}';
    }
    if (source == 'board') {
      return '📋 ${data['board_name'] ?? ''} › ${data['post_title'] ?? ''}';
    }
    return '';
  }

  Color _sourceColor(ColorScheme colorScheme) {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') return colorScheme.primary;
    if (source == 'board') return colorScheme.tertiary;
    return colorScheme.onSurface.withOpacity(0.4);
  }

  List<Map<String, dynamic>> get _attachments =>
      List<Map<String, dynamic>>.from(
          (data['attachments'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)));

  void _openEditSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MemoFormSheet(
        memoId: memoId,
        initialContent: data['content'] as String? ?? '',
        initialAttachments: _attachments,
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final source = data['source'] as String? ?? 'direct';
    final sourceColor = _sourceColor(colorScheme);

    final authorName = source == 'chat'
        ? (data['sender_name'] as String? ?? '')
        : (data['author_name'] as String? ?? '');
    final originalDate = source == 'chat'
        ? data['original_sent_at'] as Timestamp?
        : data['original_created_at'] as Timestamp?;
    final dateStr = originalDate != null
        ? () {
            final d = originalDate.toDate();
            return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }()
        : '';

    final blocks = MemoService.blocksFromMemo(data);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: source == 'direct'
                  ? Text(l.memoSourceDirect,
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5)))
                  : Text(_subLabel(l),
                      style: TextStyle(
                          fontSize: 12,
                          color: sourceColor.withOpacity(0.8)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
            ),
            if (source != 'direct')
              TextButton.icon(
                onPressed: () => _navigateToSource(context),
                icon: Icon(
                    source == 'chat'
                        ? Icons.chat_bubble_outline
                        : Icons.article_outlined,
                    size: 14),
                label: Text(
                    source == 'chat' ? l.memoGoToChat : l.memoGoToBoard,
                    style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: sourceColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
              ),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: colorScheme.primary),
              tooltip: l.editMemo,
              onPressed: () => _openEditSheet(context),
            ),
          ]),
        ),
        if (source != 'direct') ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.person_outline,
                  size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(authorName,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(width: 12),
              Icon(Icons.access_time,
                  size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
              const SizedBox(width: 4),
              Text(dateStr,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6))),
            ]),
          ),
          const SizedBox(height: 4),
        ],
        const Divider(height: 16),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: BlockViewer(blocks: blocks),
          ),
        ),
      ]),
    );
  }

  void _navigateToSource(BuildContext context) {
    navigateToMemoSource(context, data, popFirst: true);
  }
}