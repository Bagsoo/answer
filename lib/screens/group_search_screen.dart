import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/group_service.dart';
import '../widgets/groups/group_tile.dart';
import 'group_detail_screen.dart';
import 'group_preview_screen.dart';
import 'group_qr_join_preview_screen.dart';
import 'group_tabs/group_qr_scanner_screen.dart';

class GroupSearchScreen extends StatefulWidget {
  const GroupSearchScreen({super.key});

  @override
  State<GroupSearchScreen> createState() => _GroupSearchScreenState();
}

class _GroupSearchScreenState extends State<GroupSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<List<Map<String, dynamic>>>? _searchSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _joinedSubscription;

  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _joinedGroups = [];
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _joinedSubscription = context.read<GroupService>().getMyJoinedGroups().listen((list) {
      if (!mounted) return;
      setState(() {
        _joinedGroups = list
            .map((g) => {'id': g['id'] ?? g.keys.first, ...g})
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _searchSubscription?.cancel();
    _joinedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();

    _searchSubscription?.cancel();
    setState(() {
      _searchQuery = query;
      _searchResults = [];
      _searchLoading = query.isNotEmpty;
    });

    if (query.isEmpty) {
      return;
    }

    context.read<AnalyticsService>().logSearchGroup(query);
    _searchSubscription = context.read<GroupService>().searchGroups(query).listen((list) {
      if (!mounted) return;
      setState(() {
        _searchResults = list.map((g) => {'id': g['id'] ?? '', ...g}).toList();
        _searchLoading = false;
      });
    });
  }

  Future<void> _openQrJoinFlow() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const GroupQrScannerScreen()),
    );

    if (!mounted || code == null || code.trim().isEmpty) {
      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupQrJoinPreviewScreen(rawValue: code),
      ),
    );
  }

  void _handleGroupTap(Map<String, dynamic> group, bool isAlreadyJoined) {
    if (isAlreadyJoined) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          groupId: group['id'] as String,
          groupName: group['name'] as String? ?? 'Unknown',
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
    final joinedIds = _joinedGroups.map((g) => g['id'] as String? ?? '').toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.findGroups),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQrJoinFlow,
            tooltip: l.groupQr,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
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
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.travel_explore,
                              size: 64, color: cs.onSurface.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          Text(
                            l.searchGroupsHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurface.withOpacity(0.4)),
                          ),
                        ],
                      ),
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
                            separatorBuilder: (_, __) => const Divider(height: 1),
            ),
          ),
        ],
      ),
    );
  }
}
