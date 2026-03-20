import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../providers/user_provider.dart';
import '../widgets/group_settings/group_avatar_widget.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';
import '../l10n/app_localizations.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen>
    with SingleTickerProviderStateMixin {
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

  String get _currentUserId =>
      context.read<UserProvider>().uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _joinedSub =
        context.read<GroupService>().getMyJoinedGroups().listen((list) {
      if (mounted) {
        setState(() {
          _joinedGroups =
              list.map((g) => {'id': g['id'] ?? g.keys.first, ...g}).toList();
          _joinedLoading = false;
        });
      }
    });
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
      builder: (context) => const Center(child: CircularProgressIndicator()),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              requireApproval ? l.joinRequestSent : l.joinedSuccess),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.bannedFromGroup)),
      );
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
        _joinedGroups.map((g) => g['id'] as String).toSet();

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

  // ── Tab 1: My Joined Groups ───────────────────────────────────────────────
  Widget _buildMyGroupsTab(AppLocalizations l, ColorScheme colorScheme) {
    if (_joinedLoading) {
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
            Text(
              l.noGroupsJoined,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _joinedGroups.length,
      itemBuilder: (context, index) {
        final group = _joinedGroups[index];
        final groupId = group['id'] as String? ?? '';
        final name = group['name'] as String? ?? l.unknown;
        final type = group['type'] as String? ?? 'N/A';
        final category = group['category'] as String? ?? 'N/A';
        final memberCount = (group['member_count'] as num?)?.toInt() ?? 1;
        final imageUrl = group['group_profile_image'] as String? ?? '';

        return ListTile(
          leading: GroupAvatarSync(
            groupName: name,
            imageUrl: imageUrl,
            radius: 22,
            fallbackIcon: Icons.business,
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
          ),
          title: Row(children: [
            Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            _memberBadge(memberCount, colorScheme.primaryContainer),
          ]),
          subtitle:
              Text("${l.type}: $type  •  ${l.category}: $category"),
          trailing: Icon(Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.4)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailScreen(
              groupId: groupId,
              groupName: name,
            ),
          )),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
    );
  }

  // ── Tab 2: Discover / Search Groups ──────────────────────────────────────
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
          Text(
            l.searchGroupsHint,
            textAlign: TextAlign.center,
            style:
                TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
          ),
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
        final name = group['name'] as String? ?? l.unknown;
        final type = group['type'] as String? ?? 'N/A';
        final category = group['category'] as String? ?? 'N/A';
        final memberCount = (group['member_count'] as num?)?.toInt() ?? 1;
        final requireApproval = group['require_approval'] as bool? ?? false;
        final imageUrl = group['group_profile_image'] as String? ?? '';
        final likes = List<String>.from(group['likes'] as List? ?? []);
        final isAlreadyJoined = joinedIds.contains(group['id']);

        return ListTile(
          // ── 그룹 프로필 사진 ────────────────────────────────────────
          leading: GroupAvatarSync(
            groupName: name,
            imageUrl: imageUrl,
            radius: 22,
            fallbackIcon: Icons.group,
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
          ),
          title: Row(children: [
            Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            _memberBadge(memberCount, colorScheme.surfaceContainerHighest),
          ]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${l.type}: $type  •  ${l.category}: $category"),
              // ── 좋아요 표시 ──────────────────────────────────────────
              if (likes.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.favorite,
                        size: 12, color: Colors.red.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text(
                      '${likes.length}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.withOpacity(0.7)),
                    ),
                  ],
                ),
            ],
          ),
          // ── 가입 여부에 따른 trailing ──────────────────────────────
          trailing: isAlreadyJoined
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: colorScheme.outline.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        l.alreadyJoined,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              : ElevatedButton(
                  onPressed: () => _onJoinPressed(group),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: requireApproval
                        ? colorScheme.tertiary
                        : colorScheme.primary,
                    foregroundColor: requireApproval
                        ? colorScheme.onTertiary
                        : colorScheme.onPrimary,
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
          // ── 그룹 클릭 시 미리보기 화면으로 이동 ─────────────────────
          onTap: () {
            if (isAlreadyJoined) {
              // 가입된 그룹이면 그룹 상세로
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupDetailScreen(
                  groupId: group['id'] as String,
                  groupName: name,
                ),
              ));
            } else {
              // 미가입 그룹이면 미리보기로
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupPreviewScreen(group: group),
              ));
            }
          },
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
    );
  }

  Widget _memberBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}