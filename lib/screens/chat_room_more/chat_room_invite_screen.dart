import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/friend_service.dart';

class ChatRoomInviteScreen extends StatefulWidget {
  final String roomId;
  final String currentUserId;
  final String? refGroupId;

  const ChatRoomInviteScreen({
    super.key,
    required this.roomId,
    required this.currentUserId,
    this.refGroupId,
  });

  @override
  State<ChatRoomInviteScreen> createState() => _ChatRoomInviteScreenState();
}

class _ChatRoomInviteScreenState extends State<ChatRoomInviteScreen> {
  final Set<String> _selectedUids = {};
  final Map<String, String> _selectedNames = {};
  List<Map<String, dynamic>> _candidates = [];
  bool _loading = true;
  bool _inviting = false;

  // 현재 채팅방 타입 (1:1 DM이면 확인 다이얼로그 필요)
  String _roomType = '';

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() => _loading = true);

    final db = FirebaseFirestore.instance;

    // 채팅방 타입 + 기존 멤버 조회
    final results = await Future.wait([
      db.collection('chat_rooms').doc(widget.roomId).get(),
      db.collection('chat_rooms').doc(widget.roomId).collection('room_members').get(),
    ]);

    final roomDoc = results[0] as DocumentSnapshot;
    final roomMembersSnap = results[1] as QuerySnapshot;

    _roomType = (roomDoc.data() as Map<String, dynamic>?)?['type'] as String? ?? '';
    final existingUids = roomMembersSnap.docs.map((d) => d.id).toSet();

    List<Map<String, dynamic>> candidates = [];

    if (widget.refGroupId != null) {
      // 그룹 멤버 중 미참여자 — display_name은 members 문서에 이미 있음
      final groupMembersSnap = await db
          .collection('groups')
          .doc(widget.refGroupId)
          .collection('members')
          .get();

      for (final doc in groupMembersSnap.docs) {
        final uid = doc.id;
        if (existingUids.contains(uid)) continue;
        final name = doc.data()['display_name'] as String? ?? uid.substring(0, 8);
        candidates.add({'uid': uid, 'name': name});
      }
    } else {
      // 친구 목록 중 미참여자
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final friendsSnap = await db
          .collection('users')
          .doc(myUid)
          .collection('friends')
          .get();

      for (final doc in friendsSnap.docs) {
        final uid = doc.id;
        if (existingUids.contains(uid)) continue;
        final name = doc.data()['display_name'] as String? ?? uid.substring(0, 8);
        candidates.add({'uid': uid, 'name': name});
      }
    }

    if (mounted) {
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    }
  }

  // ── 초대 시작: 1:1 DM이면 확인 다이얼로그 먼저 ─────────────────────────────
  Future<void> _onInviteTap() async {
    if (_selectedUids.isEmpty) return;

    if (_roomType == 'direct') {
      // 1:1 DM → 단체톡 전환 안내 다이얼로그
      final l = AppLocalizations.of(context);
      final colorScheme = Theme.of(context).colorScheme;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.convertToGroupChat),
          content: Text(l.convertToGroupChatDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Text(l.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _invite();
  }

  Future<void> _invite() async {
    setState(() => _inviting = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final roomRef = db.collection('chat_rooms').doc(widget.roomId);

      // 1:1 DM이면 type 변경 + dm_key 제거
      if (_roomType == 'direct') {
        batch.update(roomRef, {
          'type': 'group_direct',
          'dm_key': FieldValue.delete(),
        });
      }

      // 멤버 추가
      for (final uid in _selectedUids) {
        batch.update(roomRef, {
          'member_ids': FieldValue.arrayUnion([uid]),
          'unread_counts.$uid': 0,
        });
        batch.set(roomRef.collection('room_members').doc(uid), {
          'uid': uid,
          'display_name': _selectedNames[uid] ?? uid.substring(0, 8),
          'role': 'member',
          'joined_at': FieldValue.serverTimestamp(),
          'last_read_time': FieldValue.serverTimestamp(),
          'unread_cnt': 0,
          'notification_muted': false,
        });

        final name = _selectedNames[uid] ?? 'Unknown';
        batch.set(roomRef.collection('messages').doc(), {
          'is_system': true,
          'text': '$name님이 초대되었습니다.',
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _inviting = false);
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.inviteFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.inviteMembers),
        actions: [
          if (_selectedUids.isNotEmpty)
            TextButton(
              onPressed: _inviting ? null : _onInviteTap,
              child: _inviting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('${l.invite} (${_selectedUids.length})',
                      style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _candidates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_disabled, size: 64,
                          color: colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(l.noInvitableMembers,
                          style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.4))),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 1:1 DM 전환 안내 배너
                    if (_roomType == 'direct')
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: colorScheme.secondary.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              color: colorScheme.secondary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l.convertToGroupChatBanner,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSecondaryContainer)),
                          ),
                        ]),
                      ),

                    // 선택 카운트
                    if (_selectedUids.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        color: colorScheme.primaryContainer.withOpacity(0.4),
                        child: Text(
                          '${_selectedUids.length}${l.selectedCount}',
                          style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),

                    Expanded(
                      child: ListView.separated(
                        itemCount: _candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = _candidates[index];
                          final uid = candidate['uid'] as String;
                          final name = candidate['name'] as String;
                          final isSelected = _selectedUids.contains(uid);

                          return ListTile(
                            onTap: () => setState(() {
                              if (isSelected) {
                                _selectedUids.remove(uid);
                                _selectedNames.remove(uid);
                              } else {
                                _selectedUids.add(uid);
                                _selectedNames[uid] = name;
                              }
                            }),
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              child: isSelected
                                  ? Icon(Icons.check,
                                      color: colorScheme.onPrimary, size: 20)
                                  : Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface)),
                            ),
                            title: Text(name),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: colorScheme.primary)
                                : Icon(Icons.circle_outlined,
                                    color: colorScheme.onSurface.withOpacity(0.3)),
                          );
                        },
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                      ),
                    ),
                  ],
                ),

      bottomNavigationBar: _selectedUids.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  onPressed: _inviting ? null : _onInviteTap,
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: _inviting
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('${l.invite} (${_selectedUids.length})'),
                ),
              ),
            )
          : null,
    );
  }
}