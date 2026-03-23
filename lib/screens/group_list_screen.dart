import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../services/group_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/groups/group_tile.dart';
import '../screens/group_tabs/group_type_category_data.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';
import 'dart:convert';

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

  List<Map<String, dynamic>> _recommendedGroups = [];
  bool _recommendLoading = false;
  bool _recommendLoaded = false;

  String get _currentUserId => context.read<UserProvider>().uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // 추천 탭 선택 시 처음 한 번만 로드
      if (_tabController.index == 1 && !_recommendLoaded) {
        _loadRecommendations();
      }
    });
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

  Future<void> _onJoinPressed(Map<String, dynamic> group) async {
    final l = AppLocalizations.of(context);
    final groupService = context.read<GroupService>();
    final requireApproval = group['require_approval'] ?? false;
    final groupId = group['id'];
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
      group['name'] ?? '',
      group['type'] ?? 'club',
      group['category'] ?? '',
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

  // ── 내 그룹 탭 ────────────────────────────────────────────────────────────
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _joinedGroups.length,
      itemBuilder: (context, i) =>
          JoinedGroupTile(group: _joinedGroups[i]),
      separatorBuilder: (_, __) => const Divider(height: 1),
    );
  }

  // ── 추천 탭 ──────────────────────────────────────────────────────────────
  Widget _buildRecommendTab(
    Set<String> joinedIds,
    AppLocalizations l,
    ColorScheme cs,
    UserProvider userProvider,
  ) {
    if (_recommendLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 위치/관심사 미설정 안내
    final hasLocation = userProvider.hasLocation;
    final hasInterests = userProvider.interests.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _recommendLoaded = false);
        await _loadRecommendations();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 위치/관심사 미설정 안내 배너
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
            ...(_recommendedGroups.map((group) {
              final isJoined =
                  joinedIds.contains(group['id'] as String? ?? '');
              return _RecommendGroupTile(
                group: group,
                isAlreadyJoined: isJoined,
                onJoinPressed: () => _onJoinPressed(group),
                l: l,
                cs: cs,
              );
            })),
        ],
      ),
    );
  }

  // ── 검색 탭 ──────────────────────────────────────────────────────────────
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
                            return DiscoverGroupTile(
                              group: group,
                              isAlreadyJoined: joinedIds
                                  .contains(group['id'] as String? ?? ''),
                              onJoinPressed: () => _onJoinPressed(group),
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

// ── 위치/관심사 미설정 안내 배너 ──────────────────────────────────────────────
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

// ── 추천 그룹 타일 ────────────────────────────────────────────────────────────
class _RecommendGroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isAlreadyJoined;
  final VoidCallback onJoinPressed;
  final AppLocalizations l;
  final ColorScheme cs;

  const _RecommendGroupTile({
    required this.group,
    required this.isAlreadyJoined,
    required this.onJoinPressed,
    required this.l,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? l.unknown;
    final type = group['type'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 0;
    final requireApproval = group['require_approval'] as bool? ?? false;
    final imageUrl = group['group_profile_image'] as String? ?? '';
    final distanceKm = group['distance_km'] as String?;
    final typeLabel = GroupTypeCategoryData.localizeType(type, l);
    final categoryLabel = GroupTypeCategoryData.localizeKey(category, l);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: cs.secondaryContainer,
        backgroundImage:
            imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onSecondaryContainer))
            : null,
      ),
      title: Text(name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$typeLabel · $categoryLabel',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
          Row(children: [
            Icon(Icons.people_outline,
                size: 12, color: cs.onSurface.withOpacity(0.4)),
            const SizedBox(width: 3),
            Text('$memberCount',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.5))),
            if (distanceKm != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.place_outlined,
                  size: 12, color: cs.primary.withOpacity(0.6)),
              const SizedBox(width: 3),
              Text('${distanceKm}km',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.primary.withOpacity(0.7))),
            ],
          ]),
        ],
      ),
      trailing: isAlreadyJoined
          ? Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(l.alreadyJoined,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ]),
            )
          : ElevatedButton(
              onPressed: onJoinPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    requireApproval ? cs.tertiary : cs.primary,
                foregroundColor:
                    requireApproval ? cs.onTertiary : cs.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
              child: Text(
                requireApproval ? l.requestJoin : l.joinNow,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupPreviewScreen(group: group),
      )),
    );
  }
}