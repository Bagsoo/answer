import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/env_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/notification_service.dart';
import 'group_info_edit_screen.dart';
import 'group_qr_screen.dart';
import 'join_requests_screen.dart';
import 'plan_screen.dart';

import '../../widgets/group_settings/section_header.dart';
import '../../widgets/group_settings/tag_management_sheet.dart';
import '../../widgets/group_settings/board_management_screen.dart';
import '../../widgets/group_settings/board_form_screen.dart';
import '../../widgets/group_settings/banned_members_screen.dart';
import '../../widgets/common/location_picker_sheet.dart';

import './group_type_category_data.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _editingName = false;
  late TextEditingController _nameController;
  bool _groupNotifEnabled = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _loadGroupNotif();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // GroupProvider에서 name 초기값 설정 (initState에선 context 사용 불가)
    if (_nameController.text.isEmpty) {
      _nameController.text = context.read<GroupProvider>().name;
    }
  }

  Future<void> _loadGroupNotif() async {
    final groupId = context.read<GroupProvider>().groupId;
    final enabled = await context
        .read<NotificationService>()
        .getGroupNotificationEnabled(groupId);
    if (mounted) setState(() => _groupNotifEnabled = enabled);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName(AppLocalizations l, String groupId) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    batch.update(db.collection('groups').doc(groupId), {'name': newName});
    batch.update(
      db
          .collection('users')
          .doc(currentUserId)
          .collection('joined_groups')
          .doc(groupId),
      {'name': newName},
    );

    final chatSnap = await db
        .collection('chat_rooms')
        .where('ref_group_id', isEqualTo: groupId)
        .get();
    for (final doc in chatSnap.docs) {
      batch.update(doc.reference, {'group_name': newName});
    }

    await batch.commit();

    if (mounted) {
      setState(() => _editingName = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.profileSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // GroupProvider에서 읽기 — StreamBuilder 2개 완전 제거
    final gp = context.watch<GroupProvider>();
    final groupId = gp.groupId;
    final isOwner = gp.isOwner;
    final canEdit = gp.canEditGroupInfo;
    final canManage = gp.canManagePermissions;
    final memberLimit = gp.memberLimit;
    final memberCount = gp.memberCount;
    final plan = gp.plan;
    final maxLimit = gp.absoluteMaxLimit;
    final requireApproval = gp.requireApproval;
    final currentType = gp.type;
    final currentCategory = gp.category;
    final currentName = gp.name;
    final currentLocationName = gp.currentLocationName;

    return ListView(
      children: [
        SectionHeader(title: l.sectionGroupInfo),

        // ── 그룹 이름 ────────────────────────────────────────────────────────
        if (_editingName)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l.groupName),
                  onSubmitted: (_) => _saveName(l, groupId),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () => _saveName(l, groupId)),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                        _editingName = false;
                        _nameController.text = currentName;
                      })),
            ]),
          )
        else
          ListTile(
            leading: Icon(Icons.group, color: colorScheme.primary),
            title: Text(l.groupName),
            subtitle: Text(currentName),
            trailing: canEdit
                ? IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                    onPressed: () => setState(() => _editingName = true),
                  )
                : null,
          ),

        // 그룹 위치
        ListTile(
          leading: Icon(Icons.place_outlined, color: colorScheme.primary),
          title: Text(l.groupLocation),
          subtitle: Text(
            currentLocationName.isEmpty ? l.noLocationSet : currentLocationName,
            style: TextStyle(
              color: currentLocationName.isEmpty
                  ? colorScheme.onSurface.withOpacity(0.35)
                  : colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          trailing: canEdit
              ? Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4))
              : null,
          onTap: canEdit
              ? () => _pickGroupLocation(context, l, groupId)
              : null,
        ),
        // ── 유형 & 카테고리 ──────────────────────────────────────────────────
        ListTile(
          leading: Icon(Icons.category, color: colorScheme.primary), // 아이콘을 통합된 느낌으로 변경
          title: Text(l.groupType), // '그룹 정보' 혹은 '유형 및 카테고리'
          subtitle: Text(
            '${_typeLabel(currentType, l)}  •  ${currentCategory.isEmpty ? '-' : GroupTypeCategoryData.localizeKey(currentCategory, l)}',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          trailing: canEdit
              ? Icon(Icons.chevron_right, color: colorScheme.onSurface.withOpacity(0.4))
              : null,
          onTap: canEdit
              ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GroupInfoEditScreen(
                      groupId: groupId,
                      currentType: currentType,
                      currentCategory: currentCategory,
                      currentName: currentName,
                      canEditInfo: canEdit,
                    ),
                  ))
              : null,
        ),

        // ── 가입 승인 ────────────────────────────────────────────────────────
        ListTile(
          leading: Icon(Icons.lock_outline, color: colorScheme.primary),
          title: Text(l.requireApproval),
          trailing: Transform.scale(
            scale: 0.8,
            child: Switch(
              value: requireApproval,
              onChanged: canEdit
                  ? (val) => FirebaseFirestore.instance
                      .collection('groups')
                      .doc(groupId)
                      .update({'require_approval': val})
                  : null,
              activeColor: colorScheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),

        // ── 인원 제한 ────────────────────────────────────────────────────────
        ListTile(
          leading:
              Icon(Icons.people_outline, color: colorScheme.primary),
          title: Text(l.memberLimit),
          subtitle: Text('$memberCount / $memberLimit ${l.people}'),
          trailing: canEdit
              ? TextButton(
                  onPressed: () => _showMemberLimitDialog(context, l,
                      memberLimit, memberCount, maxLimit, groupId, colorScheme),
                  child: Text(l.edit))
              : null,
        ),

        const Divider(),

        // ── 알림 ─────────────────────────────────────────────────────────────
        SectionHeader(title: l.sectionNotifications),
        SwitchListTile(
          secondary: Icon(
            _groupNotifEnabled
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            color: _groupNotifEnabled
                ? colorScheme.primary
                : colorScheme.onSurface.withOpacity(0.4),
          ),
          title: Text(l.groupNotifications),
          subtitle: Text(
            _groupNotifEnabled ? l.groupNotifOnDesc : l.groupNotifOffDesc,
            style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.5)),
          ),
          value: _groupNotifEnabled,
          onChanged: (v) async {
            setState(() => _groupNotifEnabled = v);
            await context
                .read<NotificationService>()
                .setGroupNotificationEnabled(groupId, v);
          },
          activeColor: colorScheme.primary,
        ),

        const Divider(),

        // ── 멤버 관리 ────────────────────────────────────────────────────────
        if (isOwner || canManage) ...[
          SectionHeader(title: l.sectionMemberManagement),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .collection('join_requests')
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, reqSnap) {
              final pendingCount = reqSnap.data?.docs.length ?? 0;
              return ListTile(
                leading: Icon(Icons.person_add_outlined,
                    color: colorScheme.primary),
                title: Text(l.manageJoinRequests),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pendingCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$pendingCount',
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: colorScheme.onSurface.withOpacity(0.4)),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JoinRequestsScreen(groupId: groupId),
                )),
              );
            },
          ),

          // 태그 관리
          ListTile(
            leading:
                Icon(Icons.label_outline, color: colorScheme.primary),
            title: Text(l.manageTags),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.4)),
            onTap: () => _showTagManagementSheet(context, l, colorScheme),
          ),

          // 차단 목록
          StreamBuilder<QuerySnapshot>(
            stream: context
                .read<GroupService>()
                .bannedMembersStream(groupId),
            builder: (context, banSnap) {
              final banCount = banSnap.data?.docs.length ?? 0;
              return ListTile(
                leading: Icon(Icons.block, color: colorScheme.error),
                title: const Text('차단 목록'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (banCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$banCount',
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: colorScheme.onSurface.withOpacity(0.4)),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BannedMembersScreen(groupId: groupId),
                )),
              );
            },
          ),
          const Divider(),
        ],

        // ── 게시판 관리 ──────────────────────────────────────────────────────
        if (isOwner || canEdit) ...[
          SectionHeader(title: l.manageBoardsSection),
          ListTile(
            leading:
                Icon(Icons.article_outlined, color: colorScheme.primary),
            title: Text(l.manageBoardsSection),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.4)),
            onTap: () {
              // 1. 현재 context에서 이미 활성화된 groupProvider를 가져옵니다.
              final groupProvider = context.read<GroupProvider>();

              Navigator.of(context).push(MaterialPageRoute(
                // 2. 새로운 화면으로 기존 groupProvider 인스턴스를 주입하며 이동합니다.
                builder: (_) => ChangeNotifierProvider.value(
                  value: groupProvider,
                  child: BoardManagementScreen(groupId: groupId),
                ),
              ));
            },
          ),
          const Divider(),

        ],

        if ((isOwner || canEdit) || gp.isPaidPlan) ...[
          SectionHeader(title: l.sectionPremium),
          if (isOwner || canEdit)
            ListTile(
              leading:
                  Icon(Icons.workspace_premium, color: colorScheme.primary),
              title: Text(l.manageGroupPlan),
              trailing: Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4)),
              onTap: () {
                final groupProvider = context.read<GroupProvider>();

                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: groupProvider,
                    child: PlanScreen(groupId: groupId),
                  ),
                ));
              },
            ),
          if (gp.isPaidPlan)
            ListTile(
              leading:
                  Icon(Icons.qr_code_2_outlined, color: colorScheme.primary),
              title: Text(l.groupQr),
              subtitle: Text(l.groupQrDescription),
              trailing: Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4)),
              onTap: () {
                final groupProvider = context.read<GroupProvider>();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: groupProvider,
                      child: GroupQrScreen(groupId: groupId),
                    ),
                  ),
                );
              },
            ),
          const Divider(),
        ],

        // ── 위험 구역 ────────────────────────────────────────────────────────
        SectionHeader(
            title: l.sectionDangerZone, color: colorScheme.error),
        if (!isOwner)
          ListTile(
            leading:
                Icon(Icons.exit_to_app, color: colorScheme.tertiary),
            title: Text(l.leaveGroup,
                style: TextStyle(color: colorScheme.tertiary)),
            onTap: () => _showLeaveDialog(context, l, groupId),
          ),
        if (isOwner) ...[
          ListTile(
            leading: Icon(Icons.exit_to_app,
                color: colorScheme.onSurface.withOpacity(0.3)),
            title: Text(l.leaveGroup,
                style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.3))),
            subtitle: Text(l.ownerCannotLeave,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.4))),
            onTap: () => ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.ownerCannotLeave))),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: colorScheme.error),
            title: Text(l.deleteGroup,
                style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold)),
            subtitle: Text(l.deleteGroupWarning),
            onTap: () => _showDeleteDialog(context, l, groupId),
          ),
        ],

        const SizedBox(height: 32),
      ],
    );
  }

  String _typeLabel(String key, AppLocalizations l) {
    switch (key) {
      case 'company':
        return l.groupTypeCompany;
      case 'club':
        return l.groupTypeClub;
      case 'small_group':
        return l.groupTypeSmall;
      case 'academy':
        return l.groupTypeAcademy;
      case 'school_class':
        return l.groupTypeClass;
      case 'hobby_club':
        return l.groupTypeHobby;
      default:
        return key;
    }
  }

  void _showMemberLimitDialog(
    BuildContext context,
    AppLocalizations l,
    int currentLimit,
    int currentMemberCount,
    int max,
    String groupId,
    ColorScheme colorScheme,
  ) {
    double sliderValue =
        currentLimit.toDouble().clamp(10.0, max.toDouble());
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.memberLimit),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${sliderValue.toInt()} ${l.people}',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary)),
              const SizedBox(height: 8),
              Slider(
                value: sliderValue,
                min: 10,
                max: max.toDouble(),
                divisions: max == 50 ? 4 : 99,
                label: '${sliderValue.toInt()}',
                onChanged: (v) =>
                    setDialogState(() => sliderValue = v.roundToDouble()),
              ),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('10',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                colorScheme.onSurface.withOpacity(0.4))),
                    Text('$max',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                colorScheme.onSurface.withOpacity(0.4))),
                  ]),
              if (sliderValue.toInt() < currentMemberCount)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.memberLimitBelowCurrent,
                      style: TextStyle(
                          color: colorScheme.error, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.cancel)),
            ElevatedButton(
              onPressed: sliderValue.toInt() < currentMemberCount
                  ? null
                  : () async {
                      await FirebaseFirestore.instance
                          .collection('groups')
                          .doc(groupId)
                          .update(
                              {'member_limit': sliderValue.toInt()});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveDialog(
      BuildContext context, AppLocalizations l, String groupId) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.leaveGroup),
        content: Text(l.leaveGroupConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _leaveGroup(context, l, groupId);
            },
            child: Text(l.leaveGroup,
                style: TextStyle(color: colorScheme.tertiary)),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveGroup(
      BuildContext context, AppLocalizations l, String groupId) async {
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.delete(db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(currentUserId));
      batch.update(db.collection('groups').doc(groupId),
          {'member_count': FieldValue.increment(-1)});
      batch.delete(db
          .collection('users')
          .doc(currentUserId)
          .collection('joined_groups')
          .doc(groupId));

      final chatSnap = await db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .get();
      for (final chatDoc in chatSnap.docs) {
        final chatId = chatDoc.id;
        final memberIds =
            List<String>.from(chatDoc.data()['member_ids'] as List? ?? []);
        memberIds.remove(currentUserId);
        batch.update(
          db.collection('chat_rooms').doc(chatId),
          {
            'member_ids': memberIds,
            'unread_counts.$currentUserId': FieldValue.delete(),
          },
        );
        batch.delete(
          db
              .collection('chat_rooms')
              .doc(chatId)
              .collection('room_members')
              .doc(currentUserId),
        );
      }

      await batch.commit();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.leaveSuccess)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.leaveFailed)));
      }
    }
  }

  void _showDeleteDialog(
      BuildContext context, AppLocalizations l, String groupId) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteGroup),
        content: Text(l.deleteGroupConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteGroup(context, l, groupId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup(
      BuildContext context, AppLocalizations l, String groupId) async {
    try {
      final db = FirebaseFirestore.instance;
      final membersSnap = await db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();
      final batch = db.batch();
      for (final doc in membersSnap.docs) {
        final uid = doc.data()['user_id'] as String? ?? doc.id;
        batch.delete(db
            .collection('users')
            .doc(uid)
            .collection('joined_groups')
            .doc(groupId));
      }
      final chatSnap = await db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .get();
      for (final doc in chatSnap.docs) {
        batch.update(doc.reference, {
          'status': 'group_deleted',
          'deleted_at': FieldValue.serverTimestamp(),
          'deleted_by': currentUserId,
          'member_ids': <String>[],
          'unread_counts': <String, dynamic>{},
        });
      }
      batch.update(db.collection('groups').doc(groupId), {
        'status': 'deleted',
        'deleted_at': FieldValue.serverTimestamp(),
        'deleted_by': currentUserId,
      });
      await batch.commit();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.deleteSuccess)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.deleteFailed)));
      }
    }
  }

  void _showTagManagementSheet(
      BuildContext context, AppLocalizations l, ColorScheme colorScheme) {
    final groupId = context.read<GroupProvider>().groupId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => TagManagementSheet(
        groupId: groupId,
        l: l,
        colorScheme: colorScheme,
      ),
    );
  }

Future<void> _pickGroupLocation(
    BuildContext context, AppLocalizations l, String groupId) async {
  final apiKey = EnvConfig.mapsApiKey;
  final gp = context.read<GroupProvider>();
 
  final result = await showModalBottomSheet<LocationResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => LocationPickerSheet(
      googleApiKey: apiKey,
      languageCode: Localizations.localeOf(context).languageCode,
      showCurrentLocation: false,  // 그룹은 현재위치 없음
      showGroupHint: true,
      initialLocation: (gp.locationLat != null && gp.locationLng != null)
          ? LocationResult(
              latitude: gp.locationLat!,
              longitude: gp.locationLng!,
              name: gp.locationName,
              address: '',
            )
          : null,
    ),
  );
 
  if (result != null && context.mounted) {
      await context.read<GroupService>().updateGroupLocation(
        groupId: groupId,
        lat: result.latitude,
        lng: result.longitude,
        locationName: result.name,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.locationSaved)));
      }
    }
  }
}

