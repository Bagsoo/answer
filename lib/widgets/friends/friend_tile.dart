import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/user_profile_detail_screen.dart';

/// Windows 등 데스크톱에서 CachedNetworkImage의 디스크 캐시 경로가
/// 네이티브 크래시를 유발하는 환경이 있어, 모바일만 디스크 캐시 이미지를 쓴다.
ImageProvider? _friendAvatarImageProvider(String photoUrl) {
  if (photoUrl.isEmpty) return null;
  final useDiskCache = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (useDiskCache) {
    return CachedNetworkImageProvider(photoUrl);
  }
  // Windows: 네트워크 아바타 디코드를 건너뛰고 이니셜만 사용
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    return null;
  }
  return ResizeImage(
    NetworkImage(photoUrl),
    width: 128,
    height: 128,
    allowUpscaling: false,
  );
}

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
    final imageProvider =
        hasPhoto ? _friendAvatarImageProvider(photoUrl) : null;
    final showInitials = imageProvider == null;

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: imageProvider,
        onBackgroundImageError:
            imageProvider != null ? (_, __) {} : null,
        child: showInitials
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              )
            : null,
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