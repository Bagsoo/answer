import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/user_profile_detail_screen.dart';

class FriendTile extends StatelessWidget {
  final Map<String, dynamic> friend;

  const FriendTile({super.key, required this.friend});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final uid = friend['uid'] as String;
    final name = friend['display_name'] as String? ?? l.unknown;
    final photoUrl = friend['profile_image'] as String? ?? '';
    final hasPhoto = photoUrl.isNotEmpty;

    return ListTile(
      leading: CircleAvatar(
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
      title: Text(name,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileDetailScreen(
            uid: uid,
            displayName: name,
            photoUrl: photoUrl,
          ),
        ),
      ),
    );
  }
}