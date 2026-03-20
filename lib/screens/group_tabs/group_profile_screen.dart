import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/image_service.dart';
import '../../services/storage_service.dart';
import '../../l10n/app_localizations.dart';

class GroupProfileScreen extends StatefulWidget {
  final String groupId;

  const GroupProfileScreen({super.key, required this.groupId});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final l = AppLocalizations.of(context)!;
    final file = await ImageService().pickAndCompressImage();
    if (file == null || !mounted) return;

    setState(() => _uploading = true);

    try {
      // Storage 업로드
      final url = await StorageService().uploadGroupProfileImage(
        groupId: widget.groupId,
        file: file,
      );

      // Firestore 업데이트
      await GroupService().updateGroupProfileImage(
        groupId: widget.groupId,
        imageUrl: url,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.groupProfileImageUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.groupProfileImageUpdateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteGroupProfileImage),
        content: Text(l.deleteGroupProfileConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    try {
      await GroupService().updateGroupProfileImage(
        groupId: widget.groupId,
        imageUrl: '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.groupProfileImageDeleted)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final gp = context.watch<GroupProvider>();
    final photoUrl = gp.profileImageUrl;
    final hasPhoto = photoUrl.isNotEmpty;
    final groupName = gp.name;
    final canEdit = gp.canEditGroupInfo;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.groupProfileImage),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── 프로필 사진 ─────────────────────────────────────────────
            Stack(
              children: [
                GestureDetector(
                  onTap: (_uploading || !canEdit) ? null : _pickAndUpload,
                  child: CircleAvatar(
                    radius: 72,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage:
                        hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            groupName.isNotEmpty
                                ? groupName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                ),
                // 카메라 아이콘 배지
                if (canEdit)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colorScheme.surface, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                // 업로드 중 오버레이
                if (_uploading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 32),

            // ── 버튼 ────────────────────────────────────────────────────
            if (canEdit) ...[
              FilledButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l.groupProfileImageUpdate),
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _removePhoto,
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  label: Text(l.deleteGroupProfileImage,
                      style: TextStyle(color: colorScheme.error)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.error),
                  ),
                ),
              ],
            ] else ...[
              Text(l.noPermissionToChangeGroupProfileImage, style: TextStyle( fontSize: 13, color: colorScheme.onSurface.withOpacity(0.4))),
            ]              
          ],
        ),
      ),
    );
  }
}