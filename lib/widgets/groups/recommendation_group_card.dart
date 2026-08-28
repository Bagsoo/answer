import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/group_settings/group_avatar_widget.dart';
import '../../screens/group_tabs/group_type_category_data.dart';

class RecommendationGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isJoined;
  final VoidCallback onTap;
  final List<String> chips;
  final double? width;

  const RecommendationGroupCard({
    super.key,
    required this.group,
    required this.isJoined,
    required this.onTap,
    this.chips = const [],
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final name = group['name'] as String? ?? l.unknown;
    final type = group['type'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final imageUrl = group['group_profile_image'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 0;
    final distanceKm = group['distance_km'] as String?;
    final content = Material(
      color: cs.surfaceContainerLow,
      elevation: 0,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surfaceContainerLow,
                cs.surfaceContainerHighest.withOpacity(0.35),
              ],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GroupAvatarSync(
                    groupName: name,
                    imageUrl: imageUrl,
                    radius: 24,
                    fallbackIcon: Icons.groups,
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isJoined)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  l.alreadyJoined,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l.type}: ${GroupTypeCategoryData.localizeType(type, l)}  •  ${l.category}: ${GroupTypeCategoryData.localizeKey(category, l)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (distanceKm != null)
                    _InfoChip(
                      icon: Icons.place_outlined,
                      label: '$distanceKm km',
                      color: cs.secondaryContainer,
                      foreground: cs.onSecondaryContainer,
                    ),
                  _InfoChip(
                    icon: Icons.people_outline,
                    label: '$memberCount',
                    color: cs.surfaceContainerHighest,
                    foreground: cs.onSurface,
                  ),
                ],
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chips
                      .take(2)
                      .map(
                        (chip) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            chip,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (width == null) {
      return content;
    }

    return SizedBox(width: width, child: content);
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
