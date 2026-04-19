import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../services/friend_service.dart';
import '../services/local_preferences_service.dart';
import '../providers/user_provider.dart';
import '../providers/chat_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/chat/chat_tiles.dart';
import '../widgets/chat/chats_section.dart';
import 'chat_room_screen.dart';
import '../utils/ad_interleaver.dart';

class ChatListScreen extends StatefulWidget {
  final void Function(String roomId)? onRoomSelected;
  final String filterQuery;
  const ChatListScreen({super.key, this.onRoomSelected, this.filterQuery = ''});  

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {  

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        context.read<ChatProvider>().attachGlobalRoomsStreamWhenReady();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  DateTime? _latestTime(List<Map<String, dynamic>> rooms) {
    for (final room in rooms) {
      final t = room['last_time'];
      if (t != null) return (t as dynamic).toDate();
    }
    return null;
  }

  Future<void> _persistSectionUnread({
    required int privateUnread,
    required Map<String, int> groupUnread,
  }) async {
    await LocalPreferencesService.setInt(
      LocalPreferencesService.privateChatUnreadKey(_myUid),
      privateUnread,
    );
    for (final entry in groupUnread.entries) {
      await LocalPreferencesService.setInt(
        LocalPreferencesService.groupChatUnreadKey(_myUid, entry.key),
        entry.value,
      );
    }
  }

  bool _matchesRoom(Map<String, dynamic> room, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    final roomName = (room['name'] as String? ?? '').toLowerCase();
    final memberNames = List<String>.from(room['search_member_names'] as List? ?? [])
        .map((name) => name.toLowerCase())
        .toList();

    if (roomName.contains(normalized)) return true;
    return memberNames.any((name) => name.contains(normalized));
  }

  void _showNewChatSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
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
                  _showFriendPicker(context, single: true);
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
                  _showFriendPicker(context, single: false);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendPicker(BuildContext context, {required bool single}) {
    final l = AppLocalizations.of(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FriendPickerScreen(isSingleSelect: single, l: l),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final prefs = context.read<SharedPreferences>();
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatSheet(context),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Builder(
        builder: (context) {
          if (!chatProvider.isRoomsLoaded && chatProvider.chatRooms.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRooms = chatProvider.chatRooms;
          final rooms = allRooms
              .where((room) => _matchesRoom(room, widget.filterQuery))
              .toList();

          if (allRooms.isEmpty) {
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
                    onPressed: () => _showNewChatSheet(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l.startNewChat),
                  ),
                ],
              ),
            );
          }

          final dmRooms =
              rooms.where((r) => r['ref_group_id'] == null).toList();
          final privateUnread = dmRooms.fold<int>(
            0,
            (sum, room) => sum + ((room['unread_cnt'] as int?) ?? 0),
          );

          final Map<String, List<Map<String, dynamic>>> groupedRooms = {};
          for (final room in rooms.where((r) => r['ref_group_id'] != null)) {
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
          final groupUnread = <String, int>{
            for (final entry in sortedGroups)
              entry.key: entry.value.fold<int>(
                0,
                (sum, room) => sum + ((room['unread_cnt'] as int?) ?? 0),
              ),
          };
          _persistSectionUnread(
            privateUnread: privateUnread,
            groupUnread: groupUnread,
          );
          // 1) 그룹 위젯 리스트
          final groupWidgets = sortedGroups.map<Widget>((entry) {
            final roomsInGroup = entry.value;
            final groupName = roomsInGroup.first['group_name'] as String? ?? l.unknown;
            final groupId = entry.key;
            final totalUnread = groupUnread[groupId] ?? 0;

            return GroupChatSection(
              key: ValueKey(groupId),
              groupId: groupId,
              groupName: groupName,
              rooms: roomsInGroup,
              totalUnread: totalUnread,
              colorScheme: colorScheme,
              myUid: _myUid,
              prefs: prefs,
              onRoomSelected: widget.onRoomSelected,
            );
          }).toList();

          final privateSection = dmRooms.isEmpty
              ? const <Widget>[]
              : [
                  PrivateChatSection(
                    key: const ValueKey('private_section'),
                    title: l.privateChats,
                    rooms: dmRooms,
                    totalUnread: privateUnread,
                    colorScheme: colorScheme,
                    myUid: _myUid,
                    prefs: prefs,
                    onRoomSelected: widget.onRoomSelected,
                  ),
                ];

          return ListView(
            children: [
              ...privateSection,
              ...interleaveAds(groupWidgets, keyPrefix: 'group_ad'),
            ],
          );
        },
      ),
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
  final TextEditingController _roomNameController = TextEditingController();
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
        title:
            Text(widget.isSingleSelect ? l.startDm : l.createGroupChat),
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
                      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                  return const Center(child: CircularProgressIndicator());
                }
                final friends = snap.data ?? [];
                if (friends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 56,
                            color:
                                colorScheme.onSurface.withOpacity(0.2)),
                        const SizedBox(height: 12),
                        Text(l.noFriends,
                            style: TextStyle(
                                color:
                                    colorScheme.onSurface.withOpacity(0.4))),
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
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
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
