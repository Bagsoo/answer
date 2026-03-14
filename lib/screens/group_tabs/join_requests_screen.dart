import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/group_service.dart';

class JoinRequestsScreen extends StatelessWidget {
  final String groupId;

  const JoinRequestsScreen({super.key, required this.groupId});

  String _formatDate(Timestamp? ts, AppLocalizations l) {
    if (ts == null) return '-';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l.justNow;
    if (diff.inHours < 1) return l.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l.hoursAgo(diff.inHours);
    if (diff.inDays < 7) return l.daysAgo(diff.inDays);
    return '${dt.year}.${dt.month.toString().padLeft(2,'0')}.${dt.day.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupService = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(title: Text(l.manageJoinRequests)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: groupService.getPendingJoinRequests(groupId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snap.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noJoinRequests,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            itemBuilder: (context, i) {
              final req = requests[i];
              final uid = req['id'] as String;
              final name = req['display_name'] as String? ?? l.unknown;
              final phone = req['phone_number'] as String? ?? '';
              final ts = req['requested_at'] as Timestamp?;

              return _JoinRequestTile(
                uid: uid,
                name: name,
                phone: phone,
                timeLabel: _formatDate(ts, l),
                groupId: groupId,
                groupService: groupService,
                l: l,
                colorScheme: colorScheme,
              );
            },
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
          );
        },
      ),
    );
  }
}

class _JoinRequestTile extends StatefulWidget {
  final String uid;
  final String name;
  final String phone;
  final String timeLabel;
  final String groupId;
  final GroupService groupService;
  final AppLocalizations l;
  final ColorScheme colorScheme;

  const _JoinRequestTile({
    required this.uid,
    required this.name,
    required this.phone,
    required this.timeLabel,
    required this.groupId,
    required this.groupService,
    required this.l,
    required this.colorScheme,
  });

  @override
  State<_JoinRequestTile> createState() => _JoinRequestTileState();
}

class _JoinRequestTileState extends State<_JoinRequestTile> {
  bool _processing = false;

  Future<void> _approve() async {
    setState(() => _processing = true);
    final result = await widget.groupService
        .approveJoinRequest(widget.groupId, widget.uid);
    if (mounted) {
      setState(() => _processing = false);
      final message = result == 'ok'
          ? widget.l.joinApproved(widget.name)
          : result == 'banned'
              ? '${widget.name}님은 차단된 사용자입니다. 가입 요청이 삭제되었습니다.'
              : widget.l.joinApproveFailed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: result == 'ok' ? Colors.green : widget.colorScheme.error,
      ));
    }
  }

  Future<void> _reject() async {
    // 거절 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.l.rejectJoinRequest),
        content: Text(widget.l.rejectJoinRequestConfirm(widget.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(widget.l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.colorScheme.error,
              foregroundColor: widget.colorScheme.onError,
            ),
            child: Text(widget.l.reject),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _processing = true);
    final ok = await widget.groupService
        .rejectJoinRequest(widget.groupId, widget.uid);
    if (mounted) {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? widget.l.joinRejected(widget.name)
            : widget.l.joinRejectFailed),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Text(
          widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(widget.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.phone.isNotEmpty)
            Text(widget.phone,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5))),
          Text(widget.timeLabel,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(0.4))),
        ],
      ),
      isThreeLine: widget.phone.isNotEmpty,
      trailing: _processing
          ? const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 거절
                IconButton(
                  icon: Icon(Icons.close_rounded, color: cs.error),
                  tooltip: widget.l.reject,
                  onPressed: _reject,
                ),
                const SizedBox(width: 4),
                // 승인
                FilledButton(
                  onPressed: _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(widget.l.approve,
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
    );
  }
}