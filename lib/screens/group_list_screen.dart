import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/group_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/groups/group_tile.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen>
    with SingleTickerProviderStateMixin {
  static const _keyJoinedGroups = 'joined_groups_cache';

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _joinedGroups = [];
  bool _joinedLoading = true;

  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;

  StreamSubscription? _joinedSub;
  StreamSubscription? _searchSub;
  Timer? _debounce;

  String get _currentUserId => context.read<UserProvider>().uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCachedGroups();

    _joinedSub =
        context.read<GroupService>().getMyJoinedGroups().listen((list) {
      if (mounted) {
        final mapped = list
            .map((g) => {'id': g['id'] ?? g.keys.first, ...g})
            .toList();
        setState(() {
          _joinedGroups = mapped;
          _joinedLoading = false;
        });
        // Firebase 응답 오면 캐시 갱신
        _saveGroupsCache(mapped);
      }
    });
  }

  // ── 캐시 로드 (앱 시작 시 즉시 표시) ──────────────────────────────────────
  Future<void> _loadCachedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyJoinedGroups);
    if (raw != null && mounted) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        final cached = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (cached.isNotEmpty) {
          setState(() {
            _joinedGroups = cached;
            // 캐시가 있으면 로딩 스피너 표시 안 함
            _joinedLoading = false;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _saveGroupsCache(List<Map<String, dynamic>> groups) async {
    try {
      // id, name, type, category, member_count, group_profile_image만 저장
      final slim = groups.map((g) => {
        'id': g['id'],
        'name': g['name'],
        'type': g['type'],
        'category': g['category'],
        'member_count': g['member_count'],
        'group_profile_image': g['group_profile_image'],
      }).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyJoinedGroups, jsonEncode(slim));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _joinedSub?.cancel();
    _searchSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    final query = val.trim();
    setState(() {
      _searchQuery = query;
      _searchResults = [];
      if (query.isNotEmpty) _searchLoading = true;
    });

    _debounce?.cancel();
    _searchSub?.cancel();

    if (query.isEmpty) {
      setState(() => _searchLoading = false);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchSub =
          context.read<GroupService>().searchGroups(query).listen((list) {
        if (mounted) {
          setState(() {
            _searchResults =
                list.map((g) => {'id': g['id'] ?? '', ...g}).toList();
            _searchLoading = false;
          });
        }
      });
    });
  }

  Future<void> _onJoinPressed(Map<String, dynamic> group) async {
    final l = AppLocalizations.of(context);
    final groupService = context.read<GroupService>();
    final requireApproval = group['require_approval'] ?? false;
    final groupId = group['id'];
    final groupName = group['name'] ?? 'Unknown';
    final groupType = group['type'] ?? 'club';
    final groupCategory = group['category'] ?? 'Other';
    final memberCount = group['member_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );

    final userProvider = context.read<UserProvider>();
    final result = await groupService.requestToJoin(
      groupId,
      requireApproval,
      groupName,
      groupType,
      groupCategory,
      memberCount,
      userProvider.name,
      userProvider.phoneNumber,
      userProvider.photoUrl ?? '',
    );

    if (!mounted) return;
    Navigator.pop(context);

    if (result == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            requireApproval ? l.joinRequestSent : l.joinedSuccess),
      ));
      setState(() {
        _searchQuery = '';
        _searchController.clear();
        _searchResults = [];
      });
      _searchSub?.cancel();
      _tabController.animateTo(0);
    } else if (result == 'full') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.groupFull)));
    } else if (result == 'banned') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.bannedFromGroup)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.joinFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final joinedIds =
        _joinedGroups.map((g) => g['id'] as String? ?? '').toSet();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.group), text: l.myGroups),
              Tab(icon: const Icon(Icons.search), text: l.findGroups),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyGroupsTab(l, colorScheme),
                _buildDiscoverTab(joinedIds, l, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupsTab(AppLocalizations l, ColorScheme colorScheme) {
    if (_joinedLoading && _joinedGroups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_joinedGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off,
                size: 64,
                color: colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(l.noGroupsJoined,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _joinedGroups.length,
      itemBuilder: (context, index) =>
          JoinedGroupTile(group: _joinedGroups[index]),
      separatorBuilder: (_, __) => const Divider(height: 1),
    );
  }

  Widget _buildDiscoverTab(
      Set<String> joinedIds, AppLocalizations l, ColorScheme colorScheme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l.searchGroupsHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _searchQuery.isEmpty
              ? _buildDiscoverPlaceholder(l, colorScheme)
              : _buildSearchResults(joinedIds, l, colorScheme),
        ),
      ],
    );
  }

  Widget _buildDiscoverPlaceholder(
      AppLocalizations l, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.travel_explore,
              size: 64,
              color: colorScheme.onSurface.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(l.searchGroupsHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.4))),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
      Set<String> joinedIds, AppLocalizations l, ColorScheme colorScheme) {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text(l.noGroupsFound));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final group = _searchResults[index];
        return DiscoverGroupTile(
          group: group,
          isAlreadyJoined:
              joinedIds.contains(group['id'] as String? ?? ''),
          onJoinPressed: () => _onJoinPressed(group),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
    );
  }
}