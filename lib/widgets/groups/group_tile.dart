import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/group_settings/group_avatar_widget.dart';
import '../../screens/group_detail_screen.dart';
import '../../screens/group_preview_screen.dart';
import '../../screens/group_tabs/group_type_category_data.dart';

// ── 가입된 그룹 타일 ───────────────────────────────────────────────────────────
class JoinedGroupTile extends StatelessWidget {
  final Map<String, dynamic> group;

  const JoinedGroupTile({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupId = group['id'] as String? ?? '';
    final name = group['name'] as String? ?? l.unknown;
    final type = group['type'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 1;
    final imageUrl = group['group_profile_image'] as String? ?? '';

    final typeLabel = GroupTypeCategoryData.localizeType(type, l);
    final categoryLabel = GroupTypeCategoryData.localizeKey(category, l);

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
        _MemberBadge(count: memberCount, color: colorScheme.primaryContainer),
      ]),
      subtitle: Text('${l.type}: $typeLabel  •  ${l.category}: $categoryLabel'),
      trailing: Icon(Icons.chevron_right,
          color: colorScheme.onSurface.withOpacity(0.4)),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupDetailScreen(groupId: groupId, groupName: name),
      )),
    );
  }
}

// ── 검색 결과 그룹 타일 ────────────────────────────────────────────────────────
class DiscoverGroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isAlreadyJoined;
  final VoidCallback onJoinPressed;

  const DiscoverGroupTile({
    super.key,
    required this.group,
    required this.isAlreadyJoined,
    required this.onJoinPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final name = group['name'] as String? ?? l.unknown;
    final type = group['type'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 1;
    final requireApproval = group['require_approval'] as bool? ?? false;
    final imageUrl = group['group_profile_image'] as String? ?? '';
    final likes = List<String>.from(group['likes'] as List? ?? []);

    final typeLabel = GroupTypeCategoryData.localizeType(type, l);
    final categoryLabel = GroupTypeCategoryData.localizeKey(category, l);

    return ListTile(
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
        _MemberBadge(
            count: memberCount,
            color: colorScheme.surfaceContainerHighest),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${l.type}: $typeLabel  •  ${l.category}: $categoryLabel'),
          if (likes.isNotEmpty)
            Row(children: [
              Icon(Icons.favorite,
                  size: 12, color: Colors.red.withOpacity(0.7)),
              const SizedBox(width: 3),
              Text('${likes.length}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.withOpacity(0.7))),
            ]),
        ],
      ),
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle,
                    size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(l.alreadyJoined,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary)),
              ]),
            )
          : ElevatedButton(
              onPressed: onJoinPressed,
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
      onTap: () {
        if (isAlreadyJoined) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupDetailScreen(
              groupId: group['id'] as String,
              groupName: name,
            ),
          ));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupPreviewScreen(group: group),
          ));
        }
      },
    );
  }
}

// ── 멤버 수 뱃지 ──────────────────────────────────────────────────────────────
class _MemberBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _MemberBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
          style:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}