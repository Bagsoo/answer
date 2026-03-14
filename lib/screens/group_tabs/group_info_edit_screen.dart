import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'group_type_category_data.dart';

/// 그룹 유형 & 카테고리 수정 화면
class GroupInfoEditScreen extends StatefulWidget {
  final String groupId;
  final String currentType;
  final String currentCategory;
  final String currentName;
  final bool canEditInfo; // can_edit_group_info

  const GroupInfoEditScreen({
    super.key,
    required this.groupId,
    required this.currentType,
    required this.currentCategory,
    required this.currentName,
    required this.canEditInfo,
  });

  @override
  State<GroupInfoEditScreen> createState() => _GroupInfoEditScreenState();
}

class _GroupInfoEditScreenState extends State<GroupInfoEditScreen> {
  late AppLocalizations l;
  late String _selectedType;
  late String _selectedCategory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentType;
    _selectedCategory = widget.currentCategory;
  }

  List<String> get _categories =>
      GroupTypeCategoryData.getCategoriesForType(_selectedType, l);

  // 타입 변경 시 카테고리 초기화
  void _onTypeChanged(String type) {
    setState(() {
      _selectedType = type;
      final cats = GroupTypeCategoryData.getCategoriesForType(type, l);
      _selectedCategory = cats.contains(widget.currentCategory)
          ? widget.currentCategory
          : cats.first;
    });
  }

  Future<void> _save(AppLocalizations l) async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .update({
      'type': _selectedType,
      'category': _selectedCategory,
    });
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.profileSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final typeKeys = GroupTypeCategoryData.typeKeys;

    String typeLabel(String key) {
      switch (key) {
        case 'company':     return l.groupTypeCompany;
        case 'club':        return l.groupTypeClub;
        case 'small_group': return l.groupTypeSmall;
        case 'academy':     return l.groupTypeAcademy;
        case 'school_class':return l.groupTypeClass;
        case 'hobby_club':  return l.groupTypeHobby;
        default:            return key;
      }
    }

    IconData typeIcon(String key) {
      switch (key) {
        case 'company':     return Icons.business;
        case 'club':        return Icons.groups;
        case 'small_group': return Icons.people;
        case 'academy':     return Icons.school;
        case 'school_class':return Icons.class_;
        case 'hobby_club':  return Icons.sports_esports;
        default:            return Icons.group;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.editTypeAndCategory),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(l),
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.save,
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 유형 선택 ──────────────────────────────────────────────
            Text(l.selectGroupType,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: typeKeys.length,
              itemBuilder: (context, i) {
                final key = typeKeys[i];
                final isSelected = _selectedType == key;
                return InkWell(
                  onTap: () => _onTypeChanged(key),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(typeIcon(key),
                            size: 20,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface.withOpacity(0.6)),
                        const SizedBox(width: 8),
                        Text(typeLabel(key),
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── 카테고리 선택 ──────────────────────────────────────────
            Text(l.selectCategory,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(l.selectCategoryDesc,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  selectedColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            // 현재 선택 요약
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeLabel(_selectedType),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_selectedCategory,
                          style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface.withOpacity(0.6))),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}