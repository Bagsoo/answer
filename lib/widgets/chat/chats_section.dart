import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/local_preferences_service.dart';
import '../../widgets/group_settings/group_avatar_widget.dart';
import 'chat_tiles.dart';

class GroupChatSection extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> rooms;
  final int totalUnread;
  final ColorScheme colorScheme;
  final String myUid;
  final SharedPreferences prefs;
  final void Function(String roomId)? onRoomSelected;
  const GroupChatSection({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.rooms,
    required this.totalUnread,
    required this.colorScheme,
    required this.myUid,
    required this.prefs,
    this.onRoomSelected,
  });

  @override
  State<GroupChatSection> createState() => _GroupChatSectionState();
}

class _GroupChatSectionState extends State<GroupChatSection> {
  late bool _expanded;
  late int _cachedUnread;

  String get _prefKey => 'chat_expanded_${widget.groupId}';
  String get _unreadPrefKey =>
      LocalPreferencesService.groupChatUnreadKey(widget.myUid, widget.groupId);

  @override
  void initState() {
    super.initState();
    _expanded = widget.prefs.getBool(_prefKey) ?? true;
    _cachedUnread = widget.prefs.getInt(_unreadPrefKey) ?? 0;
  }

  @override
  void didUpdateWidget(covariant GroupChatSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.totalUnread != oldWidget.totalUnread) {
      _cachedUnread = widget.totalUnread;
    }
  }

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    await widget.prefs.setBool(_prefKey, next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final unread = widget.totalUnread > 0 ? widget.totalUnread : _cachedUnread;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Row(
              children: [
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
                if (unread > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: colorScheme.primary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: widget.rooms.map<Widget>((room) {
              final type = room['type'] as String? ?? '';
              if (type == 'direct') {
                return DmTile(
                  room: room,
                  colorScheme: colorScheme,
                  myUid: widget.myUid,
                  onRoomSelected: widget.onRoomSelected,
                );
              }
              return ChatTile(
                room: room,
                colorScheme: colorScheme,
                isInGroup: true,
                myUid: widget.myUid,
                onRoomSelected: widget.onRoomSelected,
              );
            }).toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
        ),
        Divider(
          height: 8,
          thickness: 8,
          color: colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}

class PrivateChatSection extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> rooms;
  final int totalUnread;
  final ColorScheme colorScheme;
  final String myUid;
  final SharedPreferences prefs;
  final void Function(String roomId)? onRoomSelected;

  const PrivateChatSection({
    super.key,
    required this.title,
    required this.rooms,
    required this.totalUnread,
    required this.colorScheme,
    required this.myUid,
    required this.prefs,
    this.onRoomSelected,
  });

  @override
  State<PrivateChatSection> createState() => _PrivateChatSectionState();
}

class _PrivateChatSectionState extends State<PrivateChatSection> {
  late bool _expanded;
  late int _cachedUnread;

  String get _prefKey => 'chat_expanded_private';
  String get _unreadPrefKey =>
      LocalPreferencesService.privateChatUnreadKey(widget.myUid);

  @override
  void initState() {
    super.initState();
    _expanded = widget.prefs.getBool(_prefKey) ?? true;
    _cachedUnread = widget.prefs.getInt(_unreadPrefKey) ?? 0;
  }

  @override
  void didUpdateWidget(covariant PrivateChatSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.totalUnread != oldWidget.totalUnread) {
      _cachedUnread = widget.totalUnread;
    }
  }

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    await widget.prefs.setBool(_prefKey, next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final unread = widget.totalUnread > 0 ? widget.totalUnread : _cachedUnread;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (unread > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: colorScheme.primary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(
            children: widget.rooms.map<Widget>((room) {
              final type = room['type'] as String? ?? '';
              if (type == 'direct') {
                return DmTile(
                  room: room,
                  colorScheme: colorScheme,
                  myUid: widget.myUid,
                  onRoomSelected: widget.onRoomSelected,
                );
              }
              return ChatTile(
                room: room,
                colorScheme: colorScheme,
                myUid: widget.myUid,
                onRoomSelected: widget.onRoomSelected,
              );
            }).toList(),
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 220),
        ),
        Divider(
          height: 8,
          thickness: 8,
          color: colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}
