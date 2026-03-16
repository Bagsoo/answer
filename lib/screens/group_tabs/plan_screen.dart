import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:messenger/providers/group_provider.dart';
import 'package:messenger/l10n/app_localizations.dart';

class PlanScreen extends StatelessWidget {
  final String groupId;

  const PlanScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupProvider = context.watch<GroupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageGroupPlan),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 현재 플랜 정보 카드
            _buildCurrentPlanCard(context, groupProvider, l),
            const SizedBox(height: 24),
            
            Text(
              l.viewPlans,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            // FREE 플랜 ($0)
            _buildPlanItem(
              context,
              l,
              name: 'FREE',
              price: r'$0',
              description: l.freePlanDesc,
              features: [
                l.boardLimitText(3),
                l.chatLimitText(5),
                l.memberLimitText(50),
              ],
              isCurrent: groupProvider.plan == 'free',
            ),
            
            // PLUS 플랜 ($5)
            _buildPlanItem(
              context,
              l,
              name: 'PLUS',
              price: r'$5 / mo',
              description: l.plusPlanDesc,
              features: [
                l.boardLimitText(5),
                l.chatLimitText(10),
                l.memberLimitText(300),
                l.prioritySupport,
              ],
              isCurrent: groupProvider.plan == 'plus',
            ),
            
            // PRO 플랜 ($8)
            _buildPlanItem(
              context,
              l,
              name: 'PRO',
              price: r'$8 / mo',
              description: l.proPlanDesc,
              features: [
                l.boardLimitText(l.unlimited),
                l.chatLimitText(l.unlimited),
                l.memberLimitText(1000),
                l.advancedAdminTool,
              ],
              isCurrent: groupProvider.plan == 'pro',
              isPremium: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanCard(BuildContext context, GroupProvider provider, AppLocalizations l) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              radius: 24,
              child: Icon(Icons.star, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.currentPlan,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    provider.plan.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanItem(
    BuildContext context,
    AppLocalizations l, {
    required String name,
    required String price,
    required String description,
    required List<String> features,
    bool isCurrent = false,
    bool isPremium = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPremium 
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l.active,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
            ),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const Divider(height: 32),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(f),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCurrent ? null : () {
                  // TODO: 결제 로직 구현
                },
                child: Text(isCurrent ? l.active : l.selectPlan),
              ),
            ),
          ],
        ),
      ),
    );
  }
}