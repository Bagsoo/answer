import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'group_detail_screen.dart';

class GroupPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupPreviewScreen({super.key, required this.group});

  @override
  State<GroupPreviewScreen> createState() => _GroupPreviewScreenState();
}

class _GroupPreviewScreenState extends State<GroupPreviewScreen> {
  bool _joining = false;

  Map<String, dynamic> get group => widget.group;

  Future<void> _onJoin() async {
    final l = AppLocalizations.of(context);
    final groupService = context.read<GroupService>();
    final userProvider = context.read<UserProvider>();

    final groupId = group['id'] as String;
    final groupName = group['name'] as String? ?? '';
    final groupType = group['type'] as String? ?? 'club';
    final groupCategory = group['category'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 0;
    final requireApproval = group['require_approval'] as bool? ?? false;

    setState(() => _joining = true);

    final result = await groupService.requestToJoin(
      groupId,
      requireApproval,
      groupName,
      groupType,
      groupCategory,
      memberCount,
      userProvider.name,
      userProvider.phoneNumber,
      userProvider.photoUrl ?? '',
    );

    if (!mounted) return;
    setState(() => _joining = false);

    if (result == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(requireApproval ? l.joinRequestSent : l.joinedSuccess),
        ),
      );
      if (!requireApproval && mounted) {
        // 가입 성공 시 그룹 상세로 이동
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(
            groupId: groupId,
            groupName: groupName,
          ),
        ));
      } else {
        Navigator.of(context).pop();
      }
    } else if (result == 'full') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.groupFull)));
    } else if (result == 'banned') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.bannedFromGroup)),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.joinFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final groupId = group['id'] as String? ?? '';
    final name = group['name'] as String? ?? '';
    final type = group['type'] as String? ?? '';
    final category = group['category'] as String? ?? '';
    final memberCount = (group['member_count'] as num?)?.toInt() ?? 0;
    final memberLimit = (group['member_limit'] as num?)?.toInt() ?? 50;
    final requireApproval = group['require_approval'] as bool? ?? false;
    final tags = List<String>.from(group['tags'] as List? ?? []);
    final likes = List<String>.from(group['likes'] as List? ?? []);
    final profileImageUrl = group['group_profile_image'] as String? ?? '';
    final hasImage = profileImageUrl.isNotEmpty;
    final plan = group['plan'] as String? ?? 'free';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── 그룹 프로필 사진 ──────────────────────────────────────────
            CircleAvatar(
              radius: 56,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage:
                  hasImage ? NetworkImage(profileImageUrl) : null,
              child: hasImage
                  ? null
                  : Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // ── 그룹명 ──────────────────────────────────────────────────
            Text(
              name,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // ── 플랜 뱃지 ─────────────────────────────────────────────
            if (plan != 'free')
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: plan == 'pro'
                      ? Colors.amber.withOpacity(0.15)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: plan == 'pro'
                        ? Colors.amber
                        : colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  plan.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: plan == 'pro'
                        ? Colors.amber[700]
                        : colorScheme.primary,
                  ),
                ),
              ),

            // ── 통계 Row ──────────────────────────────────────────────
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatChip(
                  icon: Icons.people_outline,
                  label: '$memberCount / $memberLimit',
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: Icons.favorite,
                  label: '${likes.length}',
                  color: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 타입 / 카테고리 ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _InfoRow(
                      label: l.type, value: type, colorScheme: colorScheme),
                  const SizedBox(height: 8),
                  _InfoRow(
                      label: l.category,
                      value: category,
                      colorScheme: colorScheme),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: l.joinMethod,
                    value: requireApproval
                        ? l.requiresApproval
                        : l.freeJoin,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
            ),

            // ── 태그 ─────────────────────────────────────────────────
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tags
                      .map((tag) => Chip(
                            label: Text('#$tag',
                                style: const TextStyle(fontSize: 12)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── 가입 버튼 ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _joining ? null : _onJoin,
                icon: _joining
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(requireApproval
                        ? Icons.how_to_reg_outlined
                        : Icons.group_add_outlined),
                label: Text(requireApproval ? l.requestJoin : l.joinNow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}