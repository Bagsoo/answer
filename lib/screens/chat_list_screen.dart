import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/group_settings/group_avatar_widget.dart';
import 'chat_room_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── 유저 프로필 메모리 캐시 ────────────────────────────────────────────────────
class _UserCache {
  static final Map<String, Map<String, dynamic>> _cache = {};

  static Future<Map<String, dynamic>> get(String uid) async {
    if (_cache.containsKey(uid)) return _cache[uid]!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = {
      'name': doc.data()?['name'] as String? ?? '',
      'photo': doc.data()?['profile_image'] as String? ?? '',
    };
    _cache[uid] = data;
    return data;
  }

  static void invalidate(String uid) => _cache.remove(uid);
}

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatSheet(context, l, colorScheme),
        child: const Icon(Icons.edit_outlined),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: chatService.getChatRooms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final rooms = snapshot.data ?? [];

          if (rooms.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noChats,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        _showNewChatSheet(context, l, colorScheme),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l.startNewChat),
                  ),
                ],
              ),
            );
          }

          final dmRooms =
              rooms.where((r) => r['ref_group_id'] == null).toList();

          final Map<String, List<Map<String, dynamic>>> groupedRooms = {};
          for (final room
              in rooms.where((r) => r['ref_group_id'] != null)) {
            final groupId = room['ref_group_id'] as String;
            groupedRooms.putIfAbsent(groupId, () => []).add(room);
          }

          final sortedGroups = groupedRooms.entries.toList()
            ..sort((a, b) {
              final aLatest = _latestTime(a.value);
              final bLatest = _latestTime(b.value);
              if (aLatest == null && bLatest == null) return 0;
              if (aLatest == null) return 1;
              if (bLatest == null) return -1;
              return bLatest.compareTo(aLatest);
            });

          return ListView(
            children: [
              ...dmRooms.map((room) {
                final type = room['type'] as String? ?? 'direct';
                if (type == 'direct') {
                  // 1:1 DM → 상대방 이름/사진 동적 fetch
                  return _DmTile(
                    room: room,
                    colorScheme: colorScheme,
                    myUid: _myUid,
                  );
                }
                return _ChatTile(
                  room: room,
                  colorScheme: colorScheme,
                  myUid: _myUid,
                );
              }),

              if (dmRooms.isNotEmpty && sortedGroups.isNotEmpty)
                Divider(
                    height: 8,
                    thickness: 8,
                    color: colorScheme.surfaceContainerHighest),

              ...sortedGroups.map((entry) {
                final roomsInGroup = entry.value;
                final groupName =
                    roomsInGroup.first['group_name'] as String? ??
                        l.unknown;
                final groupId = entry.key;
                final totalUnread = roomsInGroup.fold<int>(
                    0, (sum, r) => sum + ((r['unread_cnt'] as int?) ?? 0));

                return _GroupChatSection(
                  key: ValueKey(groupId),
                  groupId: groupId,
                  groupName: groupName,
                  rooms: roomsInGroup,
                  totalUnread: totalUnread,
                  colorScheme: colorScheme,
                  myUid: _myUid,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  DateTime? _latestTime(List<Map<String, dynamic>> rooms) {
    for (final room in rooms) {
      final t = room['last_time'];
      if (t != null) return (t as dynamic).toDate();
    }
    return null;
  }

  void _showNewChatSheet(
      BuildContext context, AppLocalizations l, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.person_outline,
                      color: colorScheme.onPrimaryContainer),
                ),
                title: Text(l.startDm,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(l.startDmDesc),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFriendPickerForDm(context, l, colorScheme,
                      single: true);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Icon(Icons.group_outlined,
                      color: colorScheme.onSecondaryContainer),
                ),
                title: Text(l.createGroupChat,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(l.createGroupChatDesc),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFriendPickerForDm(context, l, colorScheme,
                      single: false);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendPickerForDm(BuildContext context, AppLocalizations l,
      ColorScheme colorScheme,
      {required bool single}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FriendPickerScreen(isSingleSelect: single, l: l),
    ));
  }
}

// ── 1:1 DM 타일 — 상대방 이름 + 프로필 동적 fetch ──────────────────────────────
class _DmTile extends StatefulWidget {
  final Map<String, dynamic> room;
  final ColorScheme colorScheme;
  final String myUid;

  const _DmTile({
    required this.room,
    required this.colorScheme,
    required this.myUid,
  });

  @override
  State<_DmTile> createState() => _DmTileState();
}

class _DmTileState extends State<_DmTile> {
  String _otherName = '';
  String _otherPhoto = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadOtherUser();
  }

  Future<void> _loadOtherUser() async {
    final memberIds =
        List<String>.from(widget.room['member_ids'] as List? ?? []);
    final otherUid = memberIds.firstWhere(
      (id) => id != widget.myUid,
      orElse: () => '',
    );
    if (otherUid.isEmpty) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final data = await _UserCache.get(otherUid);
    if (mounted) {
      setState(() {
        _otherName = data['name'] as String? ?? '';
        _otherPhoto = data['photo'] as String? ?? '';
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final roomId = widget.room['id'] as String;
    final lastMessage = widget.room['last_message'] as String? ?? '';
    final unreadCnt = widget.room['unread_cnt'] as int? ?? 0;
    final hasPhoto = _otherPhoto.isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: cs.tertiaryContainer,
        backgroundImage: hasPhoto ? CachedNetworkImageProvider(_otherPhoto) : null,
        onBackgroundImageError: hasPhoto ? (_, __) {} : null,
        child: hasPhoto
            ? null
            : _loaded
                ? (_otherName.isNotEmpty
                    ? Text(
                        _otherName[0].toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.onTertiaryContainer,
                        ),
                      )
                    : Icon(Icons.person,
                        color: cs.onTertiaryContainer, size: 22))
                : Icon(Icons.person,
                    color: cs.onTertiaryContainer, size: 22),
      ),
      title: Text(
        _loaded
            ? (_otherName.isNotEmpty ? _otherName : '...')
            : '...',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight:
                unreadCnt > 0 ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
      ),
      trailing: unreadCnt > 0
          ? CircleAvatar(
              radius: 12,
              backgroundColor: cs.error,
              child: Text(
                unreadCnt > 99 ? '99+' : unreadCnt.toString(),
                style: TextStyle(
                    color: cs.onError,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatRoomScreen(roomId: roomId))),
    );
  }
}

// ── 단체 채팅 아바타 (겹치기) ─────────────────────────────────────────────────
class _GroupDirectAvatar extends StatefulWidget {
  final String myUid;
  final List<String> memberIds;
  final ColorScheme colorScheme;

  const _GroupDirectAvatar({
    required this.myUid,
    required this.memberIds,
    required this.colorScheme,
  });

  @override
  State<_GroupDirectAvatar> createState() => _GroupDirectAvatarState();
}

class _GroupDirectAvatarState extends State<_GroupDirectAvatar> {
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    final others = widget.memberIds
        .where((id) => id != widget.myUid)
        .take(4)
        .toList();
    _loadMembers(others);
  }

  Future<void> _loadMembers(List<String> uids) async {
    final results =
        await Future.wait(uids.map((uid) => _UserCache.get(uid)));
    if (mounted) setState(() => _members = results);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    if (_members.isEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: cs.surfaceContainerHighest,
        child: Icon(Icons.people, color: cs.onSurface, size: 22),
      );
    }

    final show = _members.take(4).toList();
    const size = 44.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: show.asMap().entries.map((entry) {
          final i = entry.key;
          final data = entry.value;
          final photoUrl = data['photo'] as String? ?? '';
          final name = data['name'] as String? ?? '';
          final hasPhoto = photoUrl.isNotEmpty;

          final positions = [
            const Offset(0, 0),
            const Offset(22, 0),
            const Offset(0, 22),
            const Offset(22, 22),
          ];

          final pos = i < positions.length ? positions[i] : Offset.zero;
          final radius = show.length == 1 ? 22.0 : 13.0;

          return Positioned(
            left: pos.dx,
            top: pos.dy,
            child: CircleAvatar(
              radius: radius,
              backgroundColor: cs.primaryContainer,
              backgroundImage: hasPhoto ? CachedNetworkImageProvider(photoUrl) : null,
              onBackgroundImageError: hasPhoto ? (_, __) {} : null,
              child: hasPhoto
                  ? null
                  : Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: radius * 0.65,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 채팅방 타일 (direct 제외 나머지) ──────────────────────────────────────────
class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> room;
  final ColorScheme colorScheme;
  final bool isInGroup;
  final String myUid;

  const _ChatTile({
    required this.room,
    required this.colorScheme,
    required this.myUid,
    this.isInGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final roomId = room['id'] as String;
    final name = room['name'] as String? ?? roomId;
    final lastMessage = room['last_message'] as String? ?? '';
    final unreadCnt = room['unread_cnt'] as int? ?? 0;
    final type = room['type'] as String? ?? 'direct';
    final memberIds =
        List<String>.from(room['member_ids'] as List? ?? []);

    Widget avatar;
    if (type == 'group_direct') {
      avatar = _GroupDirectAvatar(
        myUid: myUid,
        memberIds: memberIds,
        colorScheme: colorScheme,
      );
    } else if (type == 'group_all') {
      avatar = CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(Icons.group,
            color: colorScheme.onPrimaryContainer, size: 22),
      );
    } else {
      avatar = CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(Icons.chat_bubble,
            color: colorScheme.onSecondaryContainer, size: 20),
      );
    }

    return ListTile(
      contentPadding:
          EdgeInsets.only(left: isInGroup ? 32 : 16, right: 16),
      leading: avatar,
      title: Row(
        children: [
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: unreadCnt > 0
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ),
          if (type == 'group_direct') ...[
            const SizedBox(width: 4),
            Icon(Icons.people,
                size: 12,
                color: colorScheme.onSurface.withOpacity(0.35)),
          ],
        ],
      ),
      subtitle: Text(lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
      trailing: unreadCnt > 0
          ? CircleAvatar(
              radius: 12,
              backgroundColor: colorScheme.error,
              child: Text(
                unreadCnt > 99 ? '99+' : unreadCnt.toString(),
                style: TextStyle(
                    color: colorScheme.onError,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            )
          : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatRoomScreen(roomId: roomId))),
    );
  }
}

// ── 그룹 채팅 섹션 ─────────────────────────────────────────────────────────────
class _GroupChatSection extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> rooms;
  final int totalUnread;
  final ColorScheme colorScheme;
  final String myUid;

  const _GroupChatSection({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.rooms,
    required this.totalUnread,
    required this.colorScheme,
    required this.myUid,
  });

  @override
  State<_GroupChatSection> createState() => _GroupChatSectionState();
}

class _GroupChatSectionState extends State<_GroupChatSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Row(children: [
              GroupAvatar(
                groupId: widget.groupId,
                groupName: widget.groupName,
                radius: 14,
                fallbackIcon: Icons.group,
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.groupName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (!_expanded && widget.totalUnread > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.totalUnread > 99
                        ? '99+'
                        : '${widget.totalUnread}',
                    style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              AnimatedRotation(
                turns: _expanded ? 0.0 : -0.25,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more,
                    size: 18,
                    color: colorScheme.primary.withOpacity(0.6)),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: widget.rooms.map((room) {
              final type = room['type'] as String? ?? '';
              if (type == 'direct') {
                return _DmTile(
                  room: room,
                  colorScheme: colorScheme,
                  myUid: widget.myUid,
                );
              }
              return _ChatTile(
                room: room,
                colorScheme: colorScheme,
                isInGroup: true,
                myUid: widget.myUid,
              );
            }).toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
        ),
        Divider(
            height: 8,
            thickness: 8,
            color: colorScheme.surfaceContainerHighest),
      ],
    );
  }
}

// ── 친구 선택 화면 ─────────────────────────────────────────────────────────────
class _FriendPickerScreen extends StatefulWidget {
  final bool isSingleSelect;
  final AppLocalizations l;

  const _FriendPickerScreen(
      {required this.isSingleSelect, required this.l});

  @override
  State<_FriendPickerScreen> createState() => _FriendPickerScreenState();
}

class _FriendPickerScreenState extends State<_FriendPickerScreen> {
  final Set<String> _selectedUids = {};
  final Map<String, String> _selectedNames = {};
  final TextEditingController _roomNameController =
      TextEditingController();
  bool _creating = false;

  late final Stream<List<Map<String, dynamic>>> _friendsStream;

  @override
  void initState() {
    super.initState();
    _friendsStream = context.read<FriendService>().getFriends();
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selectedUids.isEmpty) return;
    setState(() => _creating = true);

    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    String roomId;

    if (widget.isSingleSelect) {
      final uid = _selectedUids.first;
      final name = _selectedNames[uid] ?? '';
      roomId = await friendService.getOrCreateDmRoom(uid, name,
          myName: myName);
    } else {
      roomId = await friendService.createGroupDirectRoom(
        roomName: _roomNameController.text.trim(),
        memberUids: _selectedUids.toList(),
        memberNames:
            _selectedUids.map((uid) => _selectedNames[uid] ?? '').toList(),
        myName: myName,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomScreen(roomId: roomId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.isSingleSelect ? l.startDm : l.createGroupChat),
        actions: [
          if (_selectedUids.isNotEmpty)
            TextButton(
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.confirm,
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.isSingleSelect) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _roomNameController,
                decoration: InputDecoration(
                  hintText: l.groupChatNameHint,
                  prefixIcon: const Icon(Icons.edit_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_selectedUids.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _selectedUids.map((uid) {
                    final name = _selectedNames[uid] ?? '';
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Chip(
                        label: Text(name,
                            style: const TextStyle(fontSize: 12)),
                        onDeleted: () => setState(() {
                          _selectedUids.remove(uid);
                          _selectedNames.remove(uid);
                        }),
                        deleteIconColor:
                            colorScheme.onSurface.withOpacity(0.5),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Divider(height: 1),
          ],
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _friendsStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                final friends = snap.data ?? [];
                if (friends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 56,
                            color: colorScheme.onSurface.withOpacity(0.2)),
                        const SizedBox(height: 12),
                        Text(l.noFriends,
                            style: TextStyle(
                                color: colorScheme.onSurface
                                    .withOpacity(0.4))),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: friends.length,
                  itemBuilder: (context, i) {
                    final friend = friends[i];
                    final uid = friend['uid'] as String? ??
                        friend['id'] as String? ??
                        '';
                    final name =
                        friend['display_name'] as String? ?? l.unknown;
                    final isSelected = _selectedUids.contains(uid);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? colorScheme.primary
                            : colorScheme.primaryContainer,
                        child: isSelected
                            ? Icon(Icons.check,
                                color: colorScheme.onPrimary, size: 20)
                            : Text(
                                name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold)),
                      ),
                      title: Text(name),
                      onTap: () {
                        if (widget.isSingleSelect) {
                          setState(() {
                            _selectedUids..clear()..add(uid);
                            _selectedNames..clear();
                            _selectedNames[uid] = name;
                          });
                          _create();
                        } else {
                          setState(() {
                            if (isSelected) {
                              _selectedUids.remove(uid);
                              _selectedNames.remove(uid);
                            } else {
                              _selectedUids.add(uid);
                              _selectedNames[uid] = name;
                            }
                          });
                        }
                      },
                    );
                  },
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}