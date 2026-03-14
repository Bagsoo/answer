import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/group_provider.dart';
import '../chat_room_screen.dart';

class ChatsTab extends StatelessWidget {
  final String groupName;

  const ChatsTab({super.key, required this.groupName});

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chat_rooms')
            .where('ref_group_id', isEqualTo: groupId)
            .orderBy('last_time', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];
          if (chats.isEmpty) {
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

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final data = chats[index].data() as Map<String, dynamic>;
              final roomId = chats[index].id;
              final name = data['name'] as String? ?? 'Untitled Chat';
              final type = data['type'] as String? ?? 'group_sub';
              final isGroupAll = type == 'group_all';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isGroupAll
                      ? colorScheme.primaryContainer
                      : colorScheme.secondaryContainer,
                  child: Icon(
                    isGroupAll ? Icons.speaker_notes : Icons.chat,
                    color: isGroupAll
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Text(name,
                    style: TextStyle(
                        fontWeight: isGroupAll
                            ? FontWeight.bold
                            : FontWeight.normal)),
                subtitle: Text(
                  data['last_message'] as String? ?? 'No messages yet...',
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
        groupName: groupName,
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
                        isMe ? '$displayName (${l.me})' : displayName),
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