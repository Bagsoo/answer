import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/group_service.dart';

class BannedMembersScreen extends StatelessWidget {
  final String groupId;
  const BannedMembersScreen({super.key, required this.groupId});

  Future<void> _unban(
      BuildContext context, String uid, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('차단 해제'),
        content: Text(
            '$displayName님의 차단을 해제할까요?\n해제 후 그룹에 다시 가입할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<GroupService>().unbanMember(groupId, uid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName님의 차단을 해제했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groupService = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(title: const Text('그룹 차단 목록')),
      body: StreamBuilder<QuerySnapshot>(
        stream: groupService.bannedMembersStream(groupId),
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
                  Icon(Icons.check_circle_outline,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text('차단된 멤버가 없습니다.',
                      style: TextStyle(
                          color:
                              colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final uid = doc.id;
              final data = doc.data() as Map<String, dynamic>;
              final displayName = data['display_name'] as String? ??
                  uid.substring(0, 8);
              final bannedAt = data['banned_at'] as Timestamp?;
              final dateStr = bannedAt != null
                  ? '${bannedAt.toDate().year}.${bannedAt.toDate().month.toString().padLeft(2, '0')}.${bannedAt.toDate().day.toString().padLeft(2, '0')}'
                  : '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.errorContainer,
                  child: Icon(Icons.block,
                      color: colorScheme.error, size: 20),
                ),
                title: Text(displayName),
                subtitle:
                    dateStr.isNotEmpty ? Text('차단일: $dateStr') : null,
                trailing: TextButton(
                  onPressed: () => _unban(context, uid, displayName),
                  child: Text('차단 해제',
                      style: TextStyle(color: colorScheme.primary)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
