import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';
import 'schedule_form_screen.dart';

class ScheduleDetailScreen extends StatelessWidget {
  final String groupId;
  final String scheduleId;
  final bool canEdit;

  const ScheduleDetailScreen({
    super.key,
    required this.groupId,
    required this.scheduleId,
    this.canEdit = false,
  });

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  DocumentReference get _ref => FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('schedules')
      .doc(scheduleId);

  // ── RSVP 업데이트 ─────────────────────────────────────────────────────────
  Future<void> _setRsvp(String status) async {
    await _ref.update({'rsvp.$currentUserId': status});
  }

  // ── 삭제 ─────────────────────────────────────────────────────────────────
  Future<void> _delete(BuildContext context, AppLocalizations l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteSchedule),
        content: Text(l.deleteScheduleConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _ref.delete();
    if (context.mounted) {
      context.read<NotificationService>().cancelNotification(
          NotificationService.notificationId(scheduleId));
    }

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.scheduleDeleted)),
      );
    }
  }

  // ── 지도 열기 ──────────────────────────────────────────────────────────────
  Future<void> _launchMaps(String locationName) async {
    final query = Uri.encodeComponent(locationName);
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}'
      '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    
    // 현재 화면에서 사용 중인 GroupProvider를 미리 읽어둡니다.
    final groupProvider = context.read<GroupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.scheduleDetail),
        actions: [
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final snap = await _ref.get();
                if (!context.mounted) return;
                final data = snap.data() as Map<String, dynamic>;
                data['id'] = scheduleId;

                Navigator.of(context).push(MaterialPageRoute(
                  // .value를 사용하여 기존 GroupProvider 인스턴스를 수정 화면에 전달합니다.
                  builder: (_) => ChangeNotifierProvider.value(
                    value: groupProvider,
                    child: ScheduleFormScreen(
                      groupId: groupId,
                      existing: data,
                    ),
                  ),
                ));
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              onPressed: () => _delete(context, l),
            ),
          ],
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(child: Text(l.scheduleNotFound));
          }

          final data = snap.data!.data() as Map<String, dynamic>;
          final title = data['title'] as String? ?? '';
          final desc = data['description'] as String? ?? '';
          final locationName = data['location']?['name'] as String? ?? '';
          final start = (data['start_time'] as Timestamp?)?.toDate();
          final end = (data['end_time'] as Timestamp?)?.toDate();
          final rsvp = data['rsvp'] as Map<String, dynamic>? ?? {};
          final myRsvp = rsvp[currentUserId] as String?;
          final isPro = groupProvider.plan == 'pro';

          int yesCount = 0, noCount = 0, maybeCount = 0;
          for (final v in rsvp.values) {
            if (v == 'yes') yesCount++;
            else if (v == 'no') noCount++;
            else if (v == 'maybe') maybeCount++;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                if (start != null)
                  _InfoRow(
                    icon: Icons.play_circle_outline,
                    label: l.startTime,
                    value: _fmt(start),
                    colorScheme: colorScheme,
                  ),
                if (end != null) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.stop_circle_outlined,
                    label: l.endTime,
                    value: _fmt(end),
                    colorScheme: colorScheme,
                  ),
                ],                

                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(l.scheduleDescription,
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(desc),
                ],

                const SizedBox(height: 6),
                const Divider(),
                const SizedBox(height: 8),

                Text(l.rsvp,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    _RsvpCount(icon: Icons.check_circle, color: Colors.green,
                        count: yesCount, label: l.rsvpYes),
                    const SizedBox(width: 12),
                    _RsvpCount(icon: Icons.help, color: Colors.orange,
                        count: maybeCount, label: l.rsvpMaybe),
                    const SizedBox(width: 12),
                    _RsvpCount(icon: Icons.cancel, color: Colors.red,
                        count: noCount, label: l.rsvpNo),
                  ],
                ),

                const SizedBox(height: 20),

                Text(l.myRsvp,
                    style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RsvpButton(
                      label: l.rsvpYes,
                      icon: Icons.check_circle_outline,
                      activeIcon: Icons.check_circle,
                      color: Colors.green,
                      isActive: myRsvp == 'yes',
                      onTap: () => _setRsvp('yes'),
                    ),
                    const SizedBox(width: 8),
                    _RsvpButton(
                      label: l.rsvpMaybe,
                      icon: Icons.help_outline,
                      activeIcon: Icons.help,
                      color: Colors.orange,
                      isActive: myRsvp == 'maybe',
                      onTap: () => _setRsvp('maybe'),
                    ),
                    const SizedBox(width: 8),
                    _RsvpButton(
                      label: l.rsvpNo,
                      icon: Icons.cancel_outlined,
                      activeIcon: Icons.cancel,
                      color: Colors.red,
                      isActive: myRsvp == 'no',
                      onTap: () => _setRsvp('no'),
                    ),
                  ],
                ),

                // ── 장소 정보 및 지도 버튼 추가 ───────────────────
                if (isPro && locationName.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(l.location,
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, 
                           size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(locationName, 
                                   style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _launchMaps(locationName),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l.viewOnMap), // l10n에 viewOnMap: "지도 보기" 추가 필요
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(color: colorScheme.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({
    required this.icon, required this.label,
    required this.value, required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withOpacity(0.5))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      ],
    );
  }
}

class _RsvpCount extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _RsvpCount({
    required this.icon, required this.color,
    required this.count, required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 4),
      Text('$count $label',
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _RsvpButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _RsvpButton({
    required this.label, required this.icon, required this.activeIcon,
    required this.color, required this.isActive, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.15) : Colors.transparent,
            border: Border.all(
                color: isActive ? color : Colors.grey.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}