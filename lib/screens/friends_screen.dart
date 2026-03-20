import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/friend_service.dart';
import '../services/block_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'chat_room_screen.dart';
import 'user_profile_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  StreamSubscription? _friendsSub;
  StreamSubscription? _blockedSub;

  @override
  void initState() {
    super.initState();

    _blockedSub =
        context.read<BlockService>().getBlockedUidSet().listen((uids) {
      if (mounted) setState(() => _blockedUids = uids);
    });

    _friendsSub =
        context.read<FriendService>().getFriends().listen((list) {
      if (mounted) {
        setState(() {
          _friends = list;
          _loading = false;
        });
      }
    });
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
        title: const Text('차단'),
        content: Text('$name 님을 차단하시겠어요?\n차단하면 친구 목록에서도 제거됩니다.'),
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
            child: const Text('차단'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await context.read<BlockService>().blockUser(targetUid, name);
    await context.read<FriendService>().removeFriend(targetUid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 님을 차단했습니다')),
      );
    }
  }

  Future<void> _removeFriend(
      String friendUid, String friendName) async {
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
        SnackBar(
            content: Text(AppLocalizations.of(context).friendRemoved)),
      );
    }
  }

  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddFriendDialog(
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

    final filtered = _filterQuery.isEmpty
        ? allFriends
        : allFriends.where((f) {
            final name =
                (f['display_name'] as String? ?? '').toLowerCase();
            final phone = f['phone_number'] as String? ?? '';
            final q = _filterQuery.toLowerCase();

            if (name.contains(q)) return true;

            final digitsStored =
                phone.replaceAll(RegExp(r'\D'), '');
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${allFriends.length}',
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
                      hintText: '이름 또는 번호 검색',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon:
                                  const Icon(Icons.close, size: 16),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64,
                                color: colorScheme.onSurface
                                    .withOpacity(0.2)),
                            const SizedBox(height: 16),
                            Text(l.noFriends,
                                style: TextStyle(
                                    color: colorScheme.onSurface
                                        .withOpacity(0.4))),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _showAddFriendDialog,
                              icon: const Icon(
                                  Icons.person_add_outlined,
                                  size: 18),
                              label: Text(l.addFriend),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final friend = filtered[index];
                          final uid = friend['uid'] as String;
                          final name = friend['display_name'] as String? ?? l.unknown;
                          // profile_image 필드 — String 타입이므로 isNotEmpty로 체크
                          final photoUrl = friend['profile_image'] as String? ?? '';
                          final hasPhoto = photoUrl.isNotEmpty;

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor:
                                  colorScheme.primaryContainer,
                              backgroundImage: hasPhoto
                                ? CachedNetworkImageProvider(photoUrl)
                                : null,
                              onBackgroundImageError:
                                  hasPhoto ? (_, __) {} : null,
                              child: hasPhoto
                                  ? null
                                  : Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            trailing:
                                const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    UserProfileDetailScreen(
                                  uid: uid,
                                  displayName: name,
                                  photoUrl: photoUrl,
                                ),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 72),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── 친구 추가 다이얼로그 ──────────────────────────────────────────────────────
class _AddFriendDialog extends StatefulWidget {
  final void Function(String uid, String name) onDm;

  const _AddFriendDialog({required this.onDm});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _searching = false;
  Map<String, dynamic>? _result;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final phone = _controller.text.trim();
    if (phone.isEmpty) return;
    setState(() {
      _searching = true;
      _result = null;
      _error = '';
    });

    final friendService = context.read<FriendService>();
    final found = await friendService.searchByPhone(phone);

    if (!mounted) return;
    if (found == null) {
      setState(() {
        _error = AppLocalizations.of(context).userNotFound;
        _searching = false;
      });
      return;
    }

    final alreadyFriend = await friendService.isFriend(found['uid']);
    if (!mounted) return;
    setState(() {
      _result = {...found, 'already_friend': alreadyFriend};
      _searching = false;
    });
  }

  Future<void> _addFriend() async {
    if (_result == null) return;
    final l = AppLocalizations.of(context);
    final friendService = context.read<FriendService>();
    final userProvider = context.read<UserProvider>();
    final myName = userProvider.name;
    final myPhone = userProvider.phoneNumber;
    final success = await friendService.addFriend(
      _result!['uid'] as String,
      _result!['name'] as String? ?? l.unknown,
      myName: myName,
      myPhoneNumber: myPhone,
      myProfileImage: userProvider.photoUrl ?? '',
      friendPhoneNumber: _result!['phone_number'] as String? ?? '',
      friendProfileImage: _result!['profile_image'] as String? ?? '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              success ? l.friendAdded : l.friendAddFailed)),
    );
    if (success) {
      setState(
          () => _result = {..._result!, 'already_friend': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.person_search_outlined,
                    color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(l.addFriend,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l.searchByPhone,
                      prefixIcon:
                          const Icon(Icons.phone_outlined),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  size: 18),
                              onPressed: () => setState(() {
                                _controller.clear();
                                _result = null;
                                _error = '';
                              }),
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.search, size: 20),
                ),
              ],
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 14,
                      color:
                          colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 6),
                  Text(_error,
                      style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface
                              .withOpacity(0.5))),
                ],
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildResultTile(colorScheme, l),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(
      ColorScheme colorScheme, AppLocalizations l) {
    final name = _result!['name'] as String? ?? l.unknown;
    final photoUrl =
        _result!['profile_image'] as String? ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    final alreadyFriend =
        _result!['already_friend'] as bool? ?? false;
    final uid = _result!['uid'] as String;

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: hasPhoto
            ? CachedNetworkImageProvider(photoUrl)
            : null,
          onBackgroundImageError: hasPhoto ? (_, __) {} : null,
          child: hasPhoto
              ? null
              : Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600)),
              if (alreadyFriend)
                Text(l.alreadyFriend,
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary)),
            ],
          ),
        ),
        if (alreadyFriend)
          IconButton(
            icon: Icon(Icons.chat_bubble_outline,
                color: colorScheme.primary),
            onPressed: () => widget.onDm(uid, name),
          )
        else
          FilledButton.icon(
            onPressed: _addFriend,
            icon: const Icon(Icons.person_add, size: 16),
            label: Text(l.addFriend),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
            ),
          ),
      ],
    );
  }
}