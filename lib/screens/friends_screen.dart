import 'dart:async';
import 'package:flutter/foundation.dart';
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
  final String filterQuery;
  const FriendsScreen({super.key, this.filterQuery = ''});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {  

  List<Map<String, dynamic>> _friends = [];
  Set<String> _blockedUids = {};
  bool _loading = true;

  // 앱 시작 시 캐시에서 즉시 표시할 친구 수
  int _cachedFriendCount = -1;

  StreamSubscription? _friendsSub;
  StreamSubscription? _blockedSub;
  Timer? _friendsBindTimer;
  Timer? _blockedPollTimer;

  Future<void> _pollBlockedUidsWindows(BlockService blockService) async {
    if (!mounted) return;
    try {
      final uids = await blockService.fetchBlockedUidSetOnce();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _blockedUids = uids);
      });
    } catch (e) {
      debugPrint('FriendsScreen blocked poll error: $e');
    }
  }

  void _bindFirestoreStreams() {
    if (!mounted) return;
    final win = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    void bindFriends() {
      if (!mounted || _friendsSub != null) return;
      _friendsSub = context.read<FriendService>().getFriends().listen((list) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _friends = list;
            _loading = false;
            _cachedFriendCount = list.length; // 실제 값으로 동기화
          });
        });
      });
    }

    if (win) {
      final blockService = context.read<BlockService>();
      // Windows: users/.../blocked 에 snapshots()를 걸면 바로 네이티브가 끊기는
      // 증상이 있어 get() 폴링으로만 갱신한다.
      _blockedPollTimer?.cancel();
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        _pollBlockedUidsWindows(blockService);
      });
      _blockedPollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _pollBlockedUidsWindows(blockService),
      );

      _friendsBindTimer?.cancel();
      _friendsBindTimer = Timer(const Duration(milliseconds: 900), bindFriends);
    } else {
      _blockedSub =
          context.read<BlockService>().getBlockedUidSet().listen((uids) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _blockedUids = uids);
        });
      });
      bindFriends();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedCount();

    void scheduleBind() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bindFirestoreStreams();
      });
    }

    // Windows: ChatProvider 등 다른 초기화가 끝난 뒤에 Firestore 구독을 붙인다.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      Future<void>.delayed(const Duration(milliseconds: 1600), scheduleBind);
    } else {
      scheduleBind();
    }
  }

  Future<void> _loadCachedCount() async {
    final count = await FriendService.getCachedFriendCount();
    if (mounted && count >= 0) {
      setState(() => _cachedFriendCount = count);
    }
  }

  @override
  void dispose() {
    _friendsBindTimer?.cancel();
    _blockedPollTimer?.cancel();
    _friendsSub?.cancel();
    _blockedSub?.cancel();
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
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        setState(() => _blockedUids = {..._blockedUids, targetUid});
      }
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

    final filtered = widget.filterQuery.isEmpty
        ? allFriends
        : allFriends.where((f) {
            final name =
                (f['display_name'] as String? ?? '').toLowerCase();
            final phone = f['phone_number'] as String? ?? '';
            final q = widget.filterQuery.toLowerCase();
            if (name.contains(q)) return true;
            final digitsStored = phone.replaceAll(RegExp(r'\D'), '');
            final digitsQuery =
                widget.filterQuery.replaceAll(RegExp(r'\D'), '');
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