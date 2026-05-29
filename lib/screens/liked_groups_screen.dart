import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/group_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/groups/group_tile.dart';
import 'group_preview_screen.dart';
import 'group_detail_screen.dart';

class LikedGroupsScreen extends StatelessWidget {
  const LikedGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return Scaffold(appBar: AppBar(title: Text(l.likedGroupsTitle)));

    return Scaffold(
      appBar: AppBar(title: Text(l.likedGroupsTitle)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: context.read<GroupService>().getMyLikedGroups(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final groups = snapshot.data!;

          if (groups.isEmpty) {
            return Center(child: Text(l.noGroupsJoined)); // Reusing 'no joined groups' message or add new localized string
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              return ExploreGroupTile(
                group: group,
                isAlreadyJoined: false, // Liked groups might not be joined
                onTap: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  final memberDoc = await FirebaseFirestore.instance
                      .collection('groups')
                      .doc(group['id'])
                      .collection('members')
                      .doc(uid)
                      .get();
                  if (memberDoc.exists) {
                    // 가입된 그룹이면 그룹디테일로 이동
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GroupDetailScreen(groupId: group['id'], groupName: group['name'],),
                    ));
                  } else {
                    // 가입 안 된 그룹이면 그룹프리뷰로 이동
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GroupPreviewScreen(group: group),
                    ));
                  }
                },
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
          );
        },
      ),
    );
  }
}
