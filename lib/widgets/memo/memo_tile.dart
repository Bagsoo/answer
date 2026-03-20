import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/memo_service.dart';
import 'memo_detail_sheet.dart';
import 'memo_navigator.dart';

class MemoTile extends StatelessWidget {
  final String memoId;
  final Map<String, dynamic> data;
  final MemoService service;

  const MemoTile({
    super.key,
    required this.memoId,
    required this.data,
    required this.service,
  });

  String _subLabel() {
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

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _attachments =>
      List<Map<String, dynamic>>.from(
          (data['attachments'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)));

  void _showDetailSheet(BuildContext context, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MemoDetailSheet(
        memoId: memoId,
        data: data,
        service: service,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppLocalizations l,
      ColorScheme colorScheme) async {
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.memoDeleted)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final content = data['content'] as String? ?? '';
    final updatedAt = data['updated_at'] as Timestamp?;
    final source = data['source'] as String? ?? 'direct';
    final subLabel = _subLabel();
    final attachments = _attachments;
    final sourceColor = _sourceColor(colorScheme);

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
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              _AttachmentPreview(
                  attachments: attachments, colorScheme: colorScheme),
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
                        color: sourceColor.withOpacity(0.8)),
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
          if (source == 'chat')
            IconButton(
              icon: Icon(Icons.chat_bubble_outline,
                  size: 18, color: colorScheme.primary.withOpacity(0.7)),
              tooltip: l.memoGoToChat,
              onPressed: () =>
                  navigateToMemoSource(context, data, popFirst: false),
            ),
          if (source == 'board')
            IconButton(
              icon: Icon(Icons.article_outlined,
                  size: 18, color: colorScheme.tertiary.withOpacity(0.7)),
              tooltip: l.memoGoToBoard,
              onPressed: () =>
                  navigateToMemoSource(context, data, popFirst: false),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: colorScheme.onSurface.withOpacity(0.35), size: 20),
            onPressed: () => _confirmDelete(context, l, colorScheme),
          ),
        ]),
        // source 무관하게 항상 뷰 시트 → 편집 버튼
        onTap: () => _showDetailSheet(context, colorScheme),
      ),
      const Divider(height: 1, indent: 16),
    ]);
  }
}

// ── 타일 내 첨부파일 미리보기 (최대 3개) ──────────────────────────────────────
class _AttachmentPreview extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;
  final ColorScheme colorScheme;

  const _AttachmentPreview(
      {required this.attachments, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final images =
        attachments.where((a) => a['type'] == 'image').take(3).toList();
    final others =
        attachments.where((a) => a['type'] != 'image').take(3).toList();

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
          if (type == 'video' && thumbUrl.isNotEmpty) {
            return Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    thumbUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.black54,
                        child: const Icon(Icons.videocam,
                            color: Colors.white, size: 24)),
                  ),
                ),
                const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              ],
            );
          }
          final icon =
              type == 'audio' ? Icons.audio_file : Icons.insert_drive_file;
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
}