import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class NoticesScreen extends StatelessWidget {
  final String roomId;

  const NoticesScreen({super.key, required this.roomId});

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')} '
        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.noticeHistory)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(roomId)
            .collection('notices')
            .orderBy('pinned_at', descending: true)
            .snapshots(),
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
                  Icon(Icons.campaign_outlined, size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noNotices,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final text = data['text'] as String? ?? '';
              final senderName = data['sender_name'] as String? ?? '';
              final pinnedAt = data['pinned_at'] as Timestamp?;
              final isCurrentNotice = i == 0;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrentNotice
                      ? colorScheme.primaryContainer.withOpacity(0.4)
                      : colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: isCurrentNotice
                      ? Border.all(color: colorScheme.primary.withOpacity(0.3))
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 현재 공지 뱃지
                      if (isCurrentNotice)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(l.currentNotice,
                              style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),

                      // 공지 내용
                      Text(text,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),

                      // 등록자 + 시간
                      Row(children: [
                        Icon(Icons.person_outline, size: 13,
                            color: colorScheme.onSurface.withOpacity(0.4)),
                        const SizedBox(width: 4),
                        Text(senderName,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurface.withOpacity(0.5))),
                        const Spacer(),
                        Text(_formatDate(pinnedAt),
                            style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface.withOpacity(0.4))),
                      ]),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 4),
          );
        },
      ),
    );
  }
}