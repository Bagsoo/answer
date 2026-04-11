import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../services/group_service.dart';
import '../services/local_preferences_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/groups/group_tile.dart';
import '../screens/group_tabs/group_type_category_data.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';
import 'group_qr_join_preview_screen.dart';
import 'group_tabs/group_qr_scanner_screen.dart';
import 'dart:convert';
import '../utils/ad_interleaver.dart';

class GroupListScreen extends StatefulWidget {
  final bool isDesktopMode;
  final String? selectedGroupId;
  final void Function(Map<String, dynamic> group)? onGroupSelected;

  const GroupListScreen({
    super.key,
    this.isDesktopMode = false,
    this.selectedGroupId,
    this.onGroupSelected,
  });

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

  List<Map<String, dynamic>> _recommendedGroups = [];
  bool _recommendLoading = false;
  bool _recommendLoaded = false;

  String get _currentUserId => context.read<UserProvider>().uid;
  String get _tabKey => LocalPreferencesService.groupListTabKey(_currentUserId);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      LocalPreferencesService.setInt(_tabKey, _tabController.index);
      if (_tabController.index == 1 && !_recommendLoaded) {
        _loadRecommendations();
      }
    });
    _restoreSelectedTab();
    _loadCachedGroups();
    context.read<GroupService>().getMyJoinedGroups().listen((list) {
      if (mounted) {
        final mapped = list
            .map((g) => {'id': g['id'] ?? g.keys.first, ...g})
            .toList();
        setState(() {
          _joinedGroups = mapped;
          _joinedLoading = false;
        });
        _saveGroupsCache(mapped);
      }
    });
  }

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
            _joinedLoading = false;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _saveGroupsCache(List<Map<String, dynamic>> groups) async {
    try {
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

  Future<void> _loadRecommendations() async {
    setState(() {
      _recommendLoading = true;
      _recommendLoaded = true;
    });
    try {
      final results = await context
          .read<RecommendationService>()
          .getRecommendedGroups();
      if (mounted) {
        setState(() {
          _recommendedGroups = results;
          _recommendLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _recommendLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    final query = val.trim();
    setState(() {
      _searchQuery = query;
      _searchResults = [];
      if (query.isNotEmpty) _searchLoading = true;
    });

    if (query.isEmpty) {
      setState(() => _searchLoading = false);
      return;
    }

    context.read<GroupService>().searchGroups(query).listen((list) {
      if (mounted) {
        setState(() {
          _searchResults =
              list.map((g) => {'id': g['id'] ?? '', ...g}).toList();
          _searchLoading = false;
        });
      }
    });
  }

  Future<void> _restoreSelectedTab() async {
    final savedIndex = await LocalPreferencesService.getInt(_tabKey);
    if (!mounted || savedIndex == null || savedIndex < 0 || savedIndex > 2) {
      return;
    }
    _tabController.animateTo(savedIndex);
  }

  Future<void> _openQrJoinFlow() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const GroupQrScannerScreen()),
    );

    if (!mounted || code == null || code.trim().isEmpty) {
      return;
    }

    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupQrJoinPreviewScreen(rawValue: code),
      ),
    );

    if (!mounted || joined != true) return;

    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _searchResults = [];
    });
    _tabController.animateTo(0);
  }

  void _handleGroupTap(Map<String, dynamic> group, bool isAlreadyJoined) {
    if (isAlreadyJoined) {
      if (widget.isDesktopMode && widget.onGroupSelected != null) {
        widget.onGroupSelected!(group);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupId: group['id'] as String,
          groupName: group['name'] as String? ?? 'Unknown',
        ),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupPreviewScreen(group: group),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final joinedIds =
        _joinedGroups.map((g) => g['id'] as String? ?? '').toSet();
    final userProvider = context.watch<UserProvider>();

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
              Tab(icon: const Icon(Icons.recommend_outlined), text: l.recommended),
              Tab(icon: const Icon(Icons.search), text: l.findGroups),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyGroupsTab(l, cs),
                _buildRecommendTab(joinedIds, l, cs, userProvider),
                _buildDiscoverTab(joinedIds, l, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupsTab(AppLocalizations l, ColorScheme cs) {
    if (_joinedLoading && _joinedGroups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_joinedGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off,
                size: 64, color: cs.onSurface.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(l.noGroupsJoined,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }

    if (widget.isDesktopMode &&
        widget.onGroupSelected != null &&
        !_joinedGroups.any((g) => (g['id'] as String?) == widget.selectedGroupId)) {
      final first = _joinedGroups.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onGroupSelected!(first);
      });
    }

    final groupWidgets = _joinedGroups.indexed.map<Widget>((entry) {
      final (i, g) = entry;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          JoinedGroupTile(
            group: g,
            isSelected: widget.selectedGroupId == (g['id'] as String? ?? ''),
            onTapOverride: widget.isDesktopMode
                ? () => _handleGroupTap(g, true)
                : null,
          ),
          if (i < _joinedGroups.length - 1) const Divider(height: 1),
        ],
      );
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: interleaveAds(groupWidgets, keyPrefix: 'my_group_ad'),
    );
  }

  Widget _buildRecommendTab(
    Set<String> joinedIds,
    AppLocalizations l,
    ColorScheme cs,
    UserProvider userProvider,
  ) {
    if (_recommendLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasLocation = userProvider.hasLocation;
    final hasInterests = userProvider.interests.isNotEmpty;

    final recommendWidgets = _recommendedGroups.map<Widget>((group) {
      final isJoined = joinedIds.contains(group['id'] as String? ?? '');
      return ExploreGroupTile(
        group: group,
        isAlreadyJoined: isJoined,
        onTap: () => _handleGroupTap(group, isJoined),
      );
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _recommendLoaded = false);
        await _loadRecommendations();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!hasLocation || !hasInterests)
            _RecommendSetupBanner(
              hasLocation: hasLocation,
              hasInterests: hasInterests,
              l: l,
              cs: cs,
            ),

          if (_recommendedGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.recommend_outlined,
                        size: 64, color: cs.onSurface.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text(l.noRecommendations,
                        style: TextStyle(
                            color: cs.onSurface.withOpacity(0.4))),
                  ],
                ),
              ),
            )
          else
            ...interleaveAds(recommendWidgets, keyPrefix: 'recommend_ad'),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab(
      Set<String> joinedIds, AppLocalizations l, ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l.searchGroupsHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _openQrJoinFlow,
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
                ],
              ),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _searchQuery.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.travel_explore,
                          size: 64,
                          color: cs.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      Text(l.searchGroupsHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onSurface.withOpacity(0.4))),
                    ],
                  ),
                )
              : _searchLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(child: Text(l.noGroupsFound))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, i) {
                            final group = _searchResults[i];
                            final isJoined = joinedIds.contains(group['id'] as String? ?? '');
                            return ExploreGroupTile(
                              group: group,
                              isAlreadyJoined: isJoined,
                              onTap: () => _handleGroupTap(group, isJoined),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                        ),
        ),
      ],
    );
  }
}

class _RecommendSetupBanner extends StatelessWidget {
  final bool hasLocation;
  final bool hasInterests;
  final AppLocalizations l;
  final ColorScheme cs;

  const _RecommendSetupBanner({
    required this.hasLocation,
    required this.hasInterests,
    required this.l,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.betterRecommendations,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                if (!hasLocation)
                  Text('• ${l.setActivityLocation}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.7))),
                if (!hasInterests)
                  Text('• ${l.setInterests}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.7))),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileScreen()),
                    );
                  },
                  child: Text(l.goToProfile,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
