import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../services/friend_service.dart';

class AddFriendDialog extends StatefulWidget {
  final void Function(String uid, String name) onDm;

  const AddFriendDialog({super.key, required this.onDm});

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
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
    final success = await friendService.addFriend(
      _result!['uid'] as String,
      _result!['name'] as String? ?? l.unknown,
      myName: userProvider.name,
      myPhoneNumber: userProvider.phoneNumber,
      myProfileImage: userProvider.photoUrl ?? '',
      friendPhoneNumber: _result!['phone_number'] as String? ?? '',
      friendProfileImage: _result!['profile_image'] as String? ?? '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? l.friendAdded : l.friendAddFailed)),
    );
    if (success) {
      setState(() => _result = {..._result!, 'already_friend': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.person_search_outlined, color: colorScheme.primary),
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
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l.searchByPhone,
                      prefixIcon: const Icon(Icons.phone_outlined),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _controller.clear();
                                _result = null;
                                _error = '';
                              }),
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 20),
                ),
              ]),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
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
      ),
    );
  }

  Widget _buildResultTile(ColorScheme colorScheme, AppLocalizations l) {
    final name = _result!['name'] as String? ?? l.unknown;
    final photoUrl = _result!['profile_image'] as String? ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    final alreadyFriend = _result!['already_friend'] as bool? ?? false;
    final uid = _result!['uid'] as String;

    return Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage:
            hasPhoto ? CachedNetworkImageProvider(photoUrl) : null,
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
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (alreadyFriend)
              Text(l.alreadyFriend,
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.primary)),
          ],
        ),
      ),
      if (alreadyFriend)
        IconButton(
          icon: Icon(Icons.chat_bubble_outline, color: colorScheme.primary),
          onPressed: () => widget.onDm(uid, name),
        )
      else
        FilledButton.icon(
          onPressed: _addFriend,
          icon: const Icon(Icons.person_add, size: 16),
          label: Text(l.addFriend),
          style: FilledButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
    ]);
  }
}