import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/user_notification_service.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final service = context.read<UserNotificationService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.sectionNotifications),
        centerTitle: true,
      ),
      body: StreamBuilder<List<UserNotification>>(
        stream: service.getNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '🙂',
                    style: TextStyle(fontSize: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '새 알림이 없습니다',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final noti = notifications[index];
              return _NotificationItem(notification: noti);
            },
          );
        },
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final UserNotification notification;

  const _NotificationItem({required this.notification});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final service = context.read<UserNotificationService>();

    return InkWell(
      onTap: () => service.markAsRead(notification.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: notification.isRead ? null : cs.primary.withOpacity(0.03),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLeading(cs),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTime(notification.createdAt),
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (notification.type == NotificationType.invite)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => service.rejectInvite(notification.id),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: cs.error,
                        ),
                        child: const Text('거절'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => service.acceptInvite(notification),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('수락'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(ColorScheme cs) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case NotificationType.invite:
        icon = Icons.group_add_outlined;
        color = Colors.blue;
        break;
      case NotificationType.friendRequest:
        icon = Icons.person_add_outlined;
        color = Colors.green;
        break;
      case NotificationType.system:
        icon = Icons.info_outline;
        color = Colors.orange;
        break;
    }

    if (notification.type == NotificationType.invite && 
        notification.data['group_photo_url'] != null && 
        notification.data['group_photo_url'].toString().isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: CachedNetworkImageProvider(notification.data['group_photo_url']),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${dt.month}월 ${dt.day}일';
  }
}
