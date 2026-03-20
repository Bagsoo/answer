import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../services/memo_service.dart';
import '../../widgets/group_settings/group_avatar_widget.dart';
import 'memo_tile.dart';

// ── 직접 작성 메모 섹션 ────────────────────────────────────────────────────────
class DirectMemoSection extends StatefulWidget {
  final List<QueryDocumentSnapshot> memos;
  final MemoService service;
  final SharedPreferences prefs;

  const DirectMemoSection({
    super.key,
    required this.memos,
    required this.service,
    required this.prefs,
  });

  @override
  State<DirectMemoSection> createState() => _DirectMemoSectionState();
}

class _DirectMemoSectionState extends State<DirectMemoSection> {
  static const _prefKey = 'memo_expanded_direct';
  late bool _expanded;

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
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
              child: Row(children: [
                Icon(Icons.edit_note_outlined,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l.memoSourceDirect,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface.withOpacity(0.7)))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${widget.memos.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary)),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...widget.memos.map((d) => MemoTile(
                        memoId: d.id,
                        data: d.data() as Map<String, dynamic>,
                        service: widget.service,
                      )),
                  const Divider(height: 1),
                ]),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
          ),
        ]);
  }
}

// ── 그룹별 메모 섹션 ───────────────────────────────────────────────────────────
class GroupMemoSection extends StatefulWidget {
  final GroupMemoGroup group;
  final MemoService service;
  final SharedPreferences prefs;

  const GroupMemoSection({
    super.key,
    required this.group,
    required this.service,
    required this.prefs,
  });

  @override
  State<GroupMemoSection> createState() => _GroupMemoSectionState();
}

class _GroupMemoSectionState extends State<GroupMemoSection> {
  late bool _expanded;

  String get _prefKey => 'memo_expanded_${widget.group.groupId}';

  @override
  void initState() {
    super.initState();
    _expanded = widget.prefs.getBool(_prefKey) ?? true;
  }

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    await widget.prefs.setBool(_prefKey, next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final group = widget.group;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleExpanded,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
              child: Row(children: [
                GroupAvatar(
                  groupId: group.groupId,
                  groupName: group.groupName,
                  radius: 12,
                  fallbackIcon: Icons.group_outlined,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(group.groupName,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface.withOpacity(0.75)))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: colorScheme.secondary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${group.memos.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.secondary)),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ]),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...group.memos.map((entry) => MemoTile(
                        memoId: entry.id,
                        data: entry.data,
                        service: widget.service,
                      )),
                  const Divider(height: 1),
                ]),
            secondChild: const SizedBox.shrink(),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
          ),
        ]);
  }
}

// ── 데이터 모델 ───────────────────────────────────────────────────────────────
class MemoEntry {
  final String id;
  final Map<String, dynamic> data;
  MemoEntry({required this.id, required this.data});
}

class GroupMemoGroup {
  final String groupId;
  final String groupName;
  final List<MemoEntry> memos;
  GroupMemoGroup(
      {required this.groupId,
      required this.groupName,
      required this.memos});
}