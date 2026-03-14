import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/notification_service.dart';
import 'group_info_edit_screen.dart';
import 'join_requests_screen.dart';

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
    final maxLimit = plan == 'free' ? 50 : 1000;
    final requireApproval = gp.requireApproval;
    final currentType = gp.type;
    final currentCategory = gp.category;
    final currentName = gp.name;

    return ListView(
      children: [
        _SectionHeader(title: l.sectionGroupInfo),

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
            leading: Icon(Icons.info_outline, color: colorScheme.primary),
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

        // ── 유형 & 카테고리 ──────────────────────────────────────────────────
        ListTile(
          leading:
              Icon(Icons.business_outlined, color: colorScheme.primary),
          title: Text(l.type),
          subtitle: Text(_typeLabel(currentType, l)),
          trailing: canEdit
              ? Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4))
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
        ListTile(
          leading:
              Icon(Icons.category_outlined, color: colorScheme.primary),
          title: Text(l.category),
          subtitle:
              Text(currentCategory.isEmpty ? '-' : currentCategory),
          trailing: canEdit
              ? Icon(Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4))
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
        _SectionHeader(title: l.sectionNotifications),
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
          _SectionHeader(title: l.sectionMemberManagement),
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
                  builder: (_) => _BannedMembersScreen(groupId: groupId),
                )),
              );
            },
          ),
          const Divider(),
        ],

        // ── 게시판 관리 ──────────────────────────────────────────────────────
        if (isOwner || canEdit) ...[
          _SectionHeader(title: l.manageBoardsSection),
          ListTile(
            leading:
                Icon(Icons.article_outlined, color: colorScheme.primary),
            title: Text(l.manageBoardsSection),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.4)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _BoardManagementScreen(groupId: groupId),
            )),
          ),
          const Divider(),
        ],

        // ── 위험 구역 ────────────────────────────────────────────────────────
        _SectionHeader(
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
        batch.delete(doc.reference);
      }
      final chatSnap = await db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .get();
      for (final doc in chatSnap.docs) batch.delete(doc.reference);
      batch.delete(db.collection('groups').doc(groupId));
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
      builder: (ctx) => _TagManagementSheet(
        groupId: groupId,
        l: l,
        colorScheme: colorScheme,
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: color ?? colorScheme.onSurface.withOpacity(0.5),
          )),
    );
  }
}

// ── 태그 관리 바텀시트 ────────────────────────────────────────────────────────
class _TagManagementSheet extends StatefulWidget {
  final String groupId;
  final AppLocalizations l;
  final ColorScheme colorScheme;

  const _TagManagementSheet(
      {required this.groupId, required this.l, required this.colorScheme});

  @override
  State<_TagManagementSheet> createState() => _TagManagementSheetState();
}

class _TagManagementSheetState extends State<_TagManagementSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final colorScheme = widget.colorScheme;
    // GroupService는 Provider에서 읽기 (직접 생성 금지)
    final groupService = context.read<GroupService>();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l.manageTags,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: l.tagNameHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final tag = _ctrl.text.trim();
                  if (tag.isEmpty) return;
                  final ok = await groupService.addGroupTag(
                      widget.groupId, tag);
                  if (ok) {
                    _ctrl.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.tagAdded)));
                    }
                  }
                },
                child: Text(l.addTag),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<String>>(
            stream: groupService.getGroupTags(widget.groupId),
            builder: (context, snap) {
              final tags = snap.data ?? [];
              if (tags.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.noTags,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                );
              }
              return SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: tags.length,
                  itemBuilder: (ctx, i) => ListTile(
                    leading: Icon(Icons.label_outline,
                        color: colorScheme.primary),
                    title: Text(tags[i]),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: colorScheme.error),
                      onPressed: () async {
                        final ok = await groupService.removeGroupTag(
                            widget.groupId, tags[i]);
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.tagDeleted)));
                        }
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── 게시판 관리 화면 ──────────────────────────────────────────────────────────
class _BoardManagementScreen extends StatelessWidget {
  final String groupId;
  const _BoardManagementScreen({required this.groupId});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageBoardsSection),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () =>
                _showBoardForm(context, l, colorScheme, service),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.getBoards(groupId),
        builder: (context, snap) {
          final boards = snap.data ?? [];
          if (boards.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noBoards,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showBoardForm(context, l, colorScheme, service),
                    icon: const Icon(Icons.add),
                    label: Text(l.createBoard),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: boards.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final board = boards[i];
              final boardType =
                  board['board_type'] as String? ?? 'free';
              return ListTile(
                leading: Icon(_boardIcon(boardType),
                    color: colorScheme.primary),
                title: Text(board['name'] as String? ?? ''),
                subtitle: Text(_boardTypeLabel(boardType, l)),
                trailing:
                    Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                    onPressed: () => _showBoardForm(
                        context, l, colorScheme, service,
                        board: board),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: colorScheme.error),
                    onPressed: () => _confirmDelete(
                        context, l, colorScheme, service, board),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  IconData _boardIcon(String type) {
    switch (type) {
      case 'notice':
        return Icons.campaign_outlined;
      case 'greeting':
        return Icons.waving_hand_outlined;
      case 'sub':
        return Icons.label_outlined;
      default:
        return Icons.article_outlined;
    }
  }

  String _boardTypeLabel(String type, AppLocalizations l) {
    switch (type) {
      case 'notice':
        return l.boardTypeNotice;
      case 'greeting':
        return l.boardTypeGreeting;
      case 'sub':
        return l.boardTypeSub;
      default:
        return l.boardTypeFree;
    }
  }

  void _showBoardForm(BuildContext context, AppLocalizations l,
      ColorScheme colorScheme, GroupService service,
      {Map<String, dynamic>? board}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _BoardFormScreen(groupId: groupId, board: board),
    ));
  }

  void _confirmDelete(
      BuildContext context,
      AppLocalizations l,
      ColorScheme colorScheme,
      GroupService service,
      Map<String, dynamic> board) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteBoard),
        content: Text(l.deleteBoardConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await service.deleteBoard(
                  groupId, board['id'] as String);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        ok ? l.boardDeleted : l.boardSaveFailed)));
              }
            },
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }
}

// ── 게시판 생성/수정 폼 ────────────────────────────────────────────────────────
class _BoardFormScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic>? board;

  const _BoardFormScreen({required this.groupId, this.board});

  @override
  State<_BoardFormScreen> createState() => _BoardFormScreenState();
}

class _BoardFormScreenState extends State<_BoardFormScreen> {
  final _nameCtrl = TextEditingController();
  String _boardType = 'free';
  String _writePermission = 'all';
  List<String> _allowedTags = [];
  bool _saving = false;

  bool get isEditing => widget.board != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final b = widget.board!;
      _nameCtrl.text = b['name'] as String? ?? '';
      _boardType = b['board_type'] as String? ?? 'free';
      _writePermission = b['write_permission'] as String? ?? 'all';
      _allowedTags =
          List<String>.from(b['allowed_tags'] as List? ?? []);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onBoardTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _boardType = val;
      if (val == 'notice') _writePermission = 'owner_only';
      if (val == 'free' || val == 'greeting') _writePermission = 'all';
    });
  }

  Future<void> _save(AppLocalizations l) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.postTitleRequired)));
      return;
    }
    setState(() => _saving = true);

    final service = context.read<GroupService>();
    final data = {
      'name': name,
      'board_type': _boardType,
      'write_permission': _writePermission,
      'allowed_tags': _boardType == 'sub' ? _allowedTags : [],
    };

    bool ok;
    if (isEditing) {
      ok = await service.updateBoard(
          widget.groupId, widget.board!['id'] as String, data);
    } else {
      ok = await service.createBoard(widget.groupId, data);
    }

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? (isEditing ? l.boardUpdated : l.boardCreated)
              : l.boardSaveFailed)));
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupService = context.read<GroupService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l.editBoard : l.createBoard),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child:
                      CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _save(l),
                  child: Text(l.save,
                      style:
                          TextStyle(color: colorScheme.primary))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l.boardName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(l.boardType,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...[
            ('notice', l.boardTypeNotice, Icons.campaign_outlined),
            ('free', l.boardTypeFree, Icons.article_outlined),
            ('greeting', l.boardTypeGreeting,
                Icons.waving_hand_outlined),
            ('sub', l.boardTypeSub, Icons.label_outlined),
          ].map((e) => RadioListTile<String>(
                value: e.$1,
                groupValue: _boardType,
                onChanged: _onBoardTypeChanged,
                title: Text(e.$2),
                secondary: Icon(e.$3, color: colorScheme.primary),
                dense: true,
              )),
          const SizedBox(height: 16),
          Text(l.boardWritePermission,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          RadioListTile<String>(
            value: 'owner_only',
            groupValue: _writePermission,
            onChanged: (v) => setState(() => _writePermission = v!),
            title: Text(l.boardWriteOwnerOnly),
            dense: true,
          ),
          RadioListTile<String>(
            value: 'all',
            groupValue: _writePermission,
            onChanged: (v) => setState(() => _writePermission = v!),
            title: Text(l.boardWriteAll),
            dense: true,
          ),
          if (_boardType == 'sub') ...[
            const SizedBox(height: 16),
            Text(l.boardAllowedTags,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(l.boardAllowedTagsHint,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            StreamBuilder<List<String>>(
              stream: groupService.getGroupTags(widget.groupId),
              builder: (context, snap) {
                final tags = snap.data ?? [];
                if (tags.isEmpty) {
                  return Text(l.noTags,
                      style: TextStyle(
                          color:
                              colorScheme.onSurface.withOpacity(0.4)));
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tags.map((tag) {
                    final selected = _allowedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: selected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _allowedTags.add(tag);
                          } else {
                            _allowedTags.remove(tag);
                          }
                        });
                      },
                      selectedColor:
                          colorScheme.primary.withOpacity(0.2),
                      checkmarkColor: colorScheme.primary,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ── 그룹 차단 목록 화면 ────────────────────────────────────────────────────────
class _BannedMembersScreen extends StatelessWidget {
  final String groupId;
  const _BannedMembersScreen({required this.groupId});

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