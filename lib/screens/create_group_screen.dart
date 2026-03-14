import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'group_detail_screen.dart';
import 'group_tabs/group_type_category_data.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Step 1
  String? _selectedType;

  // Step 2
  String? _selectedCategory;

  // Step 3
  final TextEditingController _nameController = TextEditingController();
  bool _requireApproval = true;

  // Step 4
  String _plan = 'free';

  bool _isLoading = false;

  static const int _totalSteps = 4;

  List<Map<String, dynamic>> _typeOptions(AppLocalizations l) => [
        {'key': 'company', 'label': l.groupTypeCompany, 'icon': Icons.business},
        {'key': 'club', 'label': l.groupTypeClub, 'icon': Icons.groups},
        {'key': 'small_group', 'label': l.groupTypeSmall, 'icon': Icons.people},
        {'key': 'academy', 'label': l.groupTypeAcademy, 'icon': Icons.school},
        {'key': 'school_class', 'label': l.groupTypeClass, 'icon': Icons.class_},
        {'key': 'hobby_club', 'label': l.groupTypeHobby, 'icon': Icons.sports_esports},
      ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    }
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0: return _selectedType != null;
      case 1: return _selectedCategory != null;
      case 2: return _nameController.text.trim().isNotEmpty;
      case 3: return true;
      default: return false;
    }
  }

  Future<void> _createGroup(AppLocalizations l) async {
    setState(() => _isLoading = true);

    final groupService = context.read<GroupService>();
    final displayName = context.read<UserProvider>().name;

    // 표시 문자열 → 키로 역변환해서 저장
    final categoryKey = GroupTypeCategoryData.labelToKey(
            _selectedCategory!, _selectedType!, l) ??
        _selectedCategory!;

    final newGroupId = await groupService.createGroup(
      name: _nameController.text.trim(),
      type: _selectedType!,
      category: categoryKey,
      requireApproval: _requireApproval,
      displayName: displayName,
      memberLimit: 50, // 기본값 고정, 설정 탭에서 조정 가능
      plan: _plan,
    );

    if (!mounted) return;

    if (newGroupId != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupDetailScreen(
            groupId: newGroupId,
            groupName: _nameController.text.trim(),
          ),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.groupCreatedSuccess)),
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.groupCreateFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.createGroup),
        leading: _currentStep == 0
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _prevStep,
              ),
      ),
      body: Column(
        children: [
          // ── 스텝 인디케이터 ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: List.generate(_totalSteps, (i) {
                final isActive = i <= _currentStep;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i < _totalSteps - 1 ? 6 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_currentStep + 1} / $_totalSteps',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                Text(
                  _stepTitle(l),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // ── 페이지 콘텐츠 ───────────────────────────────────────
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1TypeSelect(l, colorScheme),
                _Step2CategorySelect(l, colorScheme),
                _Step3Settings(l, colorScheme),
                _Step4Plan(l, colorScheme),
              ],
            ),
          ),

          // ── 하단 버튼 ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !_canProceed || _isLoading
                      ? null
                      : _currentStep < _totalSteps - 1
                          ? _nextStep
                          : () => _createGroup(l),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          _currentStep < _totalSteps - 1
                              ? l.next
                              : l.createGroup,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle(AppLocalizations l) {
    switch (_currentStep) {
      case 0: return l.selectGroupType;
      case 1: return l.selectCategory;
      case 2: return l.groupSettings;
      case 3: return l.selectPlan;
      default: return '';
    }
  }

  // ── Step 1: 유형 선택 ────────────────────────────────────────────────────
  Widget _Step1TypeSelect(AppLocalizations l, ColorScheme colorScheme) {
    final types = _typeOptions(l);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.selectGroupTypeDesc,
              style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: types.length,
            itemBuilder: (context, i) {
              final type = types[i];
              final isSelected = _selectedType == type['key'];
              return InkWell(
                onTap: () => setState(() {
                  _selectedType = type['key'] as String;
                  // 유형 바꾸면 카테고리 초기화
                  _selectedCategory = null;
                }),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        type['icon'] as IconData,
                        size: 32,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        type['label'] as String,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Step 2: 카테고리 선택 (유형별) ──────────────────────────────────────
  Widget _Step2CategorySelect(AppLocalizations l, ColorScheme colorScheme) {
    // 선택된 유형에 맞는 카테고리 목록
    final categories = GroupTypeCategoryData.getCategoriesForType(
        _selectedType ?? 'club', l);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.selectCategoryDesc,
              style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 3: 설정 ────────────────────────────────────────────────────────
  Widget _Step3Settings(AppLocalizations l, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 그룹 이름
          TextField(
            controller: _nameController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.groupName,
              prefixIcon: const Icon(Icons.group_work_outlined),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 28),

          // 가입 승인
          Text(l.joinSettings,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest
                  .withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              title: Text(l.requireApproval),
              subtitle: Text(l.requireApprovalDesc,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.5))),
              value: _requireApproval,
              onChanged: (v) => setState(() => _requireApproval = v),
            ),
          ),
          const SizedBox(height: 24),

          // 인원수 안내 (슬라이더 대신)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.memberLimitPlanHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.75),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 4: 플랜 선택 ────────────────────────────────────────────────────
  Widget _Step4Plan(AppLocalizations l, ColorScheme colorScheme) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('_config')
          .doc('pricing')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final currency = data?['currency'] as String? ?? 'USD';
        final plusPrice =
            (data?['plus_monthly'] as num?)?.toDouble() ?? 5.0;
        final proPrice =
            (data?['pro_monthly'] as num?)?.toDouble() ?? 8.0;

        final symbol = switch (currency) {
          'USD' => '\$',
          'KRW' => '₩',
          'JPY' => '¥',
          'EUR' => '€',
          _ => currency,
        };

        String fmt(double p) {
          if (currency == 'KRW' || currency == 'JPY') {
            return '$symbol${p.toInt()}';
          }
          return p == p.truncateToDouble()
              ? '$symbol${p.toInt()}'
              : '$symbol$p';
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.selectPlanDesc,
                  style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: 20),

              // Free
              _PlanCard(
                title: l.planFree,
                price: l.planFreePrice,
                accentColor: colorScheme.primary,
                features: [
                  l.planFreeFeature1,
                  l.planFreeFeature2,
                  l.planFreeFeature3,
                  l.planFreeFeature4,
                ],
                isSelected: _plan == 'free',
                colorScheme: colorScheme,
                onTap: () => setState(() => _plan = 'free'),
              ),
              const SizedBox(height: 12),

              // Plus
              _PlanCard(
                title: l.planPlus,
                price: '${fmt(plusPrice)} / 월',
                accentColor: Colors.blue,
                features: [
                  l.planPlusFeature1,
                  l.planPlusFeature2,
                  l.planPlusFeature3,
                  l.planPlusFeature4,
                  l.planPlusFeature5,
                ],
                isSelected: _plan == 'plus',
                colorScheme: colorScheme,
                badge: l.comingSoon,
                badgeColor: Colors.blue,
                onTap: () => setState(() => _plan = 'plus'),
              ),
              const SizedBox(height: 12),

              // Pro
              _PlanCard(
                title: l.planPro,
                price: '${fmt(proPrice)} / 월',
                accentColor: Colors.deepPurple,
                features: [
                  l.planProFeature1,
                  l.planProFeature2,
                  l.planProFeature3,
                  l.planProFeature4,
                  l.planProFeature5,
                ],
                isSelected: _plan == 'pro',
                colorScheme: colorScheme,
                badge: l.comingSoon,
                badgeColor: Colors.deepPurple,
                onTap: () => setState(() => _plan = 'pro'),
              ),
              const SizedBox(height: 16),

              // 안내
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.planUpgradeComingSoon,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ── 플랜 카드 ──────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final Color accentColor;
  final List<String> features;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.accentColor,
    required this.features,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.08)
              : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? accentColor
                : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color:
                        isSelected ? accentColor : colorScheme.onSurface,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? colorScheme.tertiary)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: badgeColor ?? colorScheme.tertiary,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11,
                        color: badgeColor ?? colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle,
                      color: accentColor, size: 22),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? accentColor
                    : colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 12),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 15,
                          color: isSelected
                              ? accentColor
                              : colorScheme.onSurface.withOpacity(0.4)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}