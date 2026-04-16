import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/chat_service.dart';
import '../../utils/user_cache.dart';
import '../../utils/user_display.dart';
import '../../widgets/chat/chat_room_share_sheet.dart';
import 'schedule_form_screen.dart';
import '../../widgets/schedule/participant_list_sheet.dart';
import 'settlement_form_screen.dart';
import 'settlement_detail_screen.dart';

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
  Future<void> _setRsvp(BuildContext context, String status) async {
    final myProfile = context.read<UserProvider>();
    if (myProfile == null) return;

    // 1. 내 정보 객체 생성 (참석 시 저장될 데이터)
    final myInfo = {
      'uid': myProfile.uid,
      'display_name': myProfile.name ?? 'Anonymous',
      'photo_url': myProfile.photoUrl ?? '',
      // 'status'는 participants가 '참석자' 전용이므로 생략 가능하지만,
      // 나중에 확장성을 위해 'yes'로 넣어두는 것도 방법입니다.
      'status': 'yes',
    };

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 2. 최신 문서 데이터 가져오기 (가장 중요)
        DocumentSnapshot snapshot = await transaction.get(_ref);
        if (!snapshot.exists) return;

        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> participants = List.from(data['participants'] ?? []);

        // 3. 기존 리스트에서 내 정보 일단 제거 (중복 방지 및 상태 변경 대응)
        participants.removeWhere((p) => p['uid'] == currentUserId);

        // 4. '참석'일 때만 리스트에 추가 (방법 A 적용)
        if (status == 'yes') {
          participants.add(myInfo);
        }

        // 5. 트랜잭션으로 한꺼번에 업데이트
        transaction.update(_ref, {
          'rsvp.$currentUserId': status, // 전체 상태 관리용 Map
          'participants': participants, // 참석자 전용 List
        });

        // 6. 개인 일정(personal_schedules) DB에 동기화
        final personalRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('personal_schedules')
            .doc(scheduleId);

        if (status == 'yes') {
          transaction.set(personalRef, {
            'title': data['title'] ?? '',
            'description': data['description'] ?? '',
            'cost': data['cost'] ?? '',
            'start_time': data['start_time'],
            'end_time': data['end_time'],
            'location': data['location'],
            'type': 'group',
            'group_id': groupId,
            'group_name': context.read<GroupProvider>().name,
            'created_by': data['created_by'],
            'created_at': data['created_at'],
            'updated_at': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.delete(personalRef);
        }
      });
    } catch (e) {
      debugPrint('RSVP 업데이트 실패: $e');
      // 필요시 사용자에게 에러 알림(SnackBar 등) 추가
    }
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
            child: Text(l.cancel),
          ),
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
        NotificationService.notificationId(scheduleId),
      );
    }

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.scheduleDeleted)));
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

  Future<void> _shareToChat(BuildContext context) async {
    final chatService = context.read<ChatService>();
    final user = context.read<UserProvider>();
    final groupName = context.read<GroupProvider>().name;
    final messenger = ScaffoldMessenger.of(context);
    final snap = await _ref.get();
    if (!snap.exists || !context.mounted) return;
    final data = snap.data() as Map<String, dynamic>;

    final roomId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ChatRoomShareSheet(),
    );
    if (roomId == null || !context.mounted) return;

    final location = data['location'] as Map<String, dynamic>?;

    await chatService.sendSharedScheduleMessage(
      roomId,
      groupId: groupId,
      groupName: groupName,
      scheduleId: scheduleId,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      startTime: data['start_time'] as Timestamp?,
      endTime: data['end_time'] as Timestamp?,
      locationName: location?['name'] as String? ?? '',
      senderName: user.name,
      senderPhotoUrl: user.photoUrl,
    );
    await chatService.updateLastReadTime(roomId);
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('채팅방에 일정을 공유했습니다.')));
  }

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
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareToChat(context),
          ),
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final snap = await _ref.get();
                if (!context.mounted) return;
                final data = snap.data() as Map<String, dynamic>;
                data['id'] = scheduleId;

                Navigator.of(context).push(
                  MaterialPageRoute(
                    // .value를 사용하여 기존 GroupProvider 인스턴스를 수정 화면에 전달합니다.
                    builder: (_) => ChangeNotifierProvider.value(
                      value: groupProvider,
                      child: ScheduleFormScreen(
                        groupId: groupId,
                        existing: data,
                      ),
                    ),
                  ),
                );
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
          final cost = data['cost'] as String? ?? '';
          final locationName = data['location']?['name'] as String? ?? '';
          final start = (data['start_time'] as Timestamp?)?.toDate();
          final end = (data['end_time'] as Timestamp?)?.toDate();
          final rsvp = data['rsvp'] as Map<String, dynamic>? ?? {};
          final myRsvp = rsvp[currentUserId] as String?;
          final isPro = groupProvider.plan == 'pro';

          int yesCount = 0, noCount = 0, maybeCount = 0;
          for (final v in rsvp.values) {
            if (v == 'yes')
              yesCount++;
            else if (v == 'no')
              noCount++;
            else if (v == 'maybe')
              maybeCount++;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                if (cost.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.wallet_outlined,
                    label: l.scheduleCost,
                    value: cost,
                    colorScheme: colorScheme,
                  ),
                ],
                const SizedBox(height: 20),
                _buildParticipantSummary(
                  context,
                  data['participants'] as List<dynamic>? ?? [],
                  l,
                ),

                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    l.scheduleDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(desc),
                ],

                const SizedBox(height: 6),
                const Divider(),
                const SizedBox(height: 8),

                Text(
                  l.rsvp,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    _RsvpCount(
                      icon: Icons.check_circle,
                      color: Colors.green,
                      count: yesCount,
                      label: l.rsvpYes,
                    ),
                    const SizedBox(width: 12),
                    _RsvpCount(
                      icon: Icons.help,
                      color: Colors.orange,
                      count: maybeCount,
                      label: l.rsvpMaybe,
                    ),
                    const SizedBox(width: 12),
                    _RsvpCount(
                      icon: Icons.cancel,
                      color: Colors.red,
                      count: noCount,
                      label: l.rsvpNo,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Text(
                  l.myRsvp,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RsvpButton(
                      label: l.rsvpYes,
                      icon: Icons.check_circle_outline,
                      activeIcon: Icons.check_circle,
                      color: Colors.green,
                      isActive: myRsvp == 'yes',
                      onTap: () => _setRsvp(context, 'yes'),
                    ),
                    const SizedBox(width: 8),
                    _RsvpButton(
                      label: l.rsvpMaybe,
                      icon: Icons.help_outline,
                      activeIcon: Icons.help,
                      color: Colors.orange,
                      isActive: myRsvp == 'maybe',
                      onTap: () => _setRsvp(context, 'maybe'),
                    ),
                    const SizedBox(width: 8),
                    _RsvpButton(
                      label: l.rsvpNo,
                      icon: Icons.cancel_outlined,
                      activeIcon: Icons.cancel,
                      color: Colors.red,
                      isActive: myRsvp == 'no',
                      onTap: () => _setRsvp(context, 'no'),
                    ),
                  ],
                ),

                // ── 정산하기 버튼 ─────────────────────────────────
                const SizedBox(height: 20),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .collection('settlements')
                      .where('schedule_id', isEqualTo: scheduleId)
                      .limit(1)
                      .snapshots(),
                  builder: (context, settlementSnap) {
                    final exists = settlementSnap.hasData &&
                        settlementSnap.data!.docs.isNotEmpty;
                    final settlementIdFromSnap =
                        exists ? settlementSnap.data!.docs.first.id : null;

                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (exists && settlementIdFromSnap != null) {
                            // 이미 정산이 있으면 상세 화면으로 이동
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SettlementDetailScreen(
                                  groupId: groupId,
                                  settlementId: settlementIdFromSnap,
                                  groupName: groupProvider.name,
                                ),
                              ),
                            );
                            return;
                          }

                          // 정산이 없으면 생성 화면으로 이동
                          final participants =
                              data['participants'] as List<dynamic>? ?? [];
                          final rsvpYesUids =
                              (data['rsvp'] as Map<String, dynamic>? ?? {})
                                  .entries
                                  .where((e) => e.value == 'yes')
                                  .map((e) => e.key)
                                  .toSet();
                          final defaultMembers = participants
                              .where((p) =>
                                  rsvpYesUids.contains(p['uid']))
                              .map((p) =>
                                  Map<String, dynamic>.from(p as Map))
                              .toList();

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettlementFormScreen(
                                groupId: groupId,
                                groupName: groupProvider.name,
                                scheduleId: scheduleId,
                                scheduleTitle: title,
                                defaultMembers: defaultMembers,
                              ),
                            ),
                          );
                        },
                        icon: Icon(exists
                            ? Icons.description_outlined
                            : Icons.payments_outlined),
                        label: Text(exists
                            ? l.settlementDetail
                            : l.createSettlement),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: exists
                              ? colorScheme.secondary
                              : colorScheme.primary,
                          foregroundColor: exists
                              ? colorScheme.onSecondary
                              : colorScheme.onPrimary,
                        ),
                      ),
                    );
                  },
                ),

                // ── 장소 정보 및 지도 버튼 추가 ───────────────────
                if (isPro && locationName.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    l.location,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          locationName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _launchMaps(locationName),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        l.viewOnMap,
                      ), // l10n에 viewOnMap: "지도 보기" 추가 필요
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

  // ── 참여자 요약 빌더 ──────────────────────────────────────────────────────
  Widget _buildParticipantSummary(
    BuildContext context,
    List<dynamic> participants,
    AppLocalizations l,
  ) {
    if (participants.isEmpty) return const SizedBox.shrink();

    const int maxVisible = 5; // 최대 노출 사진 수
    final int totalCount = participants.length;
    final displayList = participants.take(maxVisible).toList();
    final colorScheme = Theme.of(context).colorScheme;
    final participantIds = participants
        .map((p) => p['uid'] as String? ?? '')
        .where((uid) => uid.isNotEmpty)
        .toSet();
    if (participantIds.isNotEmpty) {
      UserCache.prefetch(participantIds);
    }

    // 겹치는 정도를 조절하는 변수 (Avatar 크기 32 기준)
    const double avatarSize = 32.0;
    const double overlapOffset = 24.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${l.participants} ($totalCount)",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (_) =>
                  ParticipantListSheet(participants: participants, l: l),
            );
          },
          child: Row(
            children: [
              // --- Stack 시작 ---
              SizedBox(
                // 전체 너비 = (아이콘 개수 * 오프셋) + (마지막 아이콘의 남은 너비)
                width:
                    (displayList.length * overlapOffset) +
                    (totalCount > maxVisible ? overlapOffset : 8.0),
                height: avatarSize + 4, // 테두리 포함 높이
                child: Stack(
                  children: [
                    // 역순으로 쌓아야 첫 번째 사람이 맨 위로 올라옵니다 (asMap().entries.toList().reversed)
                    ...displayList.asMap().entries.toList().reversed.map((
                      entry,
                    ) {
                      int idx = entry.key;
                      var p = entry.value;
                      final uid = p['uid'] as String? ?? '';
                      final user =
                          UserDisplay.resolveCached(
                            uid,
                            fallbackName: p['display_name'] as String? ?? '',
                            fallbackPhotoUrl: p['photo_url'] as String?,
                          ) ??
                          UserDisplay.fromStored(
                            uid: uid,
                            name: p['display_name'] as String? ?? '',
                            photoUrl: p['photo_url'] as String?,
                          );
                      final resolvedPhoto = user.isDeleted ? '' : user.photoUrl;
                      return Positioned(
                        left: idx * overlapOffset,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.surface,
                              width: 2,
                            ), // 겹치는 부분의 흰색 테두리
                          ),
                          child: CircleAvatar(
                            radius: avatarSize / 2,
                            backgroundColor: colorScheme.primaryContainer,
                            backgroundImage: resolvedPhoto.isNotEmpty
                                ? NetworkImage(
                                    '$resolvedPhoto?v=${p['photo_version'] ?? 0}',
                                  )
                                : null,
                            child: resolvedPhoto.isEmpty
                                ? user.isDeleted
                                      ? const Icon(Icons.person_off_outlined)
                                      : Text(
                                          user.initial(l, fallback: '?'),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                : null,
                          ),
                        ),
                      );
                    }),
                    // +N 표시
                    if (totalCount > maxVisible)
                      Positioned(
                        left: maxVisible * overlapOffset,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: avatarSize / 2,
                            backgroundColor: colorScheme.surfaceVariant,
                            child: Text(
                              "+${totalCount - maxVisible}",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // --- Stack 끝 ---
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
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
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
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
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.color,
    required this.isActive,
    required this.onTap,
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
              color: isActive ? color : Colors.grey.withOpacity(0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(isActive ? activeIcon : icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
