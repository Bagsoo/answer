import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/friend_service.dart';
import '../services/block_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'chat_room_screen.dart';

class UserProfileDetailScreen extends StatefulWidget {
  final String uid;
  final String displayName;
  final String? photoUrl;

  const UserProfileDetailScreen({
    super.key,
    required this.uid,
    required this.displayName,
    this.photoUrl,
  });

  @override
  State<UserProfileDetailScreen> createState() => _UserProfileDetailScreenState();
}

class _UserProfileDetailScreenState extends State<UserProfileDetailScreen> {
  bool _isFriend = false;
  bool _isBlocked = false;
  bool _loading = true;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isMe => widget.uid == _myUid;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final friendService = context.read<FriendService>();
    final blockService = context.read<BlockService>();
    final results = await Future.wait([
      friendService.isFriend(widget.uid),
      blockService.isBlocked(widget.uid),
    ]);
    if (mounted) {
      setState(() {
        _isFriend = results[0];
        _isBlocked = results[1];
        _loading = false;
      });
    }
  }

  // ── DM 보내기 ─────────────────────────────────────────────────────────────
  Future<void> _openDm() async {
    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    final roomId = await friendService.getOrCreateDmRoom(
      widget.uid, widget.displayName, myName: myName,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ChatRoomScreen(roomId: roomId),
    ));
  }

  // ── 친구 추가 ─────────────────────────────────────────────────────────────
  Future<void> _addFriend() async {
    final l = AppLocalizations.of(context);
    final friendService = context.read<FriendService>();
    final myName = context.read<UserProvider>().name;
    final success = await friendService.addFriend(
      widget.uid, widget.displayName, myName: myName,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? l.friendAdded : l.friendAddFailed)),
    );
    if (success) setState(() => _isFriend = true);
  }

  // ── 친구 삭제 ─────────────────────────────────────────────────────────────
  Future<void> _removeFriend() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFriend),
        content: Text('${widget.displayName}${l.removeFriendConfirm}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
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
    await context.read<FriendService>().removeFriend(widget.uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.friendRemoved)),
      );
      setState(() => _isFriend = false);
    }
  }

  // ── 차단 ─────────────────────────────────────────────────────────────────
  Future<void> _blockUser() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.blockUser),
        content: Text(l.blockUserConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
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

    await context.read<BlockService>().blockUser(widget.uid, widget.displayName);
    // 친구였으면 친구도 삭제
    if (_isFriend) {
      await context.read<FriendService>().removeFriend(widget.uid);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.blockUserDone)),
      );
      Navigator.of(context).pop(); // 차단 후 뒤로
    }
  }

  // ── 차단 해제 ─────────────────────────────────────────────────────────────
  Future<void> _unblockUser() async {
    final l = AppLocalizations.of(context);
    await context.read<BlockService>().unblockUser(widget.uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.unblockUserDone)),
      );
      setState(() => _isBlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final name = widget.displayName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';    

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isMe
              ? _buildMyProfile(colorScheme, l)
              : _buildOtherProfile(colorScheme, l, initial),
    );
  }

  // ── 내 프로필 (자기 자신을 탭했을 때) ────────────────────────────────────
  Widget _buildMyProfile(ColorScheme colorScheme, AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              widget.displayName.isNotEmpty
                  ? widget.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l.me,
              style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.5), fontSize: 13)),
        ],
      ),
    );
  }

  // ── 다른 유저 프로필 ───────────────────────────────────────────────────────
  Widget _buildOtherProfile(
      ColorScheme colorScheme, AppLocalizations l, String initial) {
    final hasPhoto = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 40),

          // ── 아바타 ──────────────────────────────────────────────────────
          CircleAvatar(
            radius: 52,
            backgroundColor: _isBlocked
                ? colorScheme.errorContainer
                : colorScheme.primaryContainer,
            backgroundImage: hasPhoto ? NetworkImage(widget.photoUrl!) : null,
            child: !hasPhoto ? 
            Text(
              initial,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: _isBlocked
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ) : null,
          ),
          const SizedBox(height: 16),

          // ── 이름 ────────────────────────────────────────────────────────
          Text(widget.displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),

          // ── 친구 뱃지 ────────────────────────────────────────────────────
          if (_isFriend)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l.alreadyFriend,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onPrimaryContainer),
              ),
            ),

          // ── 차단 상태 표시 ────────────────────────────────────────────────
          if (_isBlocked)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l.blockUser,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onErrorContainer),
              ),
            ),

          const SizedBox(height: 36),

          // ── 액션 버튼들 ──────────────────────────────────────────────────
          if (!_isBlocked) ...[
            // DM 보내기
            _ActionButton(
              icon: Icons.chat_bubble_outline,
              label: l.sendDm,
              color: colorScheme.primary,
              onTap: _openDm,
            ),
            const Divider(indent: 16, endIndent: 16, height: 1),

            // 친구 추가 (친구 아닐 때만)
            if (!_isFriend) ...[
              _ActionButton(
                icon: Icons.person_add_outlined,
                label: l.addFriend,
                color: colorScheme.primary,
                onTap: _addFriend,
              ),
              const Divider(indent: 16, endIndent: 16, height: 1),
            ],

            // 친구 삭제 (친구일 때만)
            if (_isFriend) ...[
              _ActionButton(
                icon: Icons.person_remove_outlined,
                label: l.removeFriend,
                color: colorScheme.error.withOpacity(0.8),
                onTap: _removeFriend,
              ),
              const Divider(indent: 16, endIndent: 16, height: 1),
            ],
          ],

          // 차단하기 / 차단 해제
          _ActionButton(
            icon: _isBlocked ? Icons.lock_open_outlined : Icons.block_outlined,
            label: _isBlocked ? l.unblockUser : l.blockUser,
            color: _isBlocked
                ? colorScheme.primary
                : colorScheme.error,
            onTap: _isBlocked ? _unblockUser : _blockUser,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── 액션 버튼 타일 ────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}