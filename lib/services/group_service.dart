import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ── 그룹 생성 ──────────────────────────────────────────────────────────────
  Future<String?> createGroup({
    required String name,
    required String type,
    required String category,
    required bool requireApproval,
    required String displayName,
    String profileImage = '',
    int memberLimit = 50,
    String plan = 'free',
    bool allowPlanUpgrade = true,
    GeoPoint? location,
    String locationName = '',
  }) async {
    if (currentUserId.isEmpty) return null;

    final batch = _db.batch();
    final groupDoc = _db.collection('groups').doc();

    List<String> keywords = name.toLowerCase().split(' ');
    keywords.add(name.toLowerCase());

    batch.set(groupDoc, {
      'name': name,
      'type': type,
      'category': category,
      'require_approval': requireApproval,
      'owner_id': currentUserId,
      'member_count': 1,
      'member_limit': memberLimit,
      'plan': plan,
      'invite_token': null,
      'qr_enabled': false,
      'allow_plan_upgrade': allowPlanUpgrade,
      'created_at': FieldValue.serverTimestamp(),
      'searchable_keywords': keywords,
    });

    batch.set(groupDoc.collection('members').doc(currentUserId), {
      'user_id': currentUserId,
      'display_name': displayName,
      'profile_image': profileImage,   // ← 추가
      'joined_at': FieldValue.serverTimestamp(),
      'role': 'owner',
      'permissions': {
        'can_post_schedule': true,
        'can_create_sub_chat': true,
        'can_write_post': true,
        'can_edit_group_info': true,
        'can_manage_permissions': true,
      },
    });

    batch.set(
      _db
          .collection('users')
          .doc(currentUserId)
          .collection('joined_groups')
          .doc(groupDoc.id),
      {
        'joined_at': FieldValue.serverTimestamp(),
        'name': name,
        'type': type,
        'category': category,
        'member_count': 1,
      },
    );

    final chatDoc = _db.collection('chat_rooms').doc();
    batch.set(chatDoc, {
      'type': 'group_all',
      'ref_group_id': groupDoc.id,
      'group_name': name,
      'group_profile_image': profileImage,
      'name': '$name 전체 채팅',
      'member_ids': [currentUserId],
      'last_message': '채팅방이 생성되었습니다.',
      'last_time': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'unread_counts': {currentUserId: 0},
    });

    batch.set(chatDoc.collection('room_members').doc(currentUserId), {
      'uid': currentUserId,
      'display_name': displayName,
      'role': 'owner',
      'joined_at': FieldValue.serverTimestamp(),
      'last_read_time': FieldValue.serverTimestamp(),
      'unread_cnt': 0,
    });

    try {
      await batch.commit();
      return groupDoc.id;
    } catch (e) {
      debugPrint('Error creating group: $e');
      return null;
    }
  }

  // ── 그룹 검색 ──────────────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> searchGroups(String query) {
    if (query.trim().isEmpty) return Stream.value([]);
    final lowerQuery = query.toLowerCase();
    return _db
        .collection('groups')
        .where('searchable_keywords', arrayContains: lowerQuery)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // ── 그룹 가입 요청 ──────────────────────────────────────────────────────────
  Future<String> requestToJoin(
    String groupId,
    bool requireApproval,
    String groupName,
    String groupType,
    String groupCategory,
    int currentMemberCount,
    String displayName,
    String phoneNumber,
    String profileImage,   // ← 추가
  ) async {
    if (currentUserId.isEmpty) return 'error';

    try {
      final bannedDoc = await _db
          .collection('groups')
          .doc(groupId)
          .collection('banned')
          .doc(currentUserId)
          .get();
      if (bannedDoc.exists) return 'banned';

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      final memberLimit = groupData?['member_limit'] as int? ?? 50;
      final memberCount =
          groupData?['member_count'] as int? ?? currentMemberCount;

      if (memberCount >= memberLimit) return 'full';

      if (requireApproval) {
        // 가입 요청에 profile_image 포함
        await _db
            .collection('groups')
            .doc(groupId)
            .collection('join_requests')
            .doc(currentUserId)
            .set({
          'user_id': currentUserId,
          'display_name': displayName,
          'phone_number': phoneNumber,
          'profile_image': profileImage,   // ← 추가
          'requested_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      } else {
        final batch = _db.batch();

        batch.set(
          _db
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(currentUserId),
          {
            'user_id': currentUserId,
            'display_name': displayName,
            'profile_image': profileImage,   // ← 추가
            'joined_at': FieldValue.serverTimestamp(),
            'role': 'member',
            'permissions': {
              'can_post_schedule': false,
              'can_create_sub_chat': false,
              'can_write_post': true,
              'can_edit_group_info': false,
              'can_manage_permissions': false,
            },
          },
        );

        batch.update(_db.collection('groups').doc(groupId), {
          'member_count': FieldValue.increment(1),
        });

        batch.set(
          _db
              .collection('users')
              .doc(currentUserId)
              .collection('joined_groups')
              .doc(groupId),
          {
            'joined_at': FieldValue.serverTimestamp(),
            'name': groupName,
            'type': groupType,
            'category': groupCategory,
            'member_count': currentMemberCount + 1,
          },
        );

        final chatRoomsSnapshot = await _db
            .collection('chat_rooms')
            .where('ref_group_id', isEqualTo: groupId)
            .where('type', isEqualTo: 'group_all')
            .limit(1)
            .get();

        if (chatRoomsSnapshot.docs.isNotEmpty) {
          final chatId = chatRoomsSnapshot.docs.first.id;
          batch.update(_db.collection('chat_rooms').doc(chatId), {
            'member_ids': FieldValue.arrayUnion([currentUserId]),
            'unread_counts.$currentUserId': 0,
          });
          batch.set(
            _db
                .collection('chat_rooms')
                .doc(chatId)
                .collection('room_members')
                .doc(currentUserId),
            {
              'uid': currentUserId,
              'display_name': displayName,
              'role': 'member',
              'joined_at': FieldValue.serverTimestamp(),
              'last_read_time': FieldValue.serverTimestamp(),
              'unread_cnt': 0,
            },
          );
        }

        await batch.commit();
      }
      return 'ok';
    } catch (e) {
      debugPrint('Error requesting to join group: $e');
      return 'error';
    }
  }

  // ── 내 가입 그룹 목록 ──────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getMyJoinedGroups() {
    if (currentUserId.isEmpty) return Stream.value([]);
    return _db
        .collection('users')
        .doc(currentUserId)
        .collection('joined_groups')
        .snapshots()
        .switchMap((snapshot) {
      final ids = snapshot.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return Stream.value([]);
      return _db
          .collection('groups')
          .where(FieldPath.documentId, whereIn: ids)
          .snapshots()
          .map((groupsSnap) => groupsSnap.docs.map((doc) {
                final data = doc.data();
                data['id'] = doc.id;
                return data;
              }).toList());
    });
  }

  // ── 가입 요청 대기 목록 ────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getPendingJoinRequests(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('join_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final docs = snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      docs.sort((a, b) {
        final aTs = a['requested_at'] as Timestamp?;
        final bTs = b['requested_at'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return aTs.compareTo(bTs);
      });
      return docs;
    });
  }

  // ── 가입 승인 ──────────────────────────────────────────────────────────────
  Future<String> approveJoinRequest(
      String groupId, String applicantUid) async {
    try {
      final bannedDoc = await _db
          .collection('groups')
          .doc(groupId)
          .collection('banned')
          .doc(applicantUid)
          .get();
      if (bannedDoc.exists) {
        await _db
            .collection('groups')
            .doc(groupId)
            .collection('join_requests')
            .doc(applicantUid)
            .delete();
        return 'banned';
      }

      final requestDoc = await _db
          .collection('groups')
          .doc(groupId)
          .collection('join_requests')
          .doc(applicantUid)
          .get();
      final requestData = requestDoc.data();
      if (requestData == null) return 'error';

      final displayName =
          requestData['display_name'] as String? ?? 'Unknown';
      // join_requests에 저장된 profile_image 사용
      final profileImage =
          requestData['profile_image'] as String? ?? '';

      final groupDoc =
          await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      final groupName = groupData?['name'] as String? ?? '';
      final groupType = groupData?['type'] as String? ?? 'club';
      final groupCategory = groupData?['category'] as String? ?? '';
      final memberCount = groupData?['member_count'] as int? ?? 0;
      final memberLimit = groupData?['member_limit'] as int? ?? 50;

      if (memberCount >= memberLimit) return 'full';

      final batch = _db.batch();

      // members에 추가 (profile_image 포함)
      batch.set(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(applicantUid),
        {
          'user_id': applicantUid,
          'display_name': displayName,
          'profile_image': profileImage,   // ← 추가
          'joined_at': FieldValue.serverTimestamp(),
          'role': 'member',
          'permissions': {
            'can_post_schedule': false,
            'can_create_sub_chat': false,
            'can_write_post': true,
            'can_edit_group_info': false,
            'can_manage_permissions': false,
          },
        },
      );

      batch.update(_db.collection('groups').doc(groupId), {
        'member_count': FieldValue.increment(1),
      });

      batch.set(
        _db
            .collection('users')
            .doc(applicantUid)
            .collection('joined_groups')
            .doc(groupId),
        {
          'joined_at': FieldValue.serverTimestamp(),
          'name': groupName,
          'type': groupType,
          'category': groupCategory,
          'member_count': memberCount + 1,
        },
      );

      batch.delete(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('join_requests')
            .doc(applicantUid),
      );

      final chatSnap = await _db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .where('type', isEqualTo: 'group_all')
          .limit(1)
          .get();

      if (chatSnap.docs.isNotEmpty) {
        final chatId = chatSnap.docs.first.id;
        batch.update(_db.collection('chat_rooms').doc(chatId), {
          'member_ids': FieldValue.arrayUnion([applicantUid]),
          'unread_counts.$applicantUid': 0,
        });
        batch.set(
          _db
              .collection('chat_rooms')
              .doc(chatId)
              .collection('room_members')
              .doc(applicantUid),
          {
            'uid': applicantUid,
            'display_name': displayName,
            'role': 'member',
            'joined_at': FieldValue.serverTimestamp(),
            'last_read_time': FieldValue.serverTimestamp(),
            'unread_cnt': 0,
          },
        );
      }

      await batch.commit();
      return 'ok';
    } catch (e) {
      debugPrint('approveJoinRequest error: $e');
      return 'error';
    }
  }

  // ── 가입 거절 ──────────────────────────────────────────────────────────────
  Future<bool> rejectJoinRequest(
      String groupId, String applicantUid) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('join_requests')
          .doc(applicantUid)
          .delete();
      return true;
    } catch (e) {
      debugPrint('rejectJoinRequest error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 태그 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<String>> getGroupTags(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((snap) =>
            List<String>.from(snap.data()?['tags'] as List? ?? []));
  }

  Future<bool> addGroupTag(String groupId, String tag) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'tags': FieldValue.arrayUnion([tag]),
      });
      return true;
    } catch (e) {
      debugPrint('addGroupTag error: $e');
      return false;
    }
  }

  Future<bool> removeGroupTag(String groupId, String tag) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'tags': FieldValue.arrayRemove([tag]),
      });
      return true;
    } catch (e) {
      debugPrint('removeGroupTag error: $e');
      return false;
    }
  }

  Future<bool> updateMemberTags(
      String groupId, String uid, List<String> tags) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .update({'tags': tags});
      return true;
    } catch (e) {
      debugPrint('updateMemberTags error: $e');
      return false;
    }
  }

  Stream<Map<String, dynamic>?> streamLatestGroupNotice(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('notices')
        .orderBy('created_at', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      data['id'] = snap.docs.first.id;
      return data;
    });
  }

  Stream<List<Map<String, dynamic>>> streamGroupNotices(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('notices')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<bool> createGroupNotice({
    required String groupId,
    required String text,
    required String authorName,
  }) async {
    if (currentUserId.isEmpty) return false;
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('notices')
          .add({
        'text': text.trim(),
        'author_uid': currentUserId,
        'author_name': authorName,
        'created_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('createGroupNotice error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 게시판 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getBoards(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('boards')
        .orderBy('order', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<bool> createBoard(
      String groupId, Map<String, dynamic> boardData) async {
    try {
      final db = FirebaseFirestore.instance;
      return await db.runTransaction((tx) async {
        final groupRef = db.collection('groups').doc(groupId);
        final boardsRef = groupRef.collection('boards');
        final groupDoc = await tx.get(groupRef);
        final data = groupDoc.data()!;
        final plan = data['plan'] ?? 'free';
        final boardCount = data['board_count'] ?? 0;
        int maxBoards;
        switch (plan) {
          case 'pro':
            maxBoards = 1000000;
            break;
          case 'plus':
            maxBoards = 5;
            break;
          default:
            maxBoards = 3;
        }
        if (boardCount >= maxBoards) throw Exception('limit_reached');
        final newBoardRef = boardsRef.doc();
        tx.set(newBoardRef, {
          ...boardData,
          'order': boardCount,
          'created_at': FieldValue.serverTimestamp(),
        });
        tx.update(groupRef, {'board_count': FieldValue.increment(1)});
        return true;
      });
    } catch (e) {
      debugPrint('createBoard error: $e');
      return false;
    }
  }

  Future<bool> updateBoard(
      String groupId, String boardId, Map<String, dynamic> data) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('boards')
          .doc(boardId)
          .update(data);
      return true;
    } catch (e) {
      debugPrint('updateBoard error: $e');
      return false;
    }
  }

  Future<bool> deleteBoard(String groupId, String boardId) async {
    try {
      final db = FirebaseFirestore.instance;
      final groupRef = db.collection('groups').doc(groupId);
      final boardRef = groupRef.collection('boards').doc(boardId);
      final postsSnap = await groupRef
          .collection('posts')
          .where('board_id', isEqualTo: boardId)
          .get();
      final batch = db.batch();
      for (final doc in postsSnap.docs) batch.delete(doc.reference);
      batch.delete(boardRef);
      batch.update(groupRef, {'board_count': FieldValue.increment(-1)});
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('deleteBoard error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 게시글 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getPosts(
      String groupId, String boardId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .where('board_id', isEqualTo: boardId)
        .orderBy('is_pinned', descending: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Stream<Map<String, dynamic>?> getPost(String groupId, String postId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final data = snap.data()!;
      data['id'] = snap.id;
      return data;
    });
  }

  Future<String?> createPost(
      String groupId, Map<String, dynamic> postData) async {
    try {
      final doc = await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .add({
        ...postData,
        'is_pinned': false,
        'reactions': {},
        'comment_count': 0,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('createPost error: $e');
      return null;
    }
  }

  Future<bool> updatePost(
      String groupId, String postId, Map<String, dynamic> data) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .update({...data, 'updated_at': FieldValue.serverTimestamp()});
      return true;
    } catch (e) {
      debugPrint('updatePost error: $e');
      return false;
    }
  }

  Future<bool> deletePost(String groupId, String postId) async {
    try {
      final commentsSnap = await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();
      final batch = _db.batch();
      for (final doc in commentsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('deletePost error: $e');
      return false;
    }
  }

  Future<bool> togglePinPost(
      String groupId, String postId, bool currentPin) async {
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .update({'is_pinned': !currentPin});
      return true;
    } catch (e) {
      debugPrint('togglePinPost error: $e');
      return false;
    }
  }

  Future<void> toggleReaction(
      String groupId, String postId, String emoji) async {
    final ref = _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId);
    final snap = await ref.get();
    final reactions = Map<String, dynamic>.from(
        snap.data()?['reactions'] as Map? ?? {});
    if (reactions[currentUserId] == emoji) {
      reactions.remove(currentUserId);
    } else {
      reactions[currentUserId] = emoji;
    }
    await ref.update({'reactions': reactions});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 댓글 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getComments(
      String groupId, String postId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  Future<bool> addComment(String groupId, String postId, String content,
      String authorName) async {
    try {
      final batch = _db.batch();
      final commentRef = _db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc();
      batch.set(commentRef, {
        'content': content,
        'author_id': currentUserId,
        'author_name': authorName,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('posts')
            .doc(postId),
        {'comment_count': FieldValue.increment(1)},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('addComment error: $e');
      return false;
    }
  }

  Future<bool> deleteComment(
      String groupId, String postId, String commentId) async {
    try {
      final batch = _db.batch();
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId));
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('posts')
            .doc(postId),
        {'comment_count': FieldValue.increment(-1)},
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('deleteComment error: $e');
      return false;
    }
  }

  // ── 그룹 프로필 사진 업데이트 ──────────────────────────────────────────────
  Future<void> updateGroupProfileImage({
    required String groupId,
    required String imageUrl,
  }) async {
    final batch = _db.batch();
    batch.update(
      _db.collection('groups').doc(groupId),
      {'group_profile_image': imageUrl},
    );

    final chatSnap = await _db
        .collection('chat_rooms')
        .where('ref_group_id', isEqualTo: groupId)
        .where('type', isEqualTo: 'group_all')
        .get();

    for (final chatDoc in chatSnap.docs) {
      batch.update(chatDoc.reference, {'group_profile_image': imageUrl});
    }

    await batch.commit();
  }

  // ── 방장 위임 ──────────────────────────────────────────────────────────────
  Future<bool> transferOwnership(
      String groupId, String newOwnerUid) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(newOwnerUid),
        {
          'role': 'owner',
          'permissions': {
            'can_post_schedule': true,
            'can_create_sub_chat': true,
            'can_write_post': true,
            'can_edit_group_info': true,
            'can_manage_permissions': true,
          },
        },
      );
      batch.update(
        _db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(currentUserId),
        {'role': 'member'},
      );
      batch.update(
          _db.collection('groups').doc(groupId), {'owner_id': newOwnerUid});

      final chatSnap = await _db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .where('type', isEqualTo: 'group_all')
          .get();
      for (final chatDoc in chatSnap.docs) {
        final chatId = chatDoc.id;
        batch.update(
          _db
              .collection('chat_rooms')
              .doc(chatId)
              .collection('room_members')
              .doc(newOwnerUid),
          {'role': 'owner'},
        );
        batch.update(
          _db
              .collection('chat_rooms')
              .doc(chatId)
              .collection('room_members')
              .doc(currentUserId),
          {'role': 'member'},
        );
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('transferOwnership error: $e');
      return false;
    }
  }

  // ── 멤버 추방 ──────────────────────────────────────────────────────────────
  Future<bool> kickMember(String groupId, String targetUid,
      {bool ban = false, String displayName = ''}) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(targetUid));
      batch.update(_db.collection('groups').doc(groupId),
          {'member_count': FieldValue.increment(-1)});
      batch.delete(_db
          .collection('users')
          .doc(targetUid)
          .collection('joined_groups')
          .doc(groupId));

      if (ban) {
        batch.set(
          _db
              .collection('groups')
              .doc(groupId)
              .collection('banned')
              .doc(targetUid),
          {
            'display_name': displayName,
            'banned_at': FieldValue.serverTimestamp(),
            'banned_by': currentUserId,
          },
        );
      }

      final chatSnap = await _db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .get();
      for (final chatDoc in chatSnap.docs) {
        final chatId = chatDoc.id;
        final memberIds = List<String>.from(
            chatDoc.data()['member_ids'] as List? ?? []);
        memberIds.remove(targetUid);
        batch.update(_db.collection('chat_rooms').doc(chatId),
            {'member_ids': memberIds});
        batch.delete(_db
            .collection('chat_rooms')
            .doc(chatId)
            .collection('room_members')
            .doc(targetUid));
      }
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('kickMember error: $e');
      return false;
    }
  }

  // ── 차단 해제 ──────────────────────────────────────────────────────────────
  Future<void> unbanMember(String groupId, String targetUid) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .doc(targetUid)
        .delete();
  }

  Stream<QuerySnapshot> bannedMembersStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .snapshots();
  }

  Future<bool> isBanned(String groupId, String uid) async {
    final doc = await _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .doc(uid)
        .get();
    return doc.exists;
  }

  Future<void> updateGroupLocation({
    required String groupId,
    required double lat,
    required double lng,
    required String locationName,
  }) async {
    await _db.collection('groups').doc(groupId).update({
      'location': GeoPoint(lat, lng),
      'location_name': locationName,
    });
  }
}
