import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/group_provider.dart';
import '../screens/board/board_post_detail_screen.dart';
import '../screens/group_tabs/schedule_detail_screen.dart';

class SharedContentNavigator {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> openSharedPost(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final groupId = data['group_id'] as String? ?? '';
    final postId = data['post_id'] as String? ?? '';
    if (groupId.isEmpty || postId.isEmpty) {
      _showSnackBar(messenger, '게시글을 열 수 없습니다.');
      return;
    }

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _showSnackBar(messenger, '게시글을 열 수 없습니다.');
      return;
    }

    final results = await Future.wait([
      _db.collection('groups').doc(groupId).get(),
      _db.collection('groups').doc(groupId).collection('members').doc(uid).get(),
      _db.collection('groups').doc(groupId).collection('posts').doc(postId).get(),
    ]);

    final groupDoc = results[0];
    final memberDoc = results[1];
    final postDoc = results[2];

    if (!memberDoc.exists) {
      _showSnackBar(messenger, '가입된 그룹의 게시글만 볼 수 있습니다.');
      return;
    }
    if (!postDoc.exists) {
      _showSnackBar(messenger, '게시글을 찾을 수 없습니다.');
      return;
    }

    final post = postDoc.data() ?? {};
    final boardId = post['board_id'] as String? ?? data['board_id'] as String? ?? '';
    final boardDoc = boardId.isEmpty
        ? null
        : await _db
            .collection('groups')
            .doc(groupId)
            .collection('boards')
            .doc(boardId)
            .get();

    final boardData = boardDoc?.data() ?? {};
    final memberData = memberDoc.data() ?? {};

    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => BoardPostDetailScreen(
          groupId: groupId,
          groupName: groupDoc.data()?['name'] as String? ??
              data['group_name'] as String? ??
              '',
          postId: postId,
          boardName: boardData['name'] as String? ??
              data['board_name'] as String? ??
              '',
          boardType: boardData['type'] as String? ??
              data['board_type'] as String? ??
              'free',
          writePermission: boardData['write_permission'] as String? ?? 'all',
          myRole: memberData['role'] as String? ?? 'member',
        ),
      ),
    );
  }

  static Future<void> openSharedSchedule(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final groupId = data['group_id'] as String? ?? '';
    final scheduleId = data['schedule_id'] as String? ?? '';
    final uid = _auth.currentUser?.uid ?? '';
    if (groupId.isEmpty || scheduleId.isEmpty || uid.isEmpty) {
      _showSnackBar(messenger, '일정을 열 수 없습니다.');
      return;
    }

    final results = await Future.wait([
      _db.collection('groups').doc(groupId).collection('members').doc(uid).get(),
      _db.collection('groups').doc(groupId).collection('schedules').doc(scheduleId).get(),
    ]);

    final memberDoc = results[0];
    final scheduleDoc = results[1];

    if (!memberDoc.exists) {
      _showSnackBar(messenger, '가입된 그룹의 일정만 볼 수 있습니다.');
      return;
    }
    if (!scheduleDoc.exists) {
      _showSnackBar(messenger, '일정을 찾을 수 없습니다.');
      return;
    }

    final memberData = memberDoc.data() ?? {};
    final perms = Map<String, dynamic>.from(
      memberData['permissions'] as Map? ?? const {},
    );
    final scheduleData = scheduleDoc.data() ?? {};
    final canEdit = (memberData['role'] as String? ?? '') == 'owner' ||
        perms['can_post_schedule'] == true ||
        scheduleData['created_by'] == uid;

    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => GroupProvider(groupId),
          child: ScheduleDetailScreen(
            groupId: groupId,
            scheduleId: scheduleId,
            canEdit: canEdit,
          ),
        ),
      ),
    );
  }

  static void _showSnackBar(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
