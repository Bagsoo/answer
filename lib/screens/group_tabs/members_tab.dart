import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../services/friend_service.dart';
import '../../services/group_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/group_provider.dart';
import '../../widgets/groups/group_notice_sheet.dart';
import '../chat_room_screen.dart';
import '../user_profile_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

const _kAllTag = '__ALL__';

class MembersTab extends StatefulWidget {
  // groupId는 GroupProvider에서 가져오므로 파라미터 불필요
  const MembersTab({super.key});

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTag;
  bool _showSearch = false;
  bool _noticeExpanded = false;

  List<QueryDocumentSnapshot> _members = [];
  List<String> _tagList = [];
  bool _loading = true;

  // myRole/myPerms는 GroupProvider에서 가져오므로 별도 구독 불필요
  StreamSubscription? _membersSub;
  StreamSubscription? _tagsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // initState에서 context.read 사용 시 didChangeDependencies 사용
    if (_membersSub == null) {
      final groupId = context.read<GroupProvider>().groupId;
      _subscribeMembers(groupId);
      _subscribeTags(groupId);
    }
  }

  void _subscribeMembers(String groupId) {
    _membersSub = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .orderBy('joined_at', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final sorted = [...snap.docs]..sort((a, b) {
          final aRole = (a.data() as Map)['role'] as String? ?? '';
          final bRole = (b.data() as Map)['role'] as String? ?? '';
          if (aRole == 'owner') return -1;
          if (bRole == 'owner') return 1;
          return 0;
        });
      setState(() {
        _members = sorted;
        _loading = false;
      });
    });
  }

  void _subscribeTags(String groupId) {
    _tagsSub = context
        .read<GroupService>()
        .getGroupTags(groupId)
        .listen((tags) {
      if (mounted) setState(() => _tagList = tags);
    });
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _tagsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // GroupProvider에서 myRole/myPerms 읽기 (별도 구독 없이)
    final gp = context.watch<GroupProvider>();
    final myRole = gp.myRole;
    final myPerms = gp.myPerms;
    final groupId = gp.groupId;
    final canManagePerms = gp.canManagePermissions;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _members.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['display_name'] as String? ?? '').toLowerCase();
      final memberTags = List<String>.from(data['tags'] as List? ?? []);
      final photoUrl = data['profile_image'] as String? ?? '';
      final nameMatch =
          _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final tagMatch =
          _selectedTag == null || memberTags.contains(_selectedTag);
      return nameMatch && tagMatch;
    }).toList();

    final hasFilter = _searchQuery.isNotEmpty || _selectedTag != null;

    return Column(
      children: [
        StreamBuilder<Map<String, dynamic>?>(
          stream: context.read<GroupService>().streamLatestGroupNotice(groupId),
          builder: (context, noticeSnap) {
            final latestNotice = noticeSnap.data;
            final summary = latestNotice?['text'] as String? ?? '';
            
            final createdTime = (latestNotice?['created_at'] as Timestamp?)?.toDate();
            final myLastRead = gp.myLastReadNoticeTime;
            final hasUnread = latestNotice != null && (myLastRead == null || (createdTime != null && createdTime.isAfter(myLastRead)));

            return Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _noticeExpanded = !_noticeExpanded);
                    if (_noticeExpanded && hasUnread) {
                      context.read<GroupService>().updateLastReadNoticeTime(groupId);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.onSurface.withOpacity(0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                l.groupNotice,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (hasUnread)
                                Container(
                                  margin: const EdgeInsets.only(left: 4, bottom: 6),
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          _noticeExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_noticeExpanded)
                  InkWell(
                    onTap: () {
                      if (hasUnread) {
                        context.read<GroupService>().updateLastReadNoticeTime(groupId);
                      }
                      _showGroupNoticeSheet(context, groupId);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.3),
                        border: Border(
                          bottom: BorderSide(
                            color: colorScheme.primary.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latestNotice == null ? l.noNotices : l.currentNotice,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            latestNotice == null ? l.groupNoticeTapToOpen : summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: latestNotice == null ? FontWeight.w500 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        // ── 툴바 ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                }),
                child: Icon(
                  _showSearch ? Icons.search_off : Icons.search,
                  size: 20,
                  color: _showSearch
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 8),
              if (_showSearch)
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '이름으로 검색...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Icon(Icons.clear, size: 16),
                            )
                          : null,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (_tagList.isNotEmpty)
                _TagDropdownButton(
                  tagList: _tagList,
                  selectedTag: _selectedTag,
                  colorScheme: colorScheme,
                  onChanged: (val) => setState(() => _selectedTag = val),
                ),
              if (hasFilter)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedTag = null;
                      _searchQuery = '';
                      _searchController.clear();
                      _showSearch = false;
                    }),
                    child: Icon(Icons.filter_alt_off,
                        size: 18, color: colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),

        if (_selectedTag != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              Icon(Icons.label, size: 13, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(_selectedTag!,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text('필터 중',
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.4))),
            ]),
          ),

        const Divider(height: 1),

        // ── 멤버 리스트 ─────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 64,
                          color: colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(
                        _members.isEmpty
                            ? l.noMembers
                            : l.noSearchResults,
                        style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.4)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final data =
                        filtered[index].data() as Map<String, dynamic>;
                    final uid = filtered[index].id;
                    final role = data['role'] as String? ?? 'member';
                    final displayName =
                        data['display_name'] as String? ?? l.unknown;
                    final photoUrl = data['profile_image'] as String? ?? '';
                    final perms =
                        data['permissions'] as Map<String, dynamic>? ?? {};
                    final memberTags =
                        List<String>.from(data['tags'] as List? ?? []);
                    final isOwner = role == 'owner';
                    final isMe = uid == gp.currentUserId;

                    return ListTile(
                      onTap: () => _showMemberProfile(
                        context, uid, displayName, role, perms,
                        memberTags, isMe, canManagePerms,
                        myRole, myPerms, groupId, l, colorScheme, photoUrl,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isOwner
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) 
                          ? CachedNetworkImageProvider(photoUrl) 
                          : null,                        
                        child: (photoUrl == null || photoUrl.isEmpty) ?
                        Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isOwner
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ) : null,
                      ),
                      title: Text(
                        isMe ? '$displayName (${l.me})' : displayName,
                        style: TextStyle(
                          fontWeight:
                              isOwner ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOwner ? l.roleOwner : l.roleMember,
                            style: TextStyle(
                              color: isOwner
                                  ? colorScheme.primary
                                  : colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                          if (memberTags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: memberTags.map((tag) {
                                  final isHighlighted = tag == _selectedTag;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isHighlighted
                                          ? colorScheme.primary
                                              .withOpacity(0.15)
                                          : colorScheme
                                              .surfaceContainerHighest,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(tag,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isHighlighted
                                              ? colorScheme.primary
                                              : colorScheme.onSurface
                                                  .withOpacity(0.5),
                                          fontWeight: isHighlighted
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        )),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                      trailing: isOwner
                          ? Icon(Icons.star_rounded,
                              color: colorScheme.primary, size: 18)
                          : isMe
                              ? null
                              : canManagePerms
                                  ? Icon(Icons.manage_accounts_outlined,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.4))
                                  : Icon(Icons.chevron_right,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.3)),
                    );
                  },
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                ),
        ),
      ],
    );
  }

  void _showGroupNoticeSheet(BuildContext context, String groupId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<GroupProvider>(),
        child: GroupNoticeSheet(groupId: groupId),
      ),
    );
  }

  void _showMemberProfile(
    BuildContext context,
    String uid,
    String displayName,
    String role,
    Map<String, dynamic> perms,
    List<String> memberTags,
    bool isMe,
    bool canManagePerms,
    String myRole,
    Map<String, dynamic> myPerms,
    String groupId,
    AppLocalizations l,
    ColorScheme colorScheme,
    String photoUrl,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: context.read<GroupProvider>(),
        child: _MemberProfileSheet(
          uid: uid,
          displayName: displayName,
          role: role,
          perms: perms,
          memberTags: memberTags,
          isMe: isMe,
          canManagePerms: canManagePerms,
          groupId: groupId,
          l: l,
          colorScheme: colorScheme,
          photoUrl: photoUrl,
        ),
      ),
    );
  }
}

// ── 태그 드롭다운 버튼 ─────────────────────────────────────────────────────────
class _TagDropdownButton extends StatelessWidget {
  final List<String> tagList;
  final String? selectedTag;
  final ColorScheme colorScheme;
  final ValueChanged<String?> onChanged;

  const _TagDropdownButton({
    required this.tagList,
    required this.selectedTag,
    required this.colorScheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = selectedTag != null;
    return GestureDetector(
      onTap: () => _showTagMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline,
                size: 16,
                color: isActive
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withOpacity(0.55)),
            if (isActive) ...[
              const SizedBox(width: 4),
              Text(selectedTag!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary)),
            ],
          ],
        ),
      ),
    );
  }

  void _showTagMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context)
        .overlay!
        .context
        .findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
            button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: _kAllTag,
          child: Row(children: [
            Icon(Icons.people_outline,
                size: 16, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text('전체',
                style: TextStyle(
                  fontSize: 13,
                  color: selectedTag == null
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  fontWeight: selectedTag == null
                      ? FontWeight.bold
                      : FontWeight.normal,
                )),
            if (selectedTag == null) ...[
              const Spacer(),
              Icon(Icons.check, size: 14, color: colorScheme.primary),
            ],
          ]),
        ),
        ...tagList.map((tag) => PopupMenuItem<String>(
              value: tag,
              child: Row(children: [
                Icon(Icons.label_outline,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 8),
                Text(tag,
                    style: TextStyle(
                      fontSize: 13,
                      color: selectedTag == tag
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontWeight: selectedTag == tag
                          ? FontWeight.bold
                          : FontWeight.normal,
                    )),
                if (selectedTag == tag) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 14, color: colorScheme.primary),
                ],
              ]),
            )),
      ],
    ).then((val) {
      if (val == null) return;
      if (val == _kAllTag) {
        onChanged(null);
      } else {
        onChanged(val);
      }
    });
  }
}

// ── 멤버 프로필 바텀시트 ──────────────────────────────────────────────────────
class _MemberProfileSheet extends StatefulWidget {
  final String uid;
  final String displayName;
  final String role;
  final Map<String, dynamic> perms;
  final List<String> memberTags;
  final bool isMe;
  final bool canManagePerms;
  final String groupId;
  final AppLocalizations l;
  final ColorScheme colorScheme;
  final String photoUrl;

  const _MemberProfileSheet({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.perms,
    required this.memberTags,
    required this.isMe,
    required this.canManagePerms,
    required this.groupId,
    required this.l,
    required this.colorScheme,
    required this.photoUrl,
  });

  @override
  State<_MemberProfileSheet> createState() => _MemberProfileSheetState();
}

class _MemberProfileSheetState extends State<_MemberProfileSheet> {
  bool _isFriend = false;
  bool _loadingData = true;
  bool _processing = false;
  String _phoneNumber = '';

  late bool _canCreateChat;
  late bool _canPostSchedule;
  late bool _canEditGroupInfo;
  late bool _canManagePermissions;
  bool _savingPerms = false;

  @override
  void initState() {
    super.initState();
    _canCreateChat = widget.perms['can_create_sub_chat'] as bool? ?? false;
    _canPostSchedule = widget.perms['can_post_schedule'] as bool? ?? false;
    _canEditGroupInfo = widget.perms['can_edit_group_info'] as bool? ?? false;
    _canManagePermissions =
        widget.perms['can_manage_permissions'] as bool? ?? false;
    _loadData();
  }

  Future<void> _loadData() async {
    final friendService = context.read<FriendService>();
    final results = await Future.wait([
      friendService.isFriend(widget.uid),
      FirebaseFirestore.instance.collection('users').doc(widget.uid).get(),
    ]);
    if (mounted) {
      setState(() {
        _isFriend = results[0] as bool;
        final userDoc = results[1] as DocumentSnapshot;
        _phoneNumber =
            (userDoc.data() as Map<String, dynamic>?)?['phone_number']
                    as String? ??
                '';
        _loadingData = false;
      });
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _savingPerms = true);
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('members')
        .doc(widget.uid)
        .update({
      'permissions': {
        'can_create_sub_chat': _canCreateChat,
        'can_post_schedule': _canPostSchedule,
        'can_edit_group_info': _canEditGroupInfo,
        'can_manage_permissions': _canManagePermissions,
        'can_write_post': true,
      }
    });
    if (mounted) {
      setState(() => _savingPerms = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l.permissionsSaved)),
      );
    }
  }

  Future<void> _transferOwnership() async {
    final l = widget.l;
    final gp = context.read<GroupProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.transferOwnership),
        content: Text(l.transferOwnershipConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.colorScheme.primary,
              foregroundColor: widget.colorScheme.onPrimary,
            ),
            child: Text(l.transferOwnership),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _processing = true);
    final success = await context
        .read<GroupService>()
        .transferOwnership(widget.groupId, widget.uid);
    if (!mounted) return;
    setState(() => _processing = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(success
              ? l.transferOwnershipSuccess
              : l.transferOwnershipFailed)),
    );
  }

  Future<void> _kickMember() async {
    final l = widget.l;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.kickMember),
        content: Text('${widget.displayName}${l.kickMemberConfirm}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.colorScheme.error,
              foregroundColor: widget.colorScheme.onError,
            ),
            child: Text(l.kickMember),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ban = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('그룹 차단'),
        content:
            Text('${widget.displayName}님이 이 그룹에 다시 가입하지 못하도록 차단할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('차단 안 함'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.colorScheme.error,
              foregroundColor: widget.colorScheme.onError,
            ),
            child: const Text('차단'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final doBan = ban ?? false;

    setState(() => _processing = true);
    final success = await context.read<GroupService>().kickMember(
          widget.groupId,
          widget.uid,
          ban: doBan,
          displayName: widget.displayName,
        );
    if (!mounted) return;
    setState(() => _processing = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(success
              ? (doBan
                  ? '${widget.displayName}님을 추방하고 차단했습니다.'
                  : l.kickMemberSuccess)
              : l.kickMemberFailed)),
    );
  }

  Future<void> _addFriend() async {
    setState(() => _processing = true);
    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    final success = await friendService.addFriend(
        widget.uid, widget.displayName,
        myName: myName);
    if (mounted) {
      setState(() {
        _isFriend = success ? true : _isFriend;
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(success
                ? widget.l.friendAdded
                : widget.l.friendAddFailed)),
      );
    }
  }

  Future<void> _openDm() async {
    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    final roomId = await friendService.getOrCreateDmRoom(
        widget.uid, widget.displayName,
        myName: myName);
    if (mounted) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomScreen(roomId: roomId),
      ));
    }
  }

  Future<void> _callPhoneNumber() async {
    if (_phoneNumber.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: _phoneNumber);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // GroupProvider에서 myRole/myPerms 실시간 반영
    final gp = context.watch<GroupProvider>();
    final colorScheme = widget.colorScheme;
    final l = widget.l;
    final name = widget.displayName;
    final photoUrl = widget.photoUrl;
    final isOwner = widget.role == 'owner';
    final showPerms = widget.canManagePerms && !widget.isMe && !isOwner;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: showPerms ? 0.75 : 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            CircleAvatar(
              radius: 40,
              backgroundColor: isOwner
                  ? colorScheme.primary
                  : colorScheme.primaryContainer,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) 
                ? CachedNetworkImageProvider(photoUrl) 
                : null,
              child: (photoUrl == null || photoUrl.isEmpty) ?
              Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isOwner
                      ? colorScheme.onPrimary
                      : colorScheme.onPrimaryContainer,
                ),
              ) : null,
            ),
            const SizedBox(height: 12),
            Text(
              widget.isMe ? '$name (${l.me})' : name,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (isOwner) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.star_rounded,
                    color: colorScheme.primary, size: 16),
                const SizedBox(width: 4),
                Text(l.roleOwner,
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600)),
              ]),
            ],
            const SizedBox(height: 4),
            if (_loadingData)
              Container(
                width: 120,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
              )
            else if (_phoneNumber.isNotEmpty)
              InkWell(
                onTap: _callPhoneNumber,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    _phoneNumber,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (!widget.isMe)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => UserProfileDetailScreen(
                        uid: widget.uid,
                        displayName: widget.displayName,
                        photoUrl: widget.photoUrl,
                      ),
                    ));
                  },
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(l.viewProfile),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (!widget.isMe) ...[
              if (_loadingData)
                const CircularProgressIndicator()
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openDm,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(l.sendDm),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isFriend
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: Icon(Icons.check_circle,
                                size: 18, color: colorScheme.primary),
                            label: Text(l.alreadyFriend,
                                style:
                                    TextStyle(color: colorScheme.primary)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: colorScheme.primary),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _processing ? null : _addFriend,
                            icon: _processing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.person_add, size: 18),
                            label: Text(l.addFriend),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                  ),
                ]),
            ],
            // 태그 편집 (owner 또는 권한 있는 멤버)
            if (gp.canManagePermissions) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.label_outline,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(l.memberTags,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              _MemberTagEditor(
                groupId: widget.groupId,
                uid: widget.uid,
                currentTags: widget.memberTags,
                colorScheme: colorScheme,
              ),
            ],
            if (showPerms) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.manage_accounts,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(l.permissions,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ]),
              const SizedBox(height: 4),
              Text(l.permissionsHint,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              const SizedBox(height: 8),
              _PermSwitch(
                label: l.permCreateChat,
                value: _canCreateChat,
                enabled: gp.canCreateSubChat,
                onChanged: (v) => setState(() => _canCreateChat = v),
                colorScheme: colorScheme,
              ),
              _PermSwitch(
                label: l.permPostSchedule,
                value: _canPostSchedule,
                enabled: gp.canPostSchedule,
                onChanged: (v) => setState(() => _canPostSchedule = v),
                colorScheme: colorScheme,
              ),
              _PermSwitch(
                label: l.permEditGroupInfo,
                value: _canEditGroupInfo,
                enabled: gp.canEditGroupInfo,
                onChanged: (v) => setState(() => _canEditGroupInfo = v),
                colorScheme: colorScheme,
              ),
              _PermSwitch(
                label: l.permManagePermissions,
                value: _canManagePermissions,
                enabled: gp.isOwner,
                onChanged: (v) =>
                    setState(() => _canManagePermissions = v),
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savingPerms ? null : _savePermissions,
                  child: _savingPerms
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.savePermissions),
                ),
              ),
            ],
            if (gp.isOwner && !widget.isMe) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _processing ? null : _transferOwnership,
                  icon: _processing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.star_outline, size: 18),
                  label: Text(l.transferOwnership),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(color: colorScheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            if (!widget.isMe &&
                !isOwner &&
                (gp.isOwner || gp.canManagePermissions)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _processing ? null : _kickMember,
                  icon: const Icon(Icons.person_off_outlined, size: 18),
                  label: Text(l.kickMember),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 권한 스위치 ───────────────────────────────────────────────────────────────
class _PermSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;

  const _PermSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Text(label,
            style: TextStyle(
              fontSize: 14,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.35),
            )),
        if (!enabled) ...[
          const SizedBox(width: 6),
          Icon(Icons.lock_outline,
              size: 13, color: colorScheme.onSurface.withOpacity(0.35)),
        ],
      ]),
      value: value,
      onChanged: enabled ? onChanged : null,
      activeColor: colorScheme.primary,
    );
  }
}

// ── 멤버 태그 편집기 ───────────────────────────────────────────────────────────
class _MemberTagEditor extends StatefulWidget {
  final String groupId;
  final String uid;
  final List<String> currentTags;
  final ColorScheme colorScheme;

  const _MemberTagEditor({
    required this.groupId,
    required this.uid,
    required this.currentTags,
    required this.colorScheme,
  });

  @override
  State<_MemberTagEditor> createState() => _MemberTagEditorState();
}

class _MemberTagEditorState extends State<_MemberTagEditor> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.currentTags);
  }

  @override
  Widget build(BuildContext context) {
    final groupService = context.read<GroupService>();
    // 태그 목록은 GroupProvider에서 이미 구독 중 → 재활용
    final tags = context.watch<GroupProvider>().tags;

    if (tags.isEmpty) {
      return Text(
        AppLocalizations.of(context).noTags,
        style: TextStyle(
            fontSize: 12,
            color: widget.colorScheme.onSurface.withOpacity(0.4)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: tags.map((tag) {
        final selected = _selected.contains(tag);
        return FilterChip(
          label: Text(tag, style: const TextStyle(fontSize: 12)),
          selected: selected,
          onSelected: (val) async {
            final newTags = List<String>.from(_selected);
            if (val) {
              newTags.add(tag);
            } else {
              newTags.remove(tag);
            }
            setState(() => _selected = newTags);
            await groupService.updateMemberTags(
                widget.groupId, widget.uid, newTags);
          },
          selectedColor: widget.colorScheme.primary.withOpacity(0.2),
          checkmarkColor: widget.colorScheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }
}
