import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../screens/chat_room_screen.dart';
import '../../screens/board/board_post_detail_screen.dart';

/// 메모 소스(chat/board)로 이동하는 공통 로직.
/// [popFirst] — 바텀시트 등에서 호출 시 true, 타일에서 직접 호출 시 false.
Future<void> navigateToMemoSource(
  BuildContext context,
  Map<String, dynamic> data, {
  bool popFirst = false,
}) async {
  final source = data['source'] as String? ?? 'direct';
  if (source == 'direct') return;

  final navigator = Navigator.of(context, rootNavigator: true);

  if (source == 'chat') {
    final roomId = data['room_id'] as String?;
    final messageId = data['message_id'] as String?;
    if (roomId == null) return;
    if (popFirst) navigator.pop();
    navigator.push(MaterialPageRoute(
      builder: (_) =>
          ChatRoomScreen(roomId: roomId, initialScrollToMessageId: messageId),
    ));
  } else if (source == 'board') {
    final groupId = data['group_id'] as String?;
    final postId = data['post_id'] as String?;
    if (groupId == null || postId == null) return;
    if (popFirst) navigator.pop();
    await _navigateToBoard(navigator, data, groupId, postId);
  }
}

Future<void> _navigateToBoard(
  NavigatorState navigator,
  Map<String, dynamic> data,
  String groupId,
  String postId,
) async {
  final db = FirebaseFirestore.instance;
  final authUid = FirebaseAuth.instance.currentUser?.uid;
  if (authUid == null) return;

  final results = await Future.wait([
    db.collection('groups').doc(groupId).collection('members').doc(authUid).get(),
    db.collection('groups').doc(groupId).collection('posts').doc(postId).get(),
  ]);

  final myRole = (results[0].data())?['role'] as String? ?? 'member';
  final postData = results[1].data() as Map<String, dynamic>?;
  final boardId = postData?['board_id'] as String?;

  String writePermission = 'all';
  if (boardId != null) {
    final boardDoc = await db
        .collection('groups')
        .doc(groupId)
        .collection('boards')
        .doc(boardId)
        .get();
    writePermission =
        (boardDoc.data())?['write_permission'] as String? ?? 'all';
  }

  navigator.push(MaterialPageRoute(
    builder: (_) => BoardPostDetailScreen(
      groupId: groupId,
      groupName: data['group_name'] as String? ?? '',
      postId: postId,
      boardName: data['board_name'] as String? ?? '',
      boardType: data['board_type'] as String? ?? 'free',
      writePermission: writePermission,
      myRole: myRole,
    ),
  ));
}