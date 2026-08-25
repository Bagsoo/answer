import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/rendering.dart';
import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../services/group_service.dart';
import '../services/local_preferences_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/groups/group_tile.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';
import '../utils/ad_interleaver.dart';
import '../services/group_cache_service.dart';
import '../models/group_cache.dart';

import '../services/analytics_service.dart';

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
  final ScrollController _myGroupsScrollController = ScrollController();
  bool _fabVisible = true;

  late TabController _tabController;

  List<Map<String, dynamic>> _joinedGroups = [];
  bool _joinedLoading = true;

  List<Map<String, dynamic>> _recommendedGroups = [];
  bool _recommendLoading = false;
  bool _recommendLoaded = false;
  String? _recommendErrorMsg;

  String get _currentUserId => context.read<UserProvider>().uid;
  String get _tabKey => LocalPreferencesService.groupListTabKey(_currentUserId);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      LocalPreferencesService.setInt(_tabKey, _tabController.index);
      if (_tabController.index == 0 && !_recommendLoaded) {
        _loadRecommendations();
      }
    });
    _restoreSelectedTab();
    _loadRecommendations();
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
    _myGroupsScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final isScrollingDown = _myGroupsScrollController.position.userScrollDirection
        == ScrollDirection.reverse;
    final isScrollingUp = _myGroupsScrollController.position.userScrollDirection
        == ScrollDirection.forward;

    if (isScrollingDown && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (isScrollingUp && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
  }

  Future<void> _loadCachedGroups() async {
    final cached = await GroupCacheService.getJoinedGroups();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _joinedGroups = cached.map((e) => e.toJson()).toList();
        _joinedLoading = false;
      });
    }
  }

  Future<void> _saveGroupsCache(List<Map<String, dynamic>> groups) async {
    try {
      final caches = groups.map((g) => GroupCache.fromJson(g)).toList();
      await GroupCacheService.saveJoinedGroups(caches);
    } catch (_) {}
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _recommendLoading = true;
      _recommendLoaded = true;
      _recommendErrorMsg = null;
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
      debugPrint('Failed to load recommendations: $e');
      if (mounted) {
        setState(() {
          _recommendLoading = false;
          _recommendErrorMsg = 'Failed to load recommendations: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _myGroupsScrollController.removeListener(_onScroll);
    _myGroupsScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _restoreSelectedTab() async {
    final savedIndex = await LocalPreferencesService.getInt(_tabKey);
    if (!mounted || savedIndex == null || savedIndex < 0 || savedIndex > 1) {
      return;
    }
    _tabController.animateTo(savedIndex);
  }

  void _handleGroupTap(Map<String, dynamic> group, bool isAlreadyJoined) {
    // ── Analytics 로그 (추천 클릭 시) ──
    if (_tabController.index == 0) {
      context.read<AnalyticsService>().logClickRecommendation(
        groupId: group['id'] as String? ?? '',
        groupName: group['name'] as String? ?? '',
        score: (group['_score'] as num?)?.toDouble() ?? 0.0,
      );
    }

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
      floatingActionButton: AnimatedSlide(
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: _fabVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: FloatingActionButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.recommend_outlined), text: l.recommended),
              Tab(icon: const Icon(Icons.group), text: l.myGroups),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecommendTab(joinedIds, l, cs, userProvider),
                _buildMyGroupsTab(l, cs),
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
      controller: _myGroupsScrollController,
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.recommend_outlined,
                          size: 48, color: cs.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text(
                        _recommendErrorMsg ?? l.noRecommendations,
                        style: TextStyle(
                            color: _recommendErrorMsg != null ? cs.error : cs.onSurface.withOpacity(0.5)),
                        textAlign: TextAlign.center,
                      ),
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
              mainAxisSize: MainAxisSize.min,
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
                          color: cs.onSurface.withOpacity(0.7)),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                if (!hasInterests)
                  Text('• ${l.setInterests}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.7)),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
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
                          decoration: TextDecoration.underline),
                      softWrap: true,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
