import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  const GroupChatSection({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.rooms,
    required this.totalUnread,
    required this.colorScheme,
    required this.myUid,
    required this.prefs,
  });

  @override
  State<GroupChatSection> createState() => _GroupChatSectionState();
}

class _GroupChatSectionState extends State<GroupChatSection> {
  late bool _expanded;

  String get _prefKey => 'chat_expanded_${widget.groupId}';

  @override
  void initState() {
    super.initState();
    // prefs가 이미 로드되어 있으므로 동기적으로 읽기 → 애니메이션 없음
    _expanded = widget.prefs.getBool(_prefKey) ?? true;
  }

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    await widget.prefs.setBool(_prefKey, next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _toggleExpanded,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.totalUnread > 99 ? '99+' : '${widget.totalUnread}',
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
                    size: 18, color: colorScheme.primary.withOpacity(0.6)),
              ),
            ]),
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
                );
              }
              return ChatTile(
                room: room,
                colorScheme: colorScheme,
                isInGroup: true,
                myUid: widget.myUid,
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
            color: colorScheme.surfaceContainerHighest),
      ],
    );
  }
}