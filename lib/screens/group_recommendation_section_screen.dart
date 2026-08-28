import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/group_service.dart';
import '../services/recommendation_service.dart';
import '../widgets/ad/group_native_ad_tile.dart';
import '../widgets/groups/recommendation_group_card.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';

class GroupRecommendationSectionScreen extends StatefulWidget {
  final RecommendationSectionType section;

  const GroupRecommendationSectionScreen({
    super.key,
    required this.section,
  });

  @override
  State<GroupRecommendationSectionScreen> createState() =>
      _GroupRecommendationSectionScreenState();
}

class _GroupRecommendationSectionScreenState
    extends State<GroupRecommendationSectionScreen> {
  static const int _pageSize = 12;

  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _joinedSubscription;

  List<Map<String, dynamic>> _groups = [];
  final Set<String> _joinedIds = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _joinedSubscription = context.read<GroupService>().getMyJoinedGroups().listen((list) {
      if (!mounted) return;
      setState(() {
        _joinedIds
          ..clear()
          ..addAll(list.map((g) => g['id'] as String? ?? '').where((id) => id.isNotEmpty));
      });
    });
    _loadGroups();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _joinedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await context
          .read<RecommendationService>()
          .getRecommendationSectionGroups(widget.section, limit: 60);
      if (!mounted) return;
      setState(() {
        _groups = results;
        _visibleCount = _pageSize;
        _hasMore = _groups.length > _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _hasMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter > 600) return;

    setState(() {
      _loadingMore = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _visibleCount = (_visibleCount + _pageSize).clamp(0, _groups.length).toInt();
        _hasMore = _visibleCount < _groups.length;
        _loadingMore = false;
      });
    });
  }

  void _handleTap(Map<String, dynamic> group) {
    final groupId = group['id'] as String? ?? '';
    if (groupId.isEmpty) return;

    final isJoined = _joinedIds.contains(groupId);
    if (isJoined) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupId: groupId,
          groupName: group['name'] as String? ?? '',
        ),
      ));
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupPreviewScreen(group: group),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final title = _sectionTitle(l);
    final description = _sectionDescription(l);
    final emptyMessage = _emptyMessage(l);
    final visibleGroups = _groups.take(_visibleCount).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroups,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.error_outline,
                          size: 56, color: cs.error.withOpacity(0.7)),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton(
                          onPressed: _loadGroups,
                          child: Text(l.retry),
                        ),
                      ),
                    ],
                  )
                : CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.primaryContainer.withOpacity(0.75),
                                  cs.surfaceContainerHighest,
                                ],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (visibleGroups.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                emptyMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _buildListItem(l, index, visibleGroups);
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == _buildSliverItemsCount(visibleGroups.length) - 1 ? 0 : 12,
                                  ),
                                  child: item,
                                );
                              },
                              childCount: _buildSliverItemsCount(visibleGroups.length),
                            ),
                          ),
                        ),
                      if (_loadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (!_loadingMore && !_hasMore && visibleGroups.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: Text(
                              l.noMoreResults,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  int _buildSliverItemsCount(int groupCount) {
    if (groupCount < 4) return groupCount;
    final adCount = groupCount ~/ 4;
    return groupCount + adCount;
  }

  Widget _buildListItem(
    AppLocalizations l,
    int index,
    List<Map<String, dynamic>> groups,
  ) {
    final groupSlot = _groupSlotFromIndex(index);
    if (groupSlot != null) {
      final group = groups[groupSlot];
      return RecommendationGroupCard(
        group: group,
        isJoined: _joinedIds.contains(group['id'] as String? ?? ''),
        onTap: () => _handleTap(group),
        chips: _reasonChips(l, group),
        width: double.infinity,
      );
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: GroupNativeAdTile(),
    );
  }

  int? _groupSlotFromIndex(int index) {
    final blockSize = 5;
    final blockIndex = index ~/ blockSize;
    final offset = index % blockSize;
    if (offset == 4) {
      return null;
    }
    final groupIndex = blockIndex * 4 + offset;
    return groupIndex < _visibleCount ? groupIndex : null;
  }

  String _sectionTitle(AppLocalizations l) {
    return switch (widget.section) {
      RecommendationSectionType.active => l.activeGroups,
      RecommendationSectionType.personalized => l.personalizedGroups,
      RecommendationSectionType.nearbyNew => l.nearbyNewGroups,
    };
  }

  String _sectionDescription(AppLocalizations l) {
    return switch (widget.section) {
      RecommendationSectionType.active => l.activeGroupsDesc,
      RecommendationSectionType.personalized => l.personalizedGroupsDesc,
      RecommendationSectionType.nearbyNew => l.nearbyNewGroupsDesc,
    };
  }

  String _emptyMessage(AppLocalizations l) {
    return switch (widget.section) {
      RecommendationSectionType.active => l.noActiveGroups,
      RecommendationSectionType.personalized => l.noPersonalizedGroups,
      RecommendationSectionType.nearbyNew => l.noNearbyNewGroups,
    };
  }

  List<String> _reasonChips(AppLocalizations l, Map<String, dynamic> group) {
    final chips = <String>[];
    switch (widget.section) {
      case RecommendationSectionType.active:
        chips.add(l.recentlyActive);
        chips.add('${l.activityScore} ${(group['_score'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}');
        break;
      case RecommendationSectionType.personalized:
        final matched = (group['matched_interest_count'] as num?)?.toInt() ?? 0;
        if (matched > 0) {
          chips.add('${l.matchedInterests} $matched');
        }
        break;
      case RecommendationSectionType.nearbyNew:
        chips.add(l.newlyCreated);
        break;
    }
    return chips;
  }
}
