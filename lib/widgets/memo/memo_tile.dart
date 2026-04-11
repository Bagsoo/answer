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
    if (source == 'chat') return '💬 ${data['room_name'] ?? ''} · ${data['sender_name'] ?? ''}';
    if (source == 'board') return '📋 ${data['board_name'] ?? ''} › ${data['post_title'] ?? ''}';
    return '';
  }

  Color _sourceColor(ColorScheme cs) {
    final source = data['source'] as String? ?? 'direct';
    if (source == 'chat') return cs.primary;
    if (source == 'board') return cs.tertiary;
    return cs.onSurface.withOpacity(0.4);
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    try {
      final dynamic dynamicValue = value;
      final result = dynamicValue.toDate();
      if (result is DateTime) return result;
    } catch (_) {}
    return null;
  }

  String _formatDate(dynamic value) {
    final d = _asDateTime(value);
    if (d == null) return '';
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _attachments =>
      List<Map<String, dynamic>>.from(
          (data['attachments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

  List<String> get _mediaTypes =>
      List<String>.from(data['media_types'] as List? ?? []);

  // 첫 번째 이미지/손글씨 PNG URL
  String? get _firstImageUrl {
    final rawBlocks = data['blocks'] as List?;
    if (rawBlocks != null) {
      for (final b in rawBlocks) {
        final bMap = Map<String, dynamic>.from(b as Map);
        if (bMap['type'] == 'image' || bMap['type'] == 'drawing') {
          final url = (bMap['data'] as Map?)?['url'] as String?;
          if (url != null && url.isNotEmpty) return url;
        }
      }
    }
    for (final att in _attachments) {
      if (att['type'] == 'image') {
        final url = att['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  // 첫 번째 동영상 썸네일
  String? get _firstVideoThumb {
    final rawBlocks = data['blocks'] as List?;
    if (rawBlocks != null) {
      for (final b in rawBlocks) {
        final bMap = Map<String, dynamic>.from(b as Map);
        if (bMap['type'] == 'video') {
          final url = (bMap['data'] as Map?)?['thumbnail_url'] as String?;
          if (url != null && url.isNotEmpty) return url;
        }
      }
    }
    for (final att in _attachments) {
      if (att['type'] == 'video') {
        final url = att['thumbnail_url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  void _showDetailSheet(BuildContext context, ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MemoDetailSheet(memoId: memoId, data: data, service: service),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppLocalizations l, ColorScheme cs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.deleteMemoConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deleteMemo, style: TextStyle(color: cs.error))),
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
    final cs = Theme.of(context).colorScheme;
    final title = data['title'] as String? ?? '';
    final content = data['content'] as String? ?? '';
    final updatedAt = data['updated_at'];
    final source = data['source'] as String? ?? 'direct';
    final subLabel = _subLabel();
    final sourceColor = _sourceColor(cs);
    final mediaTypes = _mediaTypes;
    final hasMedia = mediaTypes.isNotEmpty || _attachments.isNotEmpty;

    final imageUrl = _firstImageUrl;
    final videoThumb = _firstVideoThumb;
    final previewUrl = imageUrl ?? videoThumb;
    final isVideoThumb = imageUrl == null && videoThumb != null;

    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 제목 (direct만)
          if (source == 'direct' && title.isNotEmpty) ...[
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
          ],
          // 본문
          if (content.isNotEmpty)
            Text(content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: (source == 'direct' && title.isNotEmpty)
                        ? cs.onSurface.withOpacity(0.6)
                        : cs.onSurface)),
          // 미디어 미리보기
          if (hasMedia) ...[
            const SizedBox(height: 6),
            _MediaPreview(
              previewUrl: previewUrl,
              isVideoThumb: isVideoThumb,
              mediaTypes: mediaTypes,
              attachments: _attachments,
              colorScheme: cs,
            ),
          ],
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subLabel,
                style: TextStyle(fontSize: 11, color: sourceColor.withOpacity(0.8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 2),
          Text(_formatDate(updatedAt),
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.35))),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (source == 'chat')
            IconButton(
              icon: Icon(Icons.chat_bubble_outline, size: 18, color: cs.primary.withOpacity(0.7)),
              tooltip: l.memoGoToChat,
              onPressed: () => navigateToMemoSource(context, data, popFirst: false),
            ),
          if (source == 'board')
            IconButton(
              icon: Icon(Icons.article_outlined, size: 18, color: cs.tertiary.withOpacity(0.7)),
              tooltip: l.memoGoToBoard,
              onPressed: () => navigateToMemoSource(context, data, popFirst: false),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: cs.onSurface.withOpacity(0.35), size: 20),
            onPressed: () => _confirmDelete(context, l, cs),
          ),
        ]),
        onTap: () => _showDetailSheet(context, cs),
      ),
      const Divider(height: 1, indent: 16),
    ]);
  }
}

// ── 미디어 미리보기 위젯 ──────────────────────────────────────────────────────
class _MediaPreview extends StatelessWidget {
  static const double _previewHeight = 88;
  final String? previewUrl;
  final bool isVideoThumb;
  final List<String> mediaTypes;
  final List<Map<String, dynamic>> attachments;
  final ColorScheme colorScheme;

  const _MediaPreview({
    required this.previewUrl,
    required this.isVideoThumb,
    required this.mediaTypes,
    required this.attachments,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (previewUrl != null && previewUrl!.isNotEmpty) {
      return Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              previewUrl!,
              width: double.infinity,
              height: _previewHeight,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _chips(),
            ),
          ),
          if (isVideoThumb)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
            ),
        ],
      );
    }
    return _chips();
  }

  Widget _chips() {
    final counts = <String, int>{};
    final allTypes = mediaTypes.isNotEmpty
        ? mediaTypes
        : attachments.map((a) => a['type'] as String? ?? 'file').toList();
    for (final t in allTypes) counts[t] = (counts[t] ?? 0) + 1;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: counts.entries.map((e) {
        final icon = _icon(e.key);
        final color = _color(e.key);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text('${e.value}',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ]),
        );
      }).toList(),
    );
  }

  IconData _icon(String type) {
    switch (type) {
      case 'drawing': return Icons.draw_outlined;
      case 'image': return Icons.image_outlined;
      case 'video': return Icons.videocam_outlined;
      case 'audio': return Icons.mic_outlined;
      default: return Icons.attach_file;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'drawing': return Colors.indigo;
      case 'image': return Colors.green;
      case 'video': return Colors.red;
      case 'audio': return Colors.orange;
      default: return colorScheme.primary;
    }
  }
}
