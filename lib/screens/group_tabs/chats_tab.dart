import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../../services/chat_service.dart';
import '../../widgets/chat/chat_tiles.dart';
import '../chat_room_screen.dart';

class ChatsTab extends StatefulWidget {
  final String groupName;

  const ChatsTab({super.key, required this.groupName});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final TextEditingController _filterController = TextEditingController();
  bool _isFiltering = false;
  String _filterQuery = '';

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    // GroupProvider에서 groupId, 권한 읽기
    final gp = context.watch<GroupProvider>();
    final groupId = gp.groupId;
    final canCreateSubChat = gp.canCreateSubChat;

    return Scaffold(
      // FutureBuilder로 권한 확인하던 부분 → GroupProvider로 대체
      floatingActionButton: canCreateSubChat
          ? FloatingActionButton(
              onPressed: () =>
                  _showCreateSubChatSheet(context, l, colorScheme, groupId),
              mini: true,
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: context.read<ChatService>().getChatRooms(
              refGroupId: groupId,
            ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('ChatsTab Stream Error: \${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('에러 발생: \${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allChats = snapshot.data ?? [];
          final chats = allChats
              .where((room) => _matchesRoom(room, _filterQuery))
              .toList();
          if (allChats.isEmpty) {
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
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isFiltering = !_isFiltering;
                          if (!_isFiltering) {
                            _filterController.clear();
                            _filterQuery = '';
                          }
                        });
                      },
                      child: Icon(
                        _isFiltering ? Icons.search_off : Icons.search,
                        size: 20,
                        color: _isFiltering
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isFiltering)
                      Expanded(
                        child: TextField(
                          controller: _filterController,
                          autofocus: true,
                          onChanged: (v) =>
                              setState(() => _filterQuery = v.trim()),
                          decoration: InputDecoration(
                            hintText: l.searchPlaceholder,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _filterQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => setState(() {
                                      _filterController.clear();
                                      _filterQuery = '';
                                    }),
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? Center(
                        child: Text(
                          l.noSearchResults,
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final data = chats[index];
                          final roomId = data['id'] as String;
                          final name =
                              data['name'] as String? ?? 'Untitled Chat';
                          final type = data['type'] as String? ?? 'group_sub';
                          final isGroupAll = type == 'group_all';
                          final groupProfileImage =
                              data['group_profile_image'] as String? ?? '';
                          final memberIds =
                              List<String>.from(data['member_ids'] as List? ?? []);

                          Widget avatar;
                          if (isGroupAll) {
                            final hasGroupProfileImage =
                                groupProfileImage.isNotEmpty;
                            avatar = CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage: hasGroupProfileImage
                                  ? CachedNetworkImageProvider(groupProfileImage)
                                  : null,
                              onBackgroundImageError:
                                  hasGroupProfileImage ? (_, __) {} : null,
                              child: hasGroupProfileImage
                                  ? null
                                  : Icon(
                                      Icons.group,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                            );
                          } else {
                            avatar = GroupDirectAvatar(
                              myUid: currentUserId,
                              memberIds: memberIds,
                              colorScheme: colorScheme,
                            );
                          }

                          return ListTile(
                            leading: avatar,
                            title: Text(name,
                                style: TextStyle(
                                    fontWeight: isGroupAll
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            subtitle: Text(
                              data['last_message'] as String? ??
                                  'No messages yet...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: colorScheme.onSurface.withOpacity(0.4)),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatRoomScreen(roomId: roomId),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateSubChatSheet(BuildContext context, AppLocalizations l,
      ColorScheme colorScheme, String groupId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateSubChatSheet(
        groupId: groupId,
        groupName: widget.groupName,
        currentUserId: currentUserId,
        l: l,
        colorScheme: colorScheme,
      ),
    );
  }
}

// ── 서브 채팅방 생성 시트 ──────────────────────────────────────────────────────
class _CreateSubChatSheet extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;
  final AppLocalizations l;
  final ColorScheme colorScheme;

  const _CreateSubChatSheet({
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
    required this.l,
    required this.colorScheme,
  });

  @override
  State<_CreateSubChatSheet> createState() => _CreateSubChatSheetState();
}

class _CreateSubChatSheetState extends State<_CreateSubChatSheet> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedUids = {};
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _selectedUids.add(widget.currentUserId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final snap = await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('members')
        .get();

    setState(() {
      _members = snap.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
      _loading = false;
    });
  }

  Future<void> _createSubChat() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedUids.isEmpty) return;

    setState(() => _creating = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final chatDoc = db.collection('chat_rooms').doc();
      final selectedUidList = _selectedUids.toList();

      batch.set(chatDoc, {
        'type': 'group_sub',
        'ref_group_id': widget.groupId,
        'group_name': widget.groupName,
        'name': name,
        'member_ids': selectedUidList,
        'last_message': '',
        'last_time': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
        'unread_counts': {for (final uid in selectedUidList) uid: 0},
      });

      for (final uid in selectedUidList) {
        final memberData = _members.firstWhere(
          (m) => m['uid'] == uid,
          orElse: () => {'display_name': uid.substring(0, 8)},
        );
        final displayName =
            memberData['display_name'] as String? ?? uid.substring(0, 8);
        batch.set(
          chatDoc.collection('room_members').doc(uid),
          {
            'uid': uid,
            'display_name': displayName,
            'role': uid == widget.currentUserId ? 'owner' : 'member',
            'joined_at': FieldValue.serverTimestamp(),
            'last_read_time': FieldValue.serverTimestamp(),
            'unread_cnt': 0,
          },
        );
      }

      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.l.createSubChatFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final l = widget.l;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(l.createSubChat,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l.subChatNameHint,
                prefixIcon: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(l.selectMembers,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface.withOpacity(0.5),
                    letterSpacing: 0.5)),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _members.length,
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final uid = member['uid'] as String;
                  final displayName =
                      member['display_name'] as String? ?? l.unknown;
                  final isMe = uid == widget.currentUserId;
                  final isSelected = _selectedUids.contains(uid);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: isMe
                        ? null
                        : (val) {
                            setState(() {
                              if (val == true) {
                                _selectedUids.add(uid);
                              } else {
                                _selectedUids.remove(uid);
                              }
                            });
                          },
                    secondary: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                        isMe ? '$displayName (\${l.me})' : displayName),
                    subtitle:
                        Text(member['role'] as String? ?? 'member'),
                    activeColor: colorScheme.primary,
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _creating ? null : _createSubChat,
                child: _creating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.create),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
