import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  final ImageService _imageService = ImageService();

  // 상태 분리 (UX 개선)
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

  /// 이미지 변경 핸들러
  Future<void> _handleImageUpdate(UserProvider userProvider) async {
    final File? compressedImage = await _imageService.pickAndCompressImage();
    if (compressedImage == null) return;

    setState(() => _isUploadingImage = true);
    try {
      await userProvider.updateProfileImage(compressedImage);
      // 알림 전파는 Cloud Functions에서 처리하도록 설계(권장)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("이미지 업로드에 실패했습니다.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  /// 이름 저장 핸들러
  Future<void> _handleSaveName(AppLocalizations l, UserProvider userProvider) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == userProvider.name) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSavingName = true);
    try {
      await userProvider.updateName(newName);
      // 이름 변경 전파도 Cloud Functions에서 수행 시 클라이언트 부하 0
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.profileSaved)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingName = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.profileSaveFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
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
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.save, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            
            // --- 프로필 이미지 섹션 ---
            GestureDetector(
              onTap: _isUploadingImage ? null : () => _handleImageUpdate(userProvider),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: colorScheme.primaryContainer,
                    // 캐시 방지를 위해 URL 끝에 쿼리 파라미터 추가
                    backgroundImage: photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: photoUrl.isEmpty
                        ? Text(
                            userProvider.name.isNotEmpty ? userProvider.name[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                          )
                        : null,
                  ),
                  // 이미지 업로드 중일 때의 오버레이 로딩
                  if (_isUploadingImage)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                  // 카메라 아이콘 (업로드 중이 아닐 때만 표시)
                  if (!_isUploadingImage)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.primary,
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 36),

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

            // 전화번호 필드 (읽기 전용)
            TextField(
              readOnly: true,
              controller: TextEditingController(text: userProvider.phoneNumber),
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                prefixIcon: const Icon(Icons.phone_outlined),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}