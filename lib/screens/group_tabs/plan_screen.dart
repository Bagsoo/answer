import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:messenger/providers/group_provider.dart';
import 'package:messenger/l10n/app_localizations.dart';
import '../../services/purchase_service.dart';

class PlanScreen extends StatefulWidget {
  final String groupId;

  const PlanScreen({super.key, required this.groupId});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final GroupPurchaseService _purchaseService = GroupPurchaseService.instance;
  late Future<PurchaseCatalog> _catalogFuture;
  String? _purchasingProductId;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _purchaseService.loadCatalog();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final groupProvider = context.watch<GroupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageGroupPlan),
      ),
      body: FutureBuilder<PurchaseCatalog>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          final catalog = snapshot.data;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCurrentPlanCard(context, groupProvider, l),
                const SizedBox(height: 24),
                Text(
                  l.viewPlans,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildFreePlanItem(context, l, groupProvider),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ..._buildAllPlans(context, l, groupProvider, catalog),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFreePlanItem(
    BuildContext context,
    AppLocalizations l,
    GroupProvider groupProvider,
  ) {
    return _buildPlanItem(
      context,
      l,
      name: 'FREE',
      price: l.planFreePrice,
      description: l.freePlanDesc,
      features: [
        l.boardLimitText(3),
        l.chatLimitText(l.unlimited),
        l.memberLimitText(50),
      ],
      isCurrent: groupProvider.plan == 'free',
      buttonEnabled: false,
    );
  }

  Widget _buildStorePlanItem(
    BuildContext context,
    AppLocalizations l,
    GroupProvider groupProvider, {
    PurchaseCatalogItem? item,
    String? plan,
  }) {
    plan ??= _purchaseService.planForProduct(item!.logicalProductId);
    final isCurrent = groupProvider.plan == plan;
    final isYearly = item != null && _purchaseService.isYearlyProduct(item.logicalProductId);

    final features = plan == 'pro'
        ? <String>[
            l.boardLimitText(l.unlimited),
            l.chatLimitText(l.unlimited),
            l.memberLimitText(1000),
            l.advancedAdminTool,
          ]
        : <String>[
            l.boardLimitText(5),
            l.chatLimitText(l.unlimited),
            l.memberLimitText(300),
            l.prioritySupport,
          ];

    return _buildPlanItem(
      context,
      l,
      name: item?.title ?? (plan == 'pro' ? 'PRO Monthly' : 'PLUS Monthly'),
      price: item?.price ?? 'Unavailable',
      description: item == null 
          ? l.comingSoon
          : (item.description.trim().isEmpty
            ? (isYearly ? 'Yearly subscription' : 'Monthly subscription')
            : item.description.trim()),
      features: features,
      isCurrent: isCurrent,
      isPremium: plan == 'pro',
      buttonEnabled: item != null && _purchasingProductId != item.logicalProductId,
      buttonText: item == null 
          ? l.comingSoon
          : (_purchasingProductId == item.logicalProductId ? l.loading : l.selectPlan),
      onPressed: item != null ? () => _startPurchase(context, item) : null,
    );
  }

  List<Widget> _buildAllPlans(BuildContext context, AppLocalizations l, GroupProvider provider, PurchaseCatalog? catalog) {
    if (catalog != null && catalog.items.isNotEmpty) {
      return catalog.items.map((item) => _buildStorePlanItem(context, l, provider, item: item)).toList();
    }
    // Fallbacks if native products are not available
    return [
      _buildStorePlanItem(context, l, provider, plan: 'plus'),
      _buildStorePlanItem(context, l, provider, plan: 'pro'),
    ];
  }

  Future<void> _startPurchase(
    BuildContext context,
    PurchaseCatalogItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _purchasingProductId = item.logicalProductId);

    try {
      await _purchaseService.purchaseGroupPlan(
        groupId: widget.groupId,
        item: item,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Purchase completed successfully.')),
      );
      setState(() {
        _catalogFuture = _purchaseService.loadCatalog();
      });
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _purchasingProductId = null);
      }
    }
  }
}

extension on _PlanScreenState {
  Widget _buildCurrentPlanCard(
    BuildContext context,
    GroupProvider provider,
    AppLocalizations l,
  ) {
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
    bool buttonEnabled = true,
    String? buttonText,
    VoidCallback? onPressed,
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
                onPressed: buttonEnabled ? onPressed : null,
                child: Text(buttonText ?? (isCurrent ? l.active : l.selectPlan)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
