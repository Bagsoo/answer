import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/chat_room_screen.dart';
import '../../utils/user_cache.dart';

// ── 유저 프로필 메모리 캐시 (Micro-batching / DataLoader) ────────────────────────

String _localizedLastMessage(BuildContext context, String lastMessage) {
  final l = AppLocalizations.of(context);
  switch (lastMessage) {
    case 'current':
      return l.locationCurrent;
    case 'destination':
      return l.locationDestination;
    case 'file':
      return l.attachFile;
    case 'contact':
      return l.attachContact;
    case 'audio':
      return l.attachVoice;
    default:
      return lastMessage;
  }
}

class ParticipantCountBadge extends StatelessWidget {
  final int count;
  final ColorScheme colorScheme;

  const ParticipantCountBadge({
    super.key,
    required this.count,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final cs = colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline,
              size: 12, color: cs.onSurface.withOpacity(0.55)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.65),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 1:1 DM 타일 ───────────────────────────────────────────────────────────────
class DmTile extends StatefulWidget {
  final Map<String, dynamic> room;
  final ColorScheme colorScheme;
  final String myUid;
  final void Function(String roomId)? onRoomSelected;

  const DmTile({
    super.key,
    required this.room,
    required this.colorScheme,
    required this.myUid,
    this.onRoomSelected,
  });

  @override
  State<DmTile> createState() => _DmTileState();
}

class _DmTileState extends State<DmTile> {
  String _otherName = '';
  String _otherPhoto = '';
  bool _otherDeleted = false;
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
    final data = await UserCache.get(otherUid);
    if (mounted) {
      setState(() {
        _otherName = data['name'] as String? ?? '';
        _otherPhoto = data['photo'] as String? ?? '';
        _otherDeleted = data['is_deleted'] == true;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final l = AppLocalizations.of(context);
    final roomId = widget.room['id'] as String;
    final lastMessage = _localizedLastMessage(
      context,
      widget.room['last_message'] as String? ?? '',
    );
    final unreadCnt = widget.room['unread_cnt'] as int? ?? 0;
    final hasPhoto = _otherPhoto.isNotEmpty && !_otherDeleted;
    final displayName = _otherDeleted
        ? l.deletedUser
        : (_otherName.isNotEmpty ? _otherName : '...');

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: cs.tertiaryContainer,
        backgroundImage:
            hasPhoto ? CachedNetworkImageProvider(_otherPhoto) : null,
        onBackgroundImageError: hasPhoto ? (_, __) {} : null,
        child: hasPhoto
            ? null
            : _loaded
                ? (_otherDeleted
                    ? Icon(Icons.person_off_outlined,
                        color: cs.onTertiaryContainer, size: 22)
                    : _otherName.isNotEmpty
                    ? Text(_otherName[0].toUpperCase(),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onTertiaryContainer))
                    : Icon(Icons.person, color: cs.onTertiaryContainer, size: 22))
                : Icon(Icons.person, color: cs.onTertiaryContainer, size: 22),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _loaded ? displayName : '...',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: unreadCnt > 0 ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          if ((widget.room['muted_uids'] as List<dynamic>? ?? []).contains(widget.myUid)) ...[
            const SizedBox(width: 4),
            Icon(Icons.notifications_off, size: 14, color: cs.onSurface.withOpacity(0.4)),
          ],
        ],
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
      onTap: () {
        if (widget.onRoomSelected != null) {
          widget.onRoomSelected!(roomId); // 데스크톱
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatRoomScreen(roomId: roomId)),
          );
        }
      },
    );
  }
}

// ── 단체 채팅 아바타 (겹치기) ─────────────────────────────────────────────────
class GroupDirectAvatar extends StatefulWidget {
  final String myUid;
  final List<String> memberIds;
  final ColorScheme colorScheme;

  const GroupDirectAvatar({
    super.key,
    required this.myUid,
    required this.memberIds,
    required this.colorScheme,
  });

  @override
  State<GroupDirectAvatar> createState() => _GroupDirectAvatarState();
}

class _GroupDirectAvatarState extends State<GroupDirectAvatar> {
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
    final results = await Future.wait(uids.map((uid) => UserCache.get(uid)));
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
          final isDeleted = data['is_deleted'] == true;
          final hasPhoto = photoUrl.isNotEmpty && !isDeleted;

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
              backgroundImage:
                  hasPhoto ? CachedNetworkImageProvider(photoUrl) : null,
              onBackgroundImageError: hasPhoto ? (_, __) {} : null,
              child: hasPhoto
                  ? null
                  : isDeleted
                      ? Icon(
                          Icons.person_off_outlined,
                          size: radius * 0.95,
                          color: cs.onPrimaryContainer,
                        )
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

// ── 채팅방 타일 (direct 제외) ──────────────────────────────────────────────────
class ChatTile extends StatelessWidget {
  final Map<String, dynamic> room;
  final ColorScheme colorScheme;
  final bool isInGroup;
  final String myUid;
  final void Function(String roomId)? onRoomSelected;

  const ChatTile({
    super.key,
    required this.room,
    required this.colorScheme,
    required this.myUid,
    this.isInGroup = false,
    this.onRoomSelected,
  });

  @override
  Widget build(BuildContext context) {
    final roomId = room['id'] as String;
    final name = room['name'] as String? ?? roomId;
    final lastMessage = _localizedLastMessage(
      context,
      room['last_message'] as String? ?? '',
    );
    final unreadCnt = room['unread_cnt'] as int? ?? 0;
    final type = room['type'] as String? ?? 'direct';
    final memberIds = List<String>.from(room['member_ids'] as List? ?? []);
    final groupProfileImage = room['group_profile_image'] as String? ?? '';
    final hasGroupProfileImage = groupProfileImage.isNotEmpty;
    final isMuted =
        (room['muted_uids'] as List<dynamic>? ?? []).contains(myUid);
    final memberCount = (room['member_count'] as int?) ?? memberIds.length;

    Widget avatar;
    if (type == 'group_direct' || type == 'group_sub') {
      avatar = GroupDirectAvatar(
        myUid: myUid,
        memberIds: memberIds,
        colorScheme: colorScheme,
      );
    } else if (type == 'group_all') {
      avatar = CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: hasGroupProfileImage
            ? CachedNetworkImageProvider(groupProfileImage)
            : null,
        onBackgroundImageError: hasGroupProfileImage ? (_, __) {} : null,
        child: hasGroupProfileImage
            ? null
            : Icon(
                Icons.group,
                color: colorScheme.onPrimaryContainer,
                size: 22,
              ),
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
      contentPadding: EdgeInsets.only(left: isInGroup ? 32 : 16, right: 16),
      leading: avatar,
      title: Row(
        children: [
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight:
                        unreadCnt > 0 ? FontWeight.bold : FontWeight.normal)),
          ),
          if (type != 'direct') ...[
            const SizedBox(width: 4),
            ParticipantCountBadge(count: memberCount, colorScheme: colorScheme),
          ],
          if (isMuted) ...[
            const SizedBox(width: 4),
            Icon(Icons.notifications_off,
                size: 14, color: colorScheme.onSurface.withOpacity(0.4)),
          ],
        ],
      ),
      subtitle: Text(lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
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
      onTap: () {
        if (onRoomSelected != null) {
          onRoomSelected!(roomId); // 데스크톱
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ChatRoomScreen(roomId: roomId)),
          );
        }
      },
    );
  }
}
