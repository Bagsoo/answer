import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/memo_service.dart';
import '../widgets/memo/memo_form_sheet.dart';
import '../widgets/memo/memo_section.dart';

class MemoScreen extends StatefulWidget {
  final bool isDesktopMode;
  final String? selectedMemoId;
  final void Function(String? memoId, Map<String, dynamic>? data)? onMemoSelected;
  final VoidCallback? onCreateRequested;

  const MemoScreen({
    super.key,
    this.isDesktopMode = false,
    this.selectedMemoId,
    this.onMemoSelected,
    this.onCreateRequested,
  });

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  static const _cacheKey = 'memo_list_cache';

  SharedPreferences? _prefs;
  List<_CachedMemo> _cachedMemos = [];
  bool _cacheLoaded = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 캐시 즉시 로드 ────────────────────────────────────────────────────────
  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);

    List<_CachedMemo> cached = [];
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        cached = list
            .map((e) => _CachedMemo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _prefs = prefs;
        _cachedMemos = cached;
        _cacheLoaded = true;
      });
    }
  }

  // ── Firebase 응답으로 캐시 갱신 ──────────────────────────────────────────
  Future<void> _saveCache(List<QueryDocumentSnapshot> docs) async {
    if (_prefs == null) return;
    try {
      final slim = docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        // 타일에 필요한 필드만 저장 (용량 절약)
        return {
          'id': d.id,
          'title': data['title'] ?? '',
          'content': data['content'] ?? '',
          'source': data['source'] ?? 'direct',
          'blocks': _slimBlocks(data['blocks'] as List?),
          'media_types': data['media_types'] ?? [],
          'attachments': _slimAttachments(data['attachments'] as List?),
          'group_id': data['group_id'] ?? '',
          'group_name': data['group_name'] ?? '',
          'room_name': data['room_name'] ?? '',
          'board_name': data['board_name'] ?? '',
          'post_title': data['post_title'] ?? '',
          'sender_name': data['sender_name'] ?? '',
          'author_name': data['author_name'] ?? '',
          'updated_at': (data['updated_at'] as Timestamp?)?.millisecondsSinceEpoch,
        };
      }).toList();
      await _prefs!.setString(_cacheKey, jsonEncode(slim));
    } catch (_) {}
  }

  // 블록에서 미리보기에 필요한 것만 (url, thumbnail_url만)
  List _slimBlocks(List? blocks) {
    if (blocks == null) return [];
    return blocks.map((b) {
      final bMap = Map<String, dynamic>.from(b as Map);
      final type = bMap['type'] as String?;
      if (type == 'image' || type == 'video' || type == 'drawing') {
        final d = Map<String, dynamic>.from(bMap['data'] as Map? ?? {});
        return {
          'type': type,
          'data': {
            'url': d['url'] ?? '',
            'thumbnail_url': d['thumbnail_url'] ?? '',
            'name': d['name'] ?? '',
          }
        };
      }
      return {'type': type, 'data': {}};
    }).toList();
  }

  // 첨부파일에서 미리보기에 필요한 것만
  List _slimAttachments(List? attachments) {
    if (attachments == null) return [];
    return attachments.map((a) {
      final aMap = Map<String, dynamic>.from(a as Map);
      return {
        'type': aMap['type'] ?? 'file',
        'url': aMap['url'] ?? '',
        'thumbnail_url': aMap['thumbnail_url'] ?? '',
        'name': aMap['name'] ?? '',
        'size': aMap['size'] ?? 0,
        'mime_type': aMap['mime_type'] ?? '',
      };
    }).toList();
  }

  void _showNewMemoSheet(BuildContext context, MemoService service) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MemoFormSheet(
        memoId: null,
        initialTitle: '',
        initialContent: '',
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final service = context.read<MemoService>();

    if (!_cacheLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: '${l.search} (제목, 내용)',
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.5)),
                prefixIcon: Icon(Icons.search, color: cs.onSurface.withOpacity(0.5)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: service.memosStream(),
              builder: (context, snap) {
                final docs = snap.data?.docs;

                // Firebase 응답 오면 캐시 갱신
                if (docs != null) {
                  _saveCache(docs);
                }

                // 표시할 데이터 결정: Firebase 우선, 없으면 캐시
                final List<_MemoItem> items;
                if (docs != null) {
                  items = docs.map((d) => _MemoItem.fromFirestore(d)).toList();
                } else if (_cachedMemos.isNotEmpty) {
                  items = _cachedMemos.map((c) => _MemoItem.fromCache(c)).toList();
                } else if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else {
                  items = [];
                }

                final query = _searchQuery.toLowerCase().trim();
                final filteredItems = query.isEmpty 
                    ? items 
                    : items.where((i) {
                        final title = (i.data['title']?.toString() ?? '').toLowerCase();
                        final content = (i.data['content']?.toString() ?? '').toLowerCase();
                        return title.contains(query) || content.contains(query);
                      }).toList();

                if (filteredItems.isEmpty) {
                  if (widget.isDesktopMode && widget.onMemoSelected != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onMemoSelected!(null, null);
                    });
                  }
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(query.isEmpty ? Icons.note_outlined : Icons.search_off,
                            size: 64, color: cs.onSurface.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text(query.isEmpty ? l.noMemos : l.noSearchResults,
                            style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
                      ],
                    ),
                  );
                }

                // 직접 메모 / 그룹 메모 분리
                final directItems = filteredItems
              .where((i) => i.source == 'direct')
              .toList();

                if (widget.isDesktopMode &&
                    widget.onMemoSelected != null &&
                    !filteredItems.any((i) => i.id == widget.selectedMemoId)) {
                  final target = filteredItems.first;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onMemoSelected!(target.id, target.data);
                  });
                }

                final Map<String, GroupMemoGroup> groupMap = {};
                for (final item in filteredItems) {
                  if (item.source == 'direct') continue;
            final groupId = item.groupId.isNotEmpty ? item.groupId : '__unknown__';
            final groupName = item.groupName.isNotEmpty ? item.groupName : l.unknown;
            groupMap.putIfAbsent(
              groupId,
              () => GroupMemoGroup(groupId: groupId, groupName: groupName, memos: []),
            );
            groupMap[groupId]!.memos.add(MemoEntry(id: item.id, data: item.data));
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              if (directItems.isNotEmpty)
                DirectMemoSection(
                  memos: directItems
                      .map((i) => _FakeDoc(id: i.id, data: i.data))
                      .toList(),
                  service: service,
                  prefs: _prefs!,
                  selectedMemoId: widget.selectedMemoId,
                  onMemoTap: widget.isDesktopMode
                      ? (memoId, data) =>
                          widget.onMemoSelected?.call(memoId, data)
                      : null,
                ),
              ...groupMap.values.map((group) => GroupMemoSection(
                    group: group,
                    service: service,
                    prefs: _prefs!,
                    selectedMemoId: widget.selectedMemoId,
                    onMemoTap: widget.isDesktopMode
                        ? (memoId, data) =>
                            widget.onMemoSelected?.call(memoId, data)
                        : null,
                  )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (widget.isDesktopMode && widget.onCreateRequested != null) {
            widget.onCreateRequested!();
          } else {
            _showNewMemoSheet(context, service);
          }
        },
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

// ── 내부 데이터 모델 ──────────────────────────────────────────────────────────
class _MemoItem {
  final String id;
  final Map<String, dynamic> data;
  final String source;
  final String groupId;
  final String groupName;

  _MemoItem({
    required this.id,
    required this.data,
    required this.source,
    required this.groupId,
    required this.groupName,
  });

  factory _MemoItem.fromFirestore(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _MemoItem(
      id: doc.id,
      data: d,
      source: d['source'] as String? ?? 'direct',
      groupId: d['group_id'] as String? ?? '',
      groupName: d['group_name'] as String? ?? '',
    );
  }

  factory _MemoItem.fromCache(_CachedMemo c) {
    return _MemoItem(
      id: c.id,
      data: c.data,
      source: c.data['source'] as String? ?? 'direct',
      groupId: c.data['group_id'] as String? ?? '',
      groupName: c.data['group_name'] as String? ?? '',
    );
  }
}

class _CachedMemo {
  final String id;
  final Map<String, dynamic> data;
  _CachedMemo({required this.id, required this.data});

  factory _CachedMemo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final millis = json['updated_at'] as int?;
    final data = Map<String, dynamic>.from(json)..remove('id');
    // updated_at 복원 (Timestamp 대신 Map으로 저장)
    if (millis != null) {
      data['updated_at'] = _FakeTimestamp(millis);
    }
    return _CachedMemo(id: id, data: data);
  }
}

// Timestamp 인터페이스 호환용 (캐시에서만 사용)
class _FakeTimestamp {
  final int millisecondsSinceEpoch;
  _FakeTimestamp(this.millisecondsSinceEpoch);
  DateTime toDate() =>
      DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
}

// DirectMemoSection에 QueryDocumentSnapshot 대신 넘기기 위한 래퍼
class _FakeDoc implements QueryDocumentSnapshot {
  final String _id;
  final Map<String, dynamic> _data;
  _FakeDoc({required String id, required Map<String, dynamic> data})
      : _id = id,
        _data = data;

  @override String get id => _id;
  @override Map<String, dynamic> data() => _data;
  @override DocumentReference get reference =>
      throw UnimplementedError();
  @override SnapshotMetadata get metadata => throw UnimplementedError();
  @override bool get exists => true;
  @override dynamic get(Object field) => _data[field];
  @override dynamic operator [](Object field) => _data[field];
}
