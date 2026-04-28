import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../services/friend_service.dart';
import '../../services/group_service.dart';
import '../../services/user_notification_service.dart';
import '../../services/local_preferences_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/group_provider.dart';
import '../../widgets/groups/group_notice_sheet.dart';
import '../chat_room_screen.dart';
import '../user_profile_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

const _kAllTag = '__ALL__';

class MembersTab extends StatefulWidget {
  final bool isDesktopMode;
  final String? selectedMemberId;
  final ValueChanged<Map<String, dynamic>>? onMemberSelected;

  const MembersTab({
    super.key,
    this.isDesktopMode = false,
    this.selectedMemberId,
    this.onMemberSelected,
  });

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;

  String _searchQuery = '';
  String? _selectedTag;
  bool _showSearch = false;
  bool _noticeExpanded = false;
  DateTime? _localLastReadNoticeTime;

  List<QueryDocumentSnapshot> _members = [];
  List<String> _tagList = [];
  bool _loading = true;

  StreamSubscription? _membersSub;
  StreamSubscription? _tagsSub;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScaleAnimation =
        CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeOut);
    _fabAnimationController.forward();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      if (_fabAnimationController.isCompleted) _fabAnimationController.reverse();
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
      if (_fabAnimationController.isDismissed) _fabAnimationController.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_membersSub == null) {
      final groupId = context.read<GroupProvider>().groupId;
      _subscribeMembers(groupId);
      _subscribeTags(groupId);
      _loadLocalLastReadNoticeTime(groupId);
    }
  }

  Future<void> _loadLocalLastReadNoticeTime(String groupId) async {
    final uid = context.read<UserProvider>().uid;
    final key = LocalPreferencesService.groupNoticeLastReadKey(uid, groupId);
    final millis = await LocalPreferencesService.getInt(key);
    if (!mounted || millis == null) return;
    setState(() {
      _localLastReadNoticeTime = DateTime.fromMillisecondsSinceEpoch(millis);
    });
  }

  Future<void> _markNoticeRead(String groupId, {DateTime? referenceTime}) async {
    final uid = context.read<UserProvider>().uid;
    final time = referenceTime ?? DateTime.now();
    final key = LocalPreferencesService.groupNoticeLastReadKey(uid, groupId);
    await LocalPreferencesService.setInt(key, time.millisecondsSinceEpoch);
    if (mounted) setState(() => _localLastReadNoticeTime = time);
    unawaited(context.read<GroupService>().updateLastReadNoticeTime(groupId));
  }

  void _subscribeMembers(String groupId) {
    final myUid = context.read<UserProvider>().uid;
    _membersSub = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final sorted = [...snap.docs]..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aUid = a.id;
          final bUid = b.id;
          final aRole = aData['role'] as String? ?? 'member';
          final bRole = bData['role'] as String? ?? 'member';
          final aJoined = aData['joined_at'] as Timestamp? ?? Timestamp.now();
          final bJoined = bData['joined_at'] as Timestamp? ?? Timestamp.now();

          // 1. 나 (Me) 우선순위
          if (aUid == myUid) return -1;
          if (bUid == myUid) return 1;

          // 2. 역할 가중치 계산 (owner: 10, manager: 5, member: 0)
          int getRoleWeight(String role) {
            if (role == 'owner') return 10;
            if (role == 'manager') return 5;
            return 0;
          }

          final aWeight = getRoleWeight(aRole);
          final bWeight = getRoleWeight(bRole);

          if (aWeight != bWeight) {
            return bWeight.compareTo(aWeight); // 높은 가중치(owner)가 위로
          }

          // 3. 같은 역할(매니저끼리, 멤버끼리)일 경우 가입 순 (오래된 순)
          return aJoined.compareTo(bJoined);
        });
      setState(() {
        _members = sorted;
        _loading = false;
      });
    });
  }

  void _subscribeTags(String groupId) {
    _tagsSub = context.read<GroupService>().getGroupTags(groupId).listen((tags) {
      if (mounted) setState(() => _tagList = tags);
    });
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _tagsSub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.watch<GroupProvider>();
    final groupId = gp.groupId;
    final canManagePerms = gp.canManagePermissions;

    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = _members.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['display_name'] as String? ?? '').toLowerCase();
      final memberTags = List<String>.from(data['tags'] as List? ?? []);
      final nameMatch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final tagMatch = _selectedTag == null || memberTags.contains(_selectedTag);
      return nameMatch && tagMatch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManagePerms ? ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton(
          onPressed: () => _showInviteFriendSheet(context, gp),
          child: const Icon(Icons.person_add_alt_1),
        ),
      ) : null,
      body: Column(
        children: [
          // ── 공지사항 영역 ──
          StreamBuilder<Map<String, dynamic>?>(
            stream: context.read<GroupService>().streamLatestGroupNotice(groupId),
            builder: (context, noticeSnap) {
              final latestNotice = noticeSnap.data;
              final summary = latestNotice?['text'] as String? ?? '';
              final createdTime = (latestNotice?['created_at'] as Timestamp?)?.toDate();
              final myLastRead = gp.myLastReadNoticeTime;
              DateTime? effectiveLastRead = (myLastRead == null) ? _localLastReadNoticeTime : 
                (_localLastReadNoticeTime == null ? myLastRead : 
                (myLastRead.isAfter(_localLastReadNoticeTime!) ? myLastRead : _localLastReadNoticeTime));
              
              final hasUnread = latestNotice != null && (effectiveLastRead == null || (createdTime != null && createdTime.isAfter(effectiveLastRead)));

              return Column(
                children: [
                  InkWell(
                    onTap: () async {
                      setState(() => _noticeExpanded = !_noticeExpanded);
                      if (_noticeExpanded && hasUnread) await _markNoticeRead(groupId, referenceTime: createdTime);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        border: Border(bottom: BorderSide(color: colorScheme.onSurface.withOpacity(0.08))),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.campaign_outlined, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l.groupNotice, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                          if (hasUnread) Container(margin: const EdgeInsets.only(left: 4, bottom: 6), width: 5, height: 5, decoration: BoxDecoration(color: colorScheme.error, shape: BoxShape.circle)),
                          Icon(_noticeExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: colorScheme.onSurface.withOpacity(0.55)),
                        ],
                      ),
                    ),
                  ),
                  if (_noticeExpanded)
                    InkWell(
                      onTap: () => _showGroupNoticeSheet(context, groupId),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          border: Border(bottom: BorderSide(color: colorScheme.primary.withOpacity(0.1))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(latestNotice == null ? l.noNotices : l.currentNotice, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colorScheme.primary)),
                            const SizedBox(height: 6),
                            Text(latestNotice == null ? l.groupNoticeTapToOpen : summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, color: colorScheme.onPrimaryContainer, fontWeight: latestNotice == null ? FontWeight.w500 : FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          // ── 툴바 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) { _searchQuery = ''; _searchController.clear(); }
                  }),
                  child: Icon(_showSearch ? Icons.search_off : Icons.search, size: 20, color: _showSearch ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.5)),
                ),
                const SizedBox(width: 8),
                if (_showSearch)
                  Expanded(child: TextField(controller: _searchController, autofocus: true, onChanged: (v) => setState(() => _searchQuery = v), style: const TextStyle(fontSize: 14), decoration: InputDecoration(hintText: l.searchPlaceholder, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), suffixIcon: _searchQuery.isNotEmpty ? GestureDetector(onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); }, child: const Icon(Icons.clear, size: 16)) : null))),
                if (_tagList.isNotEmpty) _TagDropdownButton(tagList: _tagList, selectedTag: _selectedTag, colorScheme: colorScheme, onChanged: (val) => setState(() => _selectedTag = val)),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── 멤버 리스트 ──
          Expanded(
            child: filtered.isEmpty ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 64, color: colorScheme.onSurface.withOpacity(0.2)), const SizedBox(height: 16), Text(_members.isEmpty ? l.noMembers : l.noSearchResults, style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)))])) :
              ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final data = filtered[index].data() as Map<String, dynamic>;
                  final uid = filtered[index].id;
                  final role = data['role'] as String? ?? 'member';
                  final displayName = data['display_name'] as String? ?? l.unknown;
                  final photoUrl = data['profile_image'] as String? ?? '';
                  final isOwner = role == 'owner';
                  final isManager = role == 'manager';
                  final isMe = uid == gp.currentUserId;

                  return ListTile(
                    onTap: () => _showMemberProfile(context, uid, displayName, role, data['permissions'] ?? {}, List<String>.from(data['tags'] ?? []), isMe, canManagePerms, gp.myRole, gp.myPerms, groupId, l, colorScheme, photoUrl),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: isOwner ? colorScheme.primary : (isManager ? colorScheme.secondary : colorScheme.surfaceContainerHighest),
                          backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
                          child: photoUrl.isEmpty ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?', style: TextStyle(color: isOwner ? colorScheme.onPrimary : (isManager ? colorScheme.onSecondary : colorScheme.onSurface), fontWeight: FontWeight.bold)) : null,
                        ),
                        if (isOwner || isManager)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: isOwner 
                                ? Colors.amber[700] 
                                : const Color(0xFFE0C1B3), // Rose Gold
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(1, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    title: Text(isMe ? '$displayName (${l.me})' : displayName, style: TextStyle(fontWeight: (isOwner || isManager) ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(isOwner ? l.roleOwner : (isManager ? l.roleManager : l.roleMember), style: TextStyle(color: isOwner ? colorScheme.primary : (isManager ? colorScheme.secondary : colorScheme.onSurface.withOpacity(0.5)), fontSize: 12)),
                    trailing: (canManagePerms && !isMe && !isOwner) ? Icon(Icons.manage_accounts_outlined, color: colorScheme.onSurface.withOpacity(0.4)) : null,
                  );
                },
              ),
          ),
        ],
      ),
    );
  }

  void _showInviteFriendSheet(BuildContext context, GroupProvider gp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _InviteFriendSheet(
        groupId: gp.groupId,
        groupName: gp.name,
        groupPhotoUrl: gp.profileImageUrl,
        existingMemberUids: _members.map((m) => m.id).toSet(),
      ),
    );
  }

  void _showGroupNoticeSheet(BuildContext context, String groupId) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(value: context.read<GroupProvider>(), child: GroupNoticeSheet(groupId: groupId)),
    );
  }

  void _showMemberProfile(BuildContext context, String uid, String displayName, String role, Map<String, dynamic> perms, List<String> tags, bool isMe, bool canManage, String myRole, Map<String, dynamic> myPerms, String groupId, AppLocalizations l, ColorScheme cs, String photo) {
    showModalBottomSheet(
      context: context, backgroundColor: cs.surface, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: context.read<GroupProvider>(),
        child: _MemberProfileSheet(uid: uid, displayName: displayName, role: role, perms: perms, memberTags: tags, isMe: isMe, canManagePerms: canManage, groupId: groupId, l: l, colorScheme: cs, photoUrl: photo),
      ),
    );
  }
}

// ── 친구 초대 바텀시트 ────────────────────────────────────────────────────────
class _InviteFriendSheet extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? groupPhotoUrl;
  final Set<String> existingMemberUids;

  const _InviteFriendSheet({required this.groupId, required this.groupName, this.groupPhotoUrl, required this.existingMemberUids});

  @override
  State<_InviteFriendSheet> createState() => _InviteFriendSheetState();
}

class _InviteFriendSheetState extends State<_InviteFriendSheet> {
  final Set<String> _selectedUids = {};
  final Map<String, String?> _selectedPhotos = {};
  final Map<String, String> _selectedNames = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sending = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final friendService = context.read<FriendService>();

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.8, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(l.inviteMembers, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          if (_selectedUids.isNotEmpty)
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: Stack(
                                  children: _selectedUids.toList().asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final uid = entry.value;
                                    final photo = _selectedPhotos[uid];
                                    final name = _selectedNames[uid] ?? '?';
                                    
                                    return Positioned(
                                      left: index * 20.0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: cs.surface, width: 2),
                                        ),
                                        child: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: cs.primaryContainer,
                                          backgroundImage: (photo != null && photo.isNotEmpty) ? CachedNetworkImageProvider(photo) : null,
                                          child: (photo == null || photo.isEmpty) ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(fontSize: 10, color: cs.onPrimaryContainer)) : null,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_selectedUids.isNotEmpty)
                      TextButton(
                        onPressed: _sending ? null : _sendInvites,
                        child: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text('${l.invite} (${_selectedUids.length})'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: l.searchPlaceholder,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); }) : null,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: friendService.getFriends(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final allInvitable = snapshot.data!.where((f) => !widget.existingMemberUids.contains(f['uid'])).toList();
                final friends = allInvitable.where((f) {
                  final name = (f['display_name'] as String? ?? '').toLowerCase();
                  return name.contains(_searchQuery.toLowerCase());
                }).toList();
                
                if (allInvitable.isEmpty) return Center(child: Text(l.noInvitableMembers));
                if (friends.isEmpty) return Center(child: Text(l.noSearchResults));

                return ListView.builder(
                  controller: scrollController, itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final f = friends[index];
                    final uid = f['uid'] as String;
                    final isSelected = _selectedUids.contains(uid);
                    final name = f['display_name'] as String? ?? l.unknown;
                    final photo = f['photo_url'] as String? ?? '';

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedUids.add(uid);
                            _selectedPhotos[uid] = photo;
                            _selectedNames[uid] = name;
                          } else {
                            _selectedUids.remove(uid);
                            _selectedPhotos.remove(uid);
                            _selectedNames.remove(uid);
                          }
                        });
                      },
                      secondary: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                        child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)) : null,
                      ),
                      title: Text(name),
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvites() async {
    setState(() => _sending = true);
    final userNotiService = context.read<UserNotificationService>();
    final myName = context.read<UserProvider>().name;
    try {
      for (final targetUid in _selectedUids) {
        await userNotiService.sendGroupInvite(targetUid: targetUid, groupId: widget.groupId, groupName: widget.groupName, inviterName: myName, groupPhotoUrl: widget.groupPhotoUrl);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedUids.length}명에게 초대를 보냈습니다.')));
      }
    } catch (e) { if (mounted) setState(() => _sending = false); }
  }
}

// ── 태그 드롭다운 버튼 ─────────────────────────────────────────────────────────
class _TagDropdownButton extends StatelessWidget {
  final List<String> tagList;
  final String? selectedTag;
  final ColorScheme colorScheme;
  final ValueChanged<String?> onChanged;

  const _TagDropdownButton({required this.tagList, required this.selectedTag, required this.colorScheme, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isActive = selectedTag != null;
    return GestureDetector(
      onTap: () => _showTagMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: isActive ? colorScheme.primary : colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline, size: 16, color: isActive ? colorScheme.onPrimary : colorScheme.onSurface.withOpacity(0.55)),
            if (isActive) ...[const SizedBox(width: 4), Text(selectedTag!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onPrimary))],
          ],
        ),
      ),
    );
  }

  void _showTagMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(Rect.fromPoints(button.localToGlobal(Offset.zero, ancestor: overlay), button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay)), Offset.zero & overlay.size);

    showMenu<String>(
      context: context, position: position, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(value: _kAllTag, child: Row(children: [Icon(Icons.people_outline, size: 16, color: colorScheme.onSurface.withOpacity(0.5)), const SizedBox(width: 8), Text('전체', style: TextStyle(fontSize: 13, color: selectedTag == null ? colorScheme.primary : colorScheme.onSurface, fontWeight: selectedTag == null ? FontWeight.bold : FontWeight.normal)), if (selectedTag == null) ...[const Spacer(), Icon(Icons.check, size: 14, color: colorScheme.primary)]])),
        ...tagList.map((tag) => PopupMenuItem<String>(value: tag, child: Row(children: [Icon(Icons.label_outline, size: 16, color: colorScheme.onSurface.withOpacity(0.5)), const SizedBox(width: 8), Text(tag, style: TextStyle(fontSize: 13, color: selectedTag == tag ? colorScheme.primary : colorScheme.onSurface, fontWeight: selectedTag == tag ? FontWeight.bold : FontWeight.normal)), if (selectedTag == tag) ...[const Spacer(), Icon(Icons.check, size: 14, color: colorScheme.primary)]]))),
      ],
    ).then((val) { if (val == null) return; if (val == _kAllTag) onChanged(null); else onChanged(val); });
  }
}

// ── 멤버 프로필 바텀시트 ──
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

  const _MemberProfileSheet({required this.uid, required this.displayName, required this.role, required this.perms, required this.memberTags, required this.isMe, required this.canManagePerms, required this.groupId, required this.l, required this.colorScheme, required this.photoUrl});

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
  late String _currentRole;
  bool _savingPerms = false;

  @override
  void initState() {
    super.initState();
    _currentRole = widget.role;
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
      FirebaseFirestore.instance.collection('users').doc(widget.uid).get()
    ]);
    if (mounted) {
      setState(() {
        _isFriend = results[0] as bool;
        final userDoc = results[1] as DocumentSnapshot;
        _phoneNumber =
            (userDoc.data() as Map<String, dynamic>?)?['phone_number'] as String? ??
                '';
        _loadingData = false;
      });
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _savingPerms = true);
    final success = await context.read<GroupService>().updateMemberRoleAndPermissions(
          groupId: widget.groupId,
          targetUid: widget.uid,
          role: _currentRole,
          permissions: {
            'can_create_sub_chat': _canCreateChat,
            'can_post_schedule': _canPostSchedule,
            'can_edit_group_info': _canEditGroupInfo,
            'can_manage_permissions': _canManagePermissions,
            'can_write_post': true,
          },
        );
    if (mounted) {
      setState(() => _savingPerms = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.l.permissionsSaved)));
      }
    }
  }

  Future<void> _transferOwnership() async {
    final l = widget.l;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(l.transferOwnership), content: Text(l.transferOwnershipConfirm), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: widget.colorScheme.primary, foregroundColor: widget.colorScheme.onPrimary), child: Text(l.transferOwnership))]));
    if (confirmed != true || !mounted) return;
    setState(() => _processing = true);
    final success = await context.read<GroupService>().transferOwnership(widget.groupId, widget.uid, widget.displayName, widget.photoUrl);
    if (!mounted) return;
    setState(() => _processing = false); Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? l.transferOwnershipSuccess : l.transferOwnershipFailed)));
  }

  Future<void> _kickMember() async {
    final l = widget.l;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(l.kickMember), content: Text('${widget.displayName}${l.kickMemberConfirm}'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: widget.colorScheme.error, foregroundColor: widget.colorScheme.onError), child: Text(l.kickMember))]));
    if (confirmed != true || !mounted) return;
    final ban = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('그룹 차단'), content: Text('${widget.displayName}님이 이 그룹에 다시 가입하지 못하도록 차단할까요?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('차단 안 함')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: widget.colorScheme.error, foregroundColor: widget.colorScheme.onError), child: const Text('차단'))]));
    if (!mounted) return;
    final doBan = ban ?? false;
    setState(() => _processing = true);
    final success = await context.read<GroupService>().kickMember(widget.groupId, widget.uid, ban: doBan, displayName: widget.displayName);
    if (!mounted) return;
    setState(() => _processing = false); Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? (doBan ? '${widget.displayName}님을 추방하고 차단했습니다.' : l.kickMemberSuccess) : l.kickMemberFailed)));
  }

  Future<void> _addFriend() async {
    setState(() => _processing = true);
    final success = await context.read<FriendService>().addFriend(widget.uid, widget.displayName, myName: context.read<UserProvider>().name);
    if (mounted) { setState(() { _isFriend = success ? true : _isFriend; _processing = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? widget.l.friendAdded : widget.l.friendAddFailed))); }
  }

  Future<void> _openDm() async {
    final roomId = await context.read<FriendService>().getOrCreateDmRoom(widget.uid, widget.displayName, myName: context.read<UserProvider>().name);
    if (mounted) { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatRoomScreen(roomId: roomId))); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final l = widget.l;
    final gp = context.watch<GroupProvider>();
    final isTargetOwner = widget.role == 'owner';
    final isTargetManager = widget.role == 'manager';

    final canIEdit = gp.isOwner || (gp.myRole == 'manager' && gp.canManagePermissions);
    final showPermsSection = canIEdit && !widget.isMe && !isTargetOwner;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: showPermsSection ? 0.85 : 0.45,
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
                        color: cs.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2)))),
            CircleAvatar(
                radius: 40,
                backgroundColor: isTargetOwner ? cs.primary : cs.primaryContainer,
                backgroundImage: (widget.photoUrl.isNotEmpty)
                    ? CachedNetworkImageProvider(widget.photoUrl)
                    : null,
                child: (widget.photoUrl.isEmpty)
                    ? Text(
                        widget.displayName.isNotEmpty
                            ? widget.displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isTargetOwner
                                ? cs.onPrimary
                                : cs.onPrimaryContainer))
                    : null),
            const SizedBox(height: 12),
            Text(widget.isMe ? '${widget.displayName} (${l.me})' : widget.displayName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isTargetOwner ? cs.primary : (isTargetManager ? cs.secondary : cs.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isTargetOwner ? l.roleOwner : (isTargetManager ? '매니저' : l.roleMember),
                style: TextStyle(
                  color: isTargetOwner ? cs.onPrimary : (isTargetManager ? cs.onSecondary : cs.onSurfaceVariant),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 24),
            if (!widget.isMe) ...[
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _openDm,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: Text(l.sendDm),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))))),
                const SizedBox(width: 12),
                Expanded(
                    child: _isFriend
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: Icon(Icons.check_circle,
                                size: 18, color: cs.primary),
                            label: Text(l.alreadyFriend,
                                style: TextStyle(color: cs.primary)),
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: cs.primary)))
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))))),
              ]),
            ],

            if (gp.canManagePermissions) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.label_outline, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(l.memberTags,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
              ]),
              const SizedBox(height: 8),
              _MemberTagEditor(
                  groupId: widget.groupId,
                  uid: widget.uid,
                  currentTags: widget.memberTags,
                  colorScheme: cs),
            ],

            if (showPermsSection) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.manage_accounts, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(l.adminPermissions,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
              ]),
              
              if (gp.isOwner)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'member', label: Text(l.roleGeneralMember)),
                      ButtonSegment(value: 'manager', label: Text(l.roleManager)),
                    ],
                    selected: {_currentRole},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() => _currentRole = newSelection.first);
                    },
                  ),
                ),

              if (_currentRole == 'manager') ...[
                _PermSwitch(
                    label: l.permCreateChat,
                    value: _canCreateChat,
                    onChanged: (v) => setState(() => _canCreateChat = v),
                    colorScheme: cs),
                _PermSwitch(
                    label: l.permPostSchedule,
                    value: _canPostSchedule,
                    onChanged: (v) => setState(() => _canPostSchedule = v),
                    colorScheme: cs),
                _PermSwitch(
                    label: l.permEditGroupInfo,
                    value: _canEditGroupInfo,
                    onChanged: (v) => setState(() => _canEditGroupInfo = v),
                    colorScheme: cs),
                _PermSwitch(
                    label: l.permManagePermissions,
                    value: _canManagePermissions,
                    onChanged: (v) => setState(() => _canManagePermissions = v),
                    colorScheme: cs),
              ],
              
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: _savingPerms ? null : _savePermissions,
                      child: _savingPerms
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(l.savePermissions))),
            ],

            if (canIEdit && !widget.isMe && !isTargetOwner) ...[
              const SizedBox(height: 16),
              const Divider(),
              if (gp.isOwner)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                          onPressed: _processing ? null : _transferOwnership,
                          icon: const Icon(Icons.star_outline, size: 18),
                          label: Text(l.transferOwnership),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: cs.primary,
                              side: BorderSide(color: cs.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))))),
                ),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: _processing ? null : _kickMember,
                      icon: const Icon(Icons.person_off_outlined, size: 18),
                      label: Text(l.kickMember),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))))),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 권한 스위치 & 태그 편집기 ──
class _PermSwitch extends StatelessWidget {
  final String label; final bool value; final bool enabled; final ValueChanged<bool> onChanged; final ColorScheme colorScheme;
  const _PermSwitch({required this.label, required this.value, required this.onChanged, required this.colorScheme, this.enabled = true});
  @override Widget build(BuildContext context) { return SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Row(children: [Text(label, style: TextStyle(fontSize: 14, color: enabled ? colorScheme.onSurface : colorScheme.onSurface.withOpacity(0.35))), if (!enabled) ...[const SizedBox(width: 6), Icon(Icons.lock_outline, size: 13, color: colorScheme.onSurface.withOpacity(0.35))]]), value: value, onChanged: enabled ? onChanged : null, activeColor: colorScheme.primary); }
}

class _MemberTagEditor extends StatefulWidget {
  final String groupId; final String uid; final List<String> currentTags; final ColorScheme colorScheme;
  const _MemberTagEditor({required this.groupId, required this.uid, required this.currentTags, required this.colorScheme});
  @override State<_MemberTagEditor> createState() => _MemberTagEditorState();
}
class _MemberTagEditorState extends State<_MemberTagEditor> {
  late List<String> _selected; @override void initState() { super.initState(); _selected = List.from(widget.currentTags); }
  @override Widget build(BuildContext context) {
    final tags = context.watch<GroupProvider>().tags;
    if (tags.isEmpty) return Text(AppLocalizations.of(context).noTags, style: TextStyle(fontSize: 12, color: widget.colorScheme.onSurface.withOpacity(0.4)));
    return Wrap(spacing: 8, runSpacing: 4, children: tags.map((tag) {
      final selected = _selected.contains(tag);
      return FilterChip(label: Text(tag, style: const TextStyle(fontSize: 12)), selected: selected, onSelected: (val) async { final newTags = List<String>.from(_selected); if (val) newTags.add(tag); else newTags.remove(tag); setState(() => _selected = newTags); await context.read<GroupService>().updateMemberTags(widget.groupId, widget.uid, newTags); }, selectedColor: widget.colorScheme.primary.withOpacity(0.2), checkmarkColor: widget.colorScheme.primary, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap);
    }).toList());
  }
}
