import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // UserProvider에서 바로 읽음 — Firestore 조회 없음
    final name = context.read<UserProvider>().name;
    _nameController = TextEditingController(text: name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save(AppLocalizations l, UserProvider userProvider) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == userProvider.name) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);

    try {
      // UserProvider.updateName → Firestore 업데이트 + 로컬 상태 동기화
      await userProvider.updateName(newName);

      // 친구들의 display_name 일괄 업데이트
      final db = FirebaseFirestore.instance;
      final myFriends = await db
          .collection('users')
          .doc(userProvider.uid)
          .collection('friends')
          .get();

      if (myFriends.docs.isNotEmpty) {
        final batch = db.batch();
        for (final friendDoc in myFriends.docs) {
          batch.update(
            db.collection('users').doc(friendDoc.id)
                .collection('friends').doc(userProvider.uid),
            {'display_name': newName},
          );
        }
        await batch.commit();
      }

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.profileSaved)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.profileSaveFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final userProvider = context.watch<UserProvider>();
    final currentName = userProvider.name;
    final phoneNumber = userProvider.phoneNumber;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.editProfile),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(l, userProvider),
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.save,
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            CircleAvatar(
              radius: 52,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                currentName.isNotEmpty ? currentName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),

            const SizedBox(height: 36),

            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l.name,
                prefixIcon: const Icon(Icons.person_outline),
                counterText: '',
              ),
              maxLength: 20,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(l, userProvider),
            ),

            const SizedBox(height: 16),

            TextField(
              readOnly: true,
              controller: TextEditingController(text: phoneNumber),
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                prefixIcon: const Icon(Icons.phone_outlined),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.lock_outline,
                    size: 13,
                    color: colorScheme.onSurface.withOpacity(0.4)),
                const SizedBox(width: 4),
                Text(
                  l.phoneNumberCannotChange,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
              ],
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _save(l, userProvider),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}