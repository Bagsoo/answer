import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/friend_service.dart';
import '../services/block_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import '../screens/chat_room_screen.dart';
import '../widgets/friends/friend_tile.dart';
import '../widgets/friends/add_friend_dialog.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  bool _isFiltering = false;

  List<Map<String, dynamic>> _friends = [];
  Set<String> _blockedUids = {};
  bool _loading = true;

  // 앱 시작 시 캐시에서 즉시 표시할 친구 수
  int _cachedFriendCount = -1;

  StreamSubscription? _friendsSub;
  StreamSubscription? _blockedSub;

  @override
  void initState() {
    super.initState();
    _loadCachedCount();

    _blockedSub =
        context.read<BlockService>().getBlockedUidSet().listen((uids) {
      if (mounted) setState(() => _blockedUids = uids);
    });

    _friendsSub = context.read<FriendService>().getFriends().listen((list) {
      if (mounted) {
        setState(() {
          _friends = list;
          _loading = false;
          _cachedFriendCount = list.length; // 실제 값으로 동기화
        });
      }
    });
  }

  Future<void> _loadCachedCount() async {
    final count = await FriendService.getCachedFriendCount();
    if (mounted && count >= 0) {
      setState(() => _cachedFriendCount = count);
    }
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _blockedSub?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  String _stripCountryCode(String digits) {
    const codes = ['82', '81', '86', '852', '886', '65', '66', '1'];
    for (final code in codes) {
      if (digits.startsWith(code) && digits.length > code.length + 4) {
        return digits.substring(code.length);
      }
    }
    return digits;
  }

  Future<void> _openDm(String friendUid, String friendName) async {
    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    final roomId = await friendService.getOrCreateDmRoom(
        friendUid, friendName,
        myName: myName);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatRoomScreen(roomId: roomId),
    ));
  }

  Future<void> _blockUser(String targetUid, String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.blockUser),
        content: Text(l.blockUserConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.blockUser),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await context.read<BlockService>().blockUser(targetUid, name);
    await context.read<FriendService>().removeFriend(targetUid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.blockUserDone)),
      );
    }
  }

  Future<void> _removeFriend(String friendUid, String friendName) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFriend),
        content: Text('$friendName${l.removeFriendConfirm}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await context.read<FriendService>().removeFriend(friendUid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.friendRemoved)),
      );
    }
  }

  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddFriendDialog(
        onDm: (uid, name) {
          Navigator.pop(ctx);
          _openDm(uid, name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final allFriends =
        _friends.where((f) => !_blockedUids.contains(f['uid'])).toList();

    // Firebase 스트림 오기 전 → 캐시 값 표시, 이후 → 실제 값
    final displayCount =
        _loading && _cachedFriendCount >= 0 ? _cachedFriendCount : allFriends.length;

    final filtered = _filterQuery.isEmpty
        ? allFriends
        : allFriends.where((f) {
            final name =
                (f['display_name'] as String? ?? '').toLowerCase();
            final phone = f['phone_number'] as String? ?? '';
            final q = _filterQuery.toLowerCase();
            if (name.contains(q)) return true;
            final digitsStored = phone.replaceAll(RegExp(r'\D'), '');
            final digitsQuery =
                _filterQuery.replaceAll(RegExp(r'\D'), '');
            if (digitsQuery.isEmpty) return false;
            if (digitsStored.contains(digitsQuery)) return true;
            final localStored = _stripCountryCode(digitsStored);
            final localQuery = _stripCountryCode(digitsQuery);
            if (localStored.contains(localQuery)) return true;
            if (localQuery.isNotEmpty &&
                digitsStored.contains(localQuery)) return true;
            return false;
          }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFriendDialog,
        child: const Icon(Icons.person_add_outlined),
      ),
      body: Column(
        children: [
          // ── 헤더 + 필터 검색 ────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(children: [
                  Text(
                    l.friendsList,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 캐시 값으로 즉시 표시, Firebase 응답 후 실제 값으로 교체
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$displayCount',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _isFiltering ? Icons.search_off : Icons.search,
                      size: 20,
                      color: _isFiltering
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.5),
                    ),
                    onPressed: () {
                      setState(() {
                        _isFiltering = !_isFiltering;
                        if (!_isFiltering) {
                          _filterController.clear();
                          _filterQuery = '';
                        }
                      });
                    },
                  ),
                ]),
              ),
              if (_isFiltering)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _filterController,
                    autofocus: true,
                    onChanged: (v) =>
                        setState(() => _filterQuery = v.trim()),
                    decoration: InputDecoration(
                      hintText: l.searchPlaceholder,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() {
                                _filterController.clear();
                                _filterQuery = '';
                              }),
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
            ],
          ),

          // ── 친구 목록 ──────────────────────────────────────────────
          Expanded(
            child: _loading && _friends.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64,
                                color:
                                    colorScheme.onSurface.withOpacity(0.2)),
                            const SizedBox(height: 16),
                            Text(l.noFriends,
                                style: TextStyle(
                                    color: colorScheme.onSurface
                                        .withOpacity(0.4))),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _showAddFriendDialog,
                              icon: const Icon(Icons.person_add_outlined,
                                  size: 18),
                              label: Text(l.addFriend),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            FriendTile(friend: filtered[index]),
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                      ),
          ),
        ],
      ),
    );
  }
}