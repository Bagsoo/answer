import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/group_tabs/settlement_detail_screen.dart';

class SettlementBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final ColorScheme colorScheme;
  final bool isMe;

  const SettlementBubble({
    super.key,
    required this.data,
    required this.colorScheme,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = data['settlement_title'] as String? ?? '';
    final totalCost = data['settlement_total_cost'] as String? ?? '';
    final groupId = data['group_id'] as String? ?? '';
    final scheduleId = data['schedule_id'] as String?;
    final settlementId = data['settlement_id'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        if (groupId.isNotEmpty && settlementId.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettlementDetailScreen(
              groupId: groupId,
              settlementId: settlementId,
              groupName: data['group_name'] as String? ?? '',
            ),
          ));
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.createSettlement,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              l.settlementTotalCostValue(totalCost),
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () {
                  if (groupId.isNotEmpty && settlementId.isNotEmpty) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SettlementDetailScreen(
                        groupId: groupId,
                        settlementId: settlementId,
                        groupName: data['group_name'] as String? ?? '',
                      ),
                    ));
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.zero,
                ),
                child: Text(l.settlementDetail, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
