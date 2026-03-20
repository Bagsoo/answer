import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/memo_service.dart';
import '../widgets/memo/memo_form_sheet.dart';
import '../widgets/memo/memo_section.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _prefs = prefs);
  }

  void _showNewMemoSheet(BuildContext context, MemoService service) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MemoFormSheet(
        memoId: null,
        initialContent: '',
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final service = context.read<MemoService>();

    // prefs 로드 전에는 로딩 표시
    if (_prefs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: service.memosStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noMemos,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          // 직접 작성 메모
          final directMemos = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['source'] as String? ?? 'direct') == 'direct';
          }).toList();

          // 그룹별 메모 그루핑
          final Map<String, GroupMemoGroup> groupMap = {};
          for (final d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final source = data['source'] as String? ?? 'direct';
            if (source == 'direct') continue;
            final groupId = data['group_id'] as String? ?? '__unknown__';
            final groupName = data['group_name'] as String? ?? l.unknown;
            groupMap.putIfAbsent(
              groupId,
              () => GroupMemoGroup(
                  groupId: groupId, groupName: groupName, memos: []),
            );
            groupMap[groupId]!.memos.add(MemoEntry(id: d.id, data: data));
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              if (directMemos.isNotEmpty)
                DirectMemoSection(
                  memos: directMemos,
                  service: service,
                  prefs: _prefs!,
                ),
              ...groupMap.values.map((group) => GroupMemoSection(
                    group: group,
                    service: service,
                    prefs: _prefs!,
                  )),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewMemoSheet(context, service),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}