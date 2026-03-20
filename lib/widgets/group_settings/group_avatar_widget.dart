import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 그룹 프로필 사진 위젯
/// - groupId로 Firestore에서 group_profile_image를 가져와 표시
/// - 없으면 groupName 첫 글자 이니셜로 표시
/// - 정적 캐시로 중복 fetch 방지
class GroupAvatar extends StatelessWidget {
  final String groupId;
  final String groupName;
  final double radius;
  final IconData fallbackIcon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const GroupAvatar({
    super.key,
    required this.groupId,
    required this.groupName,
    this.radius = 20,
    this.fallbackIcon = Icons.group,
    this.backgroundColor,
    this.foregroundColor,
  });

  // 앱 세션 동안 유지되는 간단한 메모리 캐시
  static final Map<String, String> _cache = {};

  Future<String> _fetchImageUrl() async {
    if (_cache.containsKey(groupId)) return _cache[groupId]!;
    final doc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();
    final url = doc.data()?['group_profile_image'] as String? ?? '';
    _cache[groupId] = url;
    return url;
  }

  /// 외부에서 캐시 무효화 (프로필 사진 변경 시 호출)
  static void invalidateCache(String groupId) {
    _cache.remove(groupId);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = backgroundColor ?? colorScheme.primaryContainer;
    final fgColor = foregroundColor ?? colorScheme.onPrimaryContainer;

    return FutureBuilder<String>(
      future: _fetchImageUrl(),
      builder: (context, snap) {
        final url = snap.data ?? '';
        final hasImage = url.isNotEmpty;

        return CircleAvatar(
          radius: radius,
          backgroundColor: bgColor,
          backgroundImage: hasImage ? NetworkImage(url) : null,
          onBackgroundImageError: hasImage ? (_, __) {} : null,
          child: hasImage
              ? null
              : Icon(
                  fallbackIcon,
                  size: radius * 0.9,
                  color: fgColor,
                ),
        );
      },
    );
  }
}

/// 이미 imageUrl을 알고 있을 때 사용하는 동기 버전 (GroupListScreen 등)
class GroupAvatarSync extends StatelessWidget {
  final String groupName;
  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const GroupAvatarSync({
    super.key,
    required this.groupName,
    required this.imageUrl,
    this.radius = 20,
    this.fallbackIcon = Icons.group,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = backgroundColor ?? colorScheme.primaryContainer;
    final fgColor = foregroundColor ?? colorScheme.onPrimaryContainer;
    final hasImage = imageUrl.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
      onBackgroundImageError: hasImage ? (_, __) {} : null,
      child: hasImage
          ? null
          : Icon(
              fallbackIcon,
              size: radius * 0.9,
              color: fgColor,
            ),
    );
  }
}