import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/group_tabs/group_type_category_data.dart';
import '../../widgets/common/location_picker_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/env_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  final ImageService _imageService = ImageService();

  bool _isUploadingImage = false;
  bool _isSavingName = false;

  @override
  void initState() {
    super.initState();
    final name = context.read<UserProvider>().name;
    _nameController = TextEditingController(text: name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleImageUpdate(UserProvider userProvider) async {
    final File? compressedImage = await _imageService.pickAndCompressImage();
    if (compressedImage == null) return;
    setState(() => _isUploadingImage = true);
    try {
      await userProvider.updateProfileImage(compressedImage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 업로드에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _handleSaveName(
      AppLocalizations l, UserProvider userProvider) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == userProvider.name) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSavingName = true);
    try {
      await userProvider.updateName(newName);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.profileSaved)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingName = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.profileSaveFailed)));
      }
    }
  }

  // ── 활동 위치 선택 ────────────────────────────────────────────────────────
  Future<void> _pickLocation(UserProvider userProvider) async {
    final apiKey = EnvConfig.mapsApiKey;
    final locale = userProvider.locale;

    final result = await showModalBottomSheet<LocationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => LocationPickerSheet(
        googleApiKey: apiKey,
        languageCode: locale,
      ),
    );

    if (result != null && mounted) {
      await userProvider.updateActivityLocation(
        lat: result.latitude,
        lng: result.longitude,
        name: result.name,
      );
    }
  }

  // ── 관심사 선택 시트 ──────────────────────────────────────────────────────
  Future<void> _showInterestsPicker(
      UserProvider userProvider, AppLocalizations l) async {
    final cs = Theme.of(context).colorScheme;
    final current = Set<String>.from(userProvider.interests);

    // 모든 카테고리 키 수집
    final allKeys = <String>{};
    for (final keys in GroupTypeCategoryData.categoryKeys.values) {
      allKeys.addAll(keys);
    }
    // 타입 키도 추가
    allKeys.addAll(GroupTypeCategoryData.typeKeys);

    final selected = Set<String>.from(current);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(l.selectInterests,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await userProvider
                        .updateInterests(selected.toList());
                  },
                  child: Text(l.confirm,
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allKeys.map((key) {
                    final label =
                        GroupTypeCategoryData.localizeKey(key, l);
                    final isSelected = selected.contains(key);
                    return FilterChip(
                      label: Text(label,
                          style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? cs.primary
                                  : cs.onSurface)),
                      selected: isSelected,
                      onSelected: (v) => setSheet(() {
                        if (v) {
                          selected.add(key);
                        } else {
                          selected.remove(key);
                        }
                      }),
                      selectedColor: cs.primaryContainer,
                      checkmarkColor: cs.primary,
                      backgroundColor:
                          cs.surfaceContainerHighest.withOpacity(0.5),
                      side: BorderSide(
                        color: isSelected
                            ? cs.primary
                            : Colors.transparent,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final userProvider = context.watch<UserProvider>();
    final photoUrl = userProvider.photoUrl ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(l.editProfile),
        actions: [
          TextButton(
            onPressed: (_isSavingName || _isUploadingImage)
                ? null
                : () => _handleSaveName(l, userProvider),
            child: _isSavingName
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.save,
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            // ── 프로필 이미지 ────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _isUploadingImage
                    ? null
                    : () => _handleImageUpdate(userProvider),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage: photoUrl.isNotEmpty
                          ? CachedNetworkImageProvider(photoUrl)
                          : null,
                      child: photoUrl.isEmpty
                          ? Text(
                              userProvider.name.isNotEmpty
                                  ? userProvider.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimaryContainer),
                            )
                          : null,
                    ),
                    if (_isUploadingImage)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.black38,
                              shape: BoxShape.circle),
                          child: const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white)),
                        ),
                      ),
                    if (!_isUploadingImage)
                      Positioned(
                        bottom: 0, right: 0,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.primary,
                          child: const Icon(Icons.camera_alt,
                              size: 16, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 36),

            // ── 이름 ─────────────────────────────────────────────────
            TextField(
              controller: _nameController,
              enabled: !_isSavingName,
              decoration: InputDecoration(
                labelText: l.name,
                prefixIcon: const Icon(Icons.person_outline),
                counterText: '',
              ),
              maxLength: 20,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),

            // ── 전화번호 (읽기 전용) ──────────────────────────────────
            TextField(
              readOnly: true,
              controller:
                  TextEditingController(text: userProvider.phoneNumber),
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                prefixIcon: const Icon(Icons.phone_outlined),
                filled: true,
                fillColor:
                    cs.surfaceContainerHighest.withOpacity(0.5),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── 활동 지역 ─────────────────────────────────────────────
            Text(l.activityLocation,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickLocation(userProvider),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cs.outline.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.place_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userProvider.locationName.isNotEmpty
                          ? userProvider.locationName
                          : l.noLocationSet,
                      style: TextStyle(
                          color: userProvider.locationName.isNotEmpty
                              ? cs.onSurface
                              : cs.onSurface.withOpacity(0.4)),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: cs.onSurface.withOpacity(0.4)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text(l.activityLocationDesc,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5))),

            const SizedBox(height: 24),

            // ── 관심사 ───────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: Text(l.myInterests,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () =>
                    _showInterestsPicker(userProvider, l),
                child: Text(l.edit,
                    style: TextStyle(color: cs.primary)),
              ),
            ]),
            const SizedBox(height: 8),
            userProvider.interests.isEmpty
                ? Text(l.noInterestsSet,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.4)))
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: userProvider.interests.map((key) {
                      final label =
                          GroupTypeCategoryData.localizeKey(key, l);
                      return Chip(
                        label: Text(label,
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor:
                            cs.primaryContainer.withOpacity(0.6),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}