import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/group_provider.dart';
import 'group_tabs/boards_tab.dart';
import 'group_tabs/chats_tab.dart';
import 'group_tabs/group_profile_screen.dart';
import 'group_tabs/members_tab.dart';
import 'group_tabs/schedule_detail_screen.dart';
import 'group_tabs/schedules_tab.dart';
import 'group_tabs/settings_tab.dart';
import 'user_profile_detail_screen.dart';
import 'chat_room_screen.dart';

enum GroupDetailTab {
  members,
  boards,
  schedules,
  chats,
  settings
}

class GroupDetailScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final Map<String, dynamic>? initialGroupData;
  final GroupDetailTab initialTab;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.initialGroupData,
    this.initialTab = GroupDetailTab.chats,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GroupProvider(groupId, initialData: initialGroupData),
      child: _GroupDetailBody(groupName: groupName, initialTab: initialTab),
    );
  }
}

class _GroupDetailBody extends StatefulWidget {
  final String groupName;
  final GroupDetailTab initialTab;

  const _GroupDetailBody({
    required this.groupName,
    required this.initialTab,
  });

  @override
  State<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends State<_GroupDetailBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _selectedMember;
  Map<String, dynamic>? _selectedSchedule;
  String? _selectedRoomId;

  bool get _showMemberPanel =>
      _tabController.index == 0 && _selectedMember != null;
  bool get _showSchedulePanel =>
      _tabController.index == 2 && _selectedSchedule != null;
  bool get _showChatPanel =>
      _tabController.index == 3 && _selectedRoomId != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      initialIndex: widget.initialTab.index,
      length: 5, 
      vsync: this
    )..addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  void _showMembersModal(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.read<GroupProvider>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: gp,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurface.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.groupName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(child: MembersTab()),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildDesktopPanel(BuildContext context) {
    if (_showMemberPanel) {
      return _DesktopMemberPanel(
        member: _selectedMember!,
        onClose: () => setState(() => _selectedMember = null),
      );
    }
    if (_showSchedulePanel) {
      return _DesktopSchedulePanel(
        schedule: _selectedSchedule!,
        onClose: () => setState(() => _selectedSchedule = null),
      );
    }
    if (_showChatPanel) {
      return ClipRect(
        child: ChatRoomScreen(
          key: ValueKey('chat_${_selectedRoomId}'),
          roomId: _selectedRoomId!,
          isDesktopMode: true,
          onClosePanel: () => setState(() => _selectedRoomId = null),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<GroupProvider, bool>((gp) => gp.loaded);
    final isDeleted = context.select<GroupProvider, bool>((gp) => gp.isDeleted);
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktopMode = MediaQuery.sizeOf(context).width >= 900;

    if (!loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (isDeleted) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).deletedGroup),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppLocalizations.of(context).deletedGroupMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        ),
      );
    }

    final memberCount = context.select<GroupProvider, int>((gp) => gp.memberCount);
    final likes = context.select<GroupProvider, List<String>>((gp) => gp.likes);
    final isLiked = context.select<GroupProvider, bool>((gp) => gp.isLiked);
    final name = context.select<GroupProvider, String>((gp) => gp.name);
    final profileImageUrl =
        context.select<GroupProvider, String>((gp) => gp.profileImageUrl);

    final tabViews = [
      MembersTab(
        isDesktopMode: isDesktopMode,
        selectedMemberId: _selectedMember?['uid'] as String?,
        onMemberSelected: isDesktopMode
            ? (member) => setState(() => _selectedMember = member)
            : null,
      ),
      const BoardsTab(),
      SchedulesTab(
        isDesktopMode: isDesktopMode,
        selectedScheduleId: _selectedSchedule?['id'] as String?,
        onScheduleSelected: isDesktopMode
            ? (schedule) => setState(() => _selectedSchedule = schedule)
            : null,
      ),
      ChatsTab(
        groupName: widget.groupName,
        isDesktopMode: isDesktopMode,
        selectedRoomId: _selectedRoomId,
        onRoomSelected: isDesktopMode
            ? (roomId) => setState(() => _selectedRoomId = roomId)
            : null,
      ),
      const SettingsTab(),
    ];

    final desktopPanel = isDesktopMode ? _buildDesktopPanel(context) : null;

    return Scaffold(
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () {
            final gp = context.read<GroupProvider>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: gp,
                  child: GroupProfileScreen(groupId: gp.groupId),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage:
                  profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
              child: profileImageUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                name.isNotEmpty ? name : widget.groupName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (memberCount > 0) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: GestureDetector(
                  onTap: () {
                    if (isDesktopMode) {
                      _tabController.animateTo(0);
                      return;
                    }
                    _showMembersModal(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 13,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$memberCount',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.read<GroupProvider>().toggleLike(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 24,
                      color: isLiked
                          ? Colors.red
                          : colorScheme.onSurface.withOpacity(0.45),
                    ),
                    if (likes.isNotEmpty)
                      Positioned(
                        right: -5,
                        bottom: -7,
                        child: Text(
                          '${likes.length}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isLiked
                                ? Colors.red
                                : colorScheme.onSurface.withOpacity(0.5),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withOpacity(0.4),
          indicatorColor: colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.people)),
            Tab(icon: Icon(Icons.article_outlined)),
            Tab(icon: Icon(Icons.calendar_month)),
            Tab(icon: Icon(Icons.chat_bubble)),
            Tab(icon: Icon(Icons.settings)),
          ],
        ),
      ),
      body: isDesktopMode
          ? Row(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: tabViews,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: desktopPanel == null
                      ? const SizedBox.shrink()
                      : Container(
                          key: ValueKey(
                            '${_tabController.index}-${_selectedMember?['uid'] ?? _selectedSchedule?['id'] ?? _selectedRoomId ?? 'panel'}',
                          ),
                          width: 400,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            border: Border(
                              left: BorderSide(
                                color: colorScheme.outline.withOpacity(0.12),
                              ),
                            ),
                          ),
                          child: desktopPanel,
                        ),
                ),
              ],
            )
          : TabBarView(
              controller: _tabController,
              children: tabViews,
            ),
    );
  }
}

class _DesktopMemberPanel extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onClose;

  const _DesktopMemberPanel({
    required this.member,
    required this.onClose,
  });

  String _roleLabel(AppLocalizations l, String role) {
    switch (role) {
      case 'owner':
        return l.roleOwner;
      default:
        return l.roleMember;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final name = member['display_name'] as String? ?? l.unknown;
    final photoUrl = (member['photo_url'] ?? member['profile_image']) as String? ?? '';
    final role = member['role'] as String? ?? 'member';
    final tags = List<String>.from(member['tags'] as List? ?? const []);
    final isMe = member['is_me'] == true;
    final uid = member['uid'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Row(
            children: [
              Text(
                '멤버 상세',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage:
                          photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      child: photoUrl.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '$name (${l.me})' : name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _roleLabel(l, role),
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '태그',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 10),
                if (tags.isEmpty)
                  Text(
                    '설정된 태그가 없습니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.45),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: uid.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserProfileDetailScreen(
                                  uid: uid,
                                  displayName: name,
                                  photoUrl: photoUrl,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(l.viewProfile),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopSchedulePanel extends StatelessWidget {
  final Map<String, dynamic> schedule;
  final VoidCallback onClose;

  const _DesktopSchedulePanel({
    required this.schedule,
    required this.onClose,
  });

  String _fmt(DateTime dt) {
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final groupId = context.read<GroupProvider>().groupId;
    final title = schedule['title'] as String? ?? '';
    final description = schedule['description'] as String? ?? '';
    final location = schedule['location'] as Map<String, dynamic>?;
    final locationName = location?['name'] as String? ?? '';
    final start = (schedule['start_time'] as Timestamp?)?.toDate();
    final end = (schedule['end_time'] as Timestamp?)?.toDate();
    final scheduleId = schedule['id'] as String? ?? '';
    final canEdit = schedule['can_edit'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Row(
            children: [
              Text(
                '일정 상세',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? l.scheduleDetail : title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                if (start != null)
                  _ScheduleInfoRow(
                    icon: Icons.play_circle_outline,
                    label: l.startTime,
                    value: _fmt(start),
                  ),
                if (end != null) ...[
                  const SizedBox(height: 12),
                  _ScheduleInfoRow(
                    icon: Icons.stop_circle_outlined,
                    label: l.endTime,
                    value: _fmt(end),
                  ),
                ],
                if (locationName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ScheduleInfoRow(
                    icon: Icons.location_on_outlined,
                    label: l.location,
                    value: locationName,
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '설명',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: scheduleId.isEmpty
                        ? null
                        : () {
                            final gp = context.read<GroupProvider>();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChangeNotifierProvider.value(
                                  value: gp,
                                  child: ScheduleDetailScreen(
                                    groupId: groupId,
                                    scheduleId: scheduleId,
                                    canEdit: canEdit,
                                  ),
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(l.scheduleDetail),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ScheduleInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
