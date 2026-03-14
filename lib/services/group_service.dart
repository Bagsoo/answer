import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // 1. Create a New Group
  Future<String?> createGroup({
    required String name,
    required String type,
    required String category,
    required bool requireApproval,
    required String displayName,   // UserProvider에서 전달
    int memberLimit = 100,
    String plan = 'free',
    bool allowPlanUpgrade = true,
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
      'allow_plan_upgrade': allowPlanUpgrade,
      'created_at': FieldValue.serverTimestamp(),
      'searchable_keywords': keywords,
    });

    // Add creator as member with 'owner' role
    final memberDoc = groupDoc.collection('members').doc(currentUserId);
    batch.set(memberDoc, {
      'user_id': currentUserId,
      'display_name': displayName, // ✅ 추가
      'joined_at': FieldValue.serverTimestamp(),
      'role': 'owner',
      'permissions': {
        'can_post_schedule': true,
        'can_create_sub_chat': true,
        'can_write_post': true,
        'can_edit_group_info': true,
        'can_manage_permissions': true,
      }
    });

    // Update user's joined_groups subcollection
    final userJoinedGroupDoc = _db
        .collection('users')
        .doc(currentUserId)
        .collection('joined_groups')
        .doc(groupDoc.id);
    batch.set(userJoinedGroupDoc, {
      'joined_at': FieldValue.serverTimestamp(),
      'name': name,
      'type': type,
      'category': category,
      'member_count': 1,
    });

    // Auto-generate the ALL Chat Room
    final chatDoc = _db.collection('chat_rooms').doc();
    batch.set(chatDoc, {
      'type': 'group_all',
      'ref_group_id': groupDoc.id,
      'group_name': name,
      'name': '$name 전체 채팅',
      'member_ids': [currentUserId],
      'last_message': '채팅방이 생성되었습니다.',
      'last_time': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'unread_counts': {currentUserId: 0},
    });

    // Add owner to room_members
    final roomMemberDoc = chatDoc.collection('room_members').doc(currentUserId);
    batch.set(roomMemberDoc, {
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

  // 2. Search Groups by Keyword
  Stream<List<Map<String, dynamic>>> searchGroups(String query) {
    if (query.trim().isEmpty) return Stream.value([]);
    final lowerQuery = query.toLowerCase();

    return _db
        .collection('groups')
        .where('searchable_keywords', arrayContains: lowerQuery)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // 3. Request to Join a Group
  Future<String> requestToJoin(
    String groupId,
    bool requireApproval,
    String groupName,
    String groupType,
    String groupCategory,
    int currentMemberCount,
    String displayName,   // UserProvider에서 전달
    String phoneNumber,   // UserProvider에서 전달
  ) async {
    if (currentUserId.isEmpty) return 'error';

    try {
      // 차단된 유저면 가입 불가
      final bannedDoc = await _db
          .collection('groups').doc(groupId)
          .collection('banned').doc(currentUserId)
          .get();
      if (bannedDoc.exists) return 'banned';

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      final memberLimit = groupData?['member_limit'] as int? ?? 50;
      final memberCount = groupData?['member_count'] as int? ?? currentMemberCount;

      if (memberCount >= memberLimit) return 'full';
      if (requireApproval) {
        await _db
            .collection('groups')
            .doc(groupId)
            .collection('join_requests')
            .doc(currentUserId)
            .set({
          'user_id': currentUserId,
          'display_name': displayName,
          'phone_number': phoneNumber,
          'requested_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      } else {
        final batch = _db.batch();

        final memberDoc = _db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(currentUserId);
        batch.set(memberDoc, {
          'user_id': currentUserId,
          'display_name': displayName, // ✅ 추가
          'joined_at': FieldValue.serverTimestamp(),
          'role': 'member',
          'permissions': {
            'can_post_schedule': false,
            'can_create_sub_chat': false,
            'can_write_post': true,
            'can_edit_group_info': false,
            'can_manage_permissions': false,
          }
        });

        batch.update(_db.collection('groups').doc(groupId), {
          'member_count': FieldValue.increment(1),
        });

        final userJoinedGroupDoc = _db
            .collection('users')
            .doc(currentUserId)
            .collection('joined_groups')
            .doc(groupId);
        batch.set(userJoinedGroupDoc, {
          'joined_at': FieldValue.serverTimestamp(),
          'name': groupName,
          'type': groupType,
          'category': groupCategory,
          'member_count': currentMemberCount + 1,
        });

        // Find existing group_all chat and add the user
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

  // 4. Get My Joined Groups
  Stream<List<Map<String, dynamic>>> getMyJoinedGroups() {
    if (currentUserId.isEmpty) return Stream.value([]);

    // joined_groups에 name/type/category/member_count가 이미 저장되어 있으므로
    // groups 컬렉션 추가 조회 불필요 — 단일 쿼리로 처리
    return _db
        .collection('users')
        .doc(currentUserId)
        .collection('joined_groups')
        .orderBy('joined_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id; // groupId
              return data;
            }).toList());
  }

  // ── 가입 요청 대기 목록 스트림 ─────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getPendingJoinRequests(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('join_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('requested_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  // ── 가입 승인 ──────────────────────────────────────────────────────────────
  Future<String> approveJoinRequest(String groupId, String applicantUid) async {
    try {
      // 차단된 유저면 승인 불가 — join_request만 삭제하고 'banned' 반환
      final bannedDoc = await _db
          .collection('groups').doc(groupId)
          .collection('banned').doc(applicantUid)
          .get();
      if (bannedDoc.exists) {
        await _db
            .collection('groups').doc(groupId)
            .collection('join_requests').doc(applicantUid)
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

      final displayName = requestData['display_name'] as String? ?? 'Unknown';

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      final groupName = groupData?['name'] as String? ?? '';
      final groupType = groupData?['type'] as String? ?? 'club';
      final groupCategory = groupData?['category'] as String? ?? '';
      final memberCount = groupData?['member_count'] as int? ?? 0;

      final batch = _db.batch();

      // members에 추가
      batch.set(
        _db.collection('groups').doc(groupId).collection('members').doc(applicantUid),
        {
          'user_id': applicantUid,
          'display_name': displayName,
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

      // member_count 증가
      batch.update(_db.collection('groups').doc(groupId), {
        'member_count': FieldValue.increment(1),
      });

      // users joined_groups 추가
      batch.set(
        _db.collection('users').doc(applicantUid).collection('joined_groups').doc(groupId),
        {
          'joined_at': FieldValue.serverTimestamp(),
          'name': groupName,
          'type': groupType,
          'category': groupCategory,
          'member_count': memberCount + 1,
        },
      );

      // join_requests 삭제
      batch.delete(
        _db.collection('groups').doc(groupId).collection('join_requests').doc(applicantUid),
      );

      // group_all 채팅방에 추가
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
          _db.collection('chat_rooms').doc(chatId).collection('room_members').doc(applicantUid),
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
  Future<bool> rejectJoinRequest(String groupId, String applicantUid) async {
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
    return _db.collection('groups').doc(groupId).snapshots().map((snap) {
      final data = snap.data();
      return List<String>.from(data?['tags'] as List? ?? []);
    });
  }

  Future<bool> addGroupTag(String groupId, String tag) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'tags': FieldValue.arrayUnion([tag]),
      });
      return true;
    } catch (e) { debugPrint('addGroupTag error: $e'); return false; }
  }

  Future<bool> removeGroupTag(String groupId, String tag) async {
    try {
      await _db.collection('groups').doc(groupId).update({
        'tags': FieldValue.arrayRemove([tag]),
      });
      return true;
    } catch (e) { debugPrint('removeGroupTag error: $e'); return false; }
  }

  Future<bool> updateMemberTags(String groupId, String uid, List<String> tags) async {
    try {
      await _db.collection('groups').doc(groupId).collection('members').doc(uid)
          .update({'tags': tags});
      return true;
    } catch (e) { debugPrint('updateMemberTags error: $e'); return false; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 게시판 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getBoards(String groupId) {
    return _db.collection('groups').doc(groupId).collection('boards')
        .orderBy('order', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data(); data['id'] = doc.id; return data;
            }).toList());
  }

  Future<bool> createBoard(String groupId, Map<String, dynamic> boardData) async {
    try {
      final snap = await _db.collection('groups').doc(groupId).collection('boards')
          .orderBy('order', descending: true).limit(1).get();
      final maxOrder = snap.docs.isEmpty
          ? 0 : (snap.docs.first.data()['order'] as int? ?? 0) + 1;
      await _db.collection('groups').doc(groupId).collection('boards').add(
          {...boardData, 'order': maxOrder, 'created_at': FieldValue.serverTimestamp()});
      return true;
    } catch (e) { debugPrint('createBoard error: $e'); return false; }
  }

  Future<bool> updateBoard(String groupId, String boardId, Map<String, dynamic> data) async {
    try {
      await _db.collection('groups').doc(groupId).collection('boards').doc(boardId).update(data);
      return true;
    } catch (e) { debugPrint('updateBoard error: $e'); return false; }
  }

  Future<bool> deleteBoard(String groupId, String boardId) async {
    try {
      final postsSnap = await _db.collection('groups').doc(groupId).collection('posts')
          .where('board_id', isEqualTo: boardId).get();
      final batch = _db.batch();
      for (final doc in postsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db.collection('groups').doc(groupId).collection('boards').doc(boardId));
      await batch.commit();
      return true;
    } catch (e) { debugPrint('deleteBoard error: $e'); return false; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 게시글 관리
  // ══════════════════════════════════════════════════════════════════════════

  Stream<List<Map<String, dynamic>>> getPosts(String groupId, String boardId) {
    return _db.collection('groups').doc(groupId).collection('posts')
        .where('board_id', isEqualTo: boardId)
        .orderBy('is_pinned', descending: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data(); data['id'] = doc.id; return data;
            }).toList());
  }

  Stream<Map<String, dynamic>?> getPost(String groupId, String postId) {
    return _db.collection('groups').doc(groupId).collection('posts').doc(postId)
        .snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data()!; data['id'] = snap.id; return data;
    });
  }

  Future<String?> createPost(String groupId, Map<String, dynamic> postData) async {
    try {
      final doc = await _db.collection('groups').doc(groupId).collection('posts').add({
        ...postData,
        'is_pinned': false,
        'reactions': {},
        'comment_count': 0,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) { debugPrint('createPost error: $e'); return null; }
  }

  Future<bool> updatePost(String groupId, String postId, Map<String, dynamic> data) async {
    try {
      await _db.collection('groups').doc(groupId).collection('posts').doc(postId)
          .update({...data, 'updated_at': FieldValue.serverTimestamp()});
      return true;
    } catch (e) { debugPrint('updatePost error: $e'); return false; }
  }

  Future<bool> deletePost(String groupId, String postId) async {
    try {
      final commentsSnap = await _db.collection('groups').doc(groupId)
          .collection('posts').doc(postId).collection('comments').get();
      final batch = _db.batch();
      for (final doc in commentsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db.collection('groups').doc(groupId).collection('posts').doc(postId));
      await batch.commit();
      return true;
    } catch (e) { debugPrint('deletePost error: $e'); return false; }
  }

  Future<bool> togglePinPost(String groupId, String postId, bool currentPin) async {
    try {
      await _db.collection('groups').doc(groupId).collection('posts').doc(postId)
          .update({'is_pinned': !currentPin});
      return true;
    } catch (e) { debugPrint('togglePinPost error: $e'); return false; }
  }

  Future<void> toggleReaction(String groupId, String postId, String emoji) async {
    final ref = _db.collection('groups').doc(groupId).collection('posts').doc(postId);
    final snap = await ref.get();
    final reactions = Map<String, dynamic>.from(snap.data()?['reactions'] as Map? ?? {});
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

  Stream<List<Map<String, dynamic>>> getComments(String groupId, String postId) {
    return _db.collection('groups').doc(groupId).collection('posts').doc(postId)
        .collection('comments')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data(); data['id'] = doc.id; return data;
            }).toList());
  }

  Future<bool> addComment(
      String groupId, String postId, String content, String authorName) async {
    try {
      final batch = _db.batch();
      final commentRef = _db.collection('groups').doc(groupId)
          .collection('posts').doc(postId).collection('comments').doc();
      batch.set(commentRef, {
        'content': content,
        'author_id': currentUserId,
        'author_name': authorName,
        'created_at': FieldValue.serverTimestamp(),
      });
      batch.update(
        _db.collection('groups').doc(groupId).collection('posts').doc(postId),
        {'comment_count': FieldValue.increment(1)},
      );
      await batch.commit();
      return true;
    } catch (e) { debugPrint('addComment error: $e'); return false; }
  }

  Future<bool> deleteComment(String groupId, String postId, String commentId) async {
    try {
      final batch = _db.batch();
      batch.delete(_db.collection('groups').doc(groupId).collection('posts')
          .doc(postId).collection('comments').doc(commentId));
      batch.update(
        _db.collection('groups').doc(groupId).collection('posts').doc(postId),
        {'comment_count': FieldValue.increment(-1)},
      );
      await batch.commit();
      return true;
    } catch (e) { debugPrint('deleteComment error: $e'); return false; }
  }

  // ── 방장 위임 ──────────────────────────────────────────────────────────────
  // 1. 신규 owner: role → 'owner', 모든 permissions true
  // 2. 기존 owner: role → 'member', permissions 유지 (임의 조정 가능)
  // 3. groups.owner_id 업데이트
  // 4. group_all 채팅방 room_members role 동기화
  Future<bool> transferOwnership(String groupId, String newOwnerUid) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();

      // 신규 owner 권한 설정
      batch.update(
        _db.collection('groups').doc(groupId).collection('members').doc(newOwnerUid),
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

      // 기존 owner → member로 강등
      batch.update(
        _db.collection('groups').doc(groupId).collection('members').doc(currentUserId),
        {'role': 'member'},
      );

      // groups.owner_id 업데이트
      batch.update(
        _db.collection('groups').doc(groupId),
        {'owner_id': newOwnerUid},
      );

      // group_all 채팅방만 room_members role 동기화 (group_sub는 독립적)
      final chatSnap = await _db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .where('type', isEqualTo: 'group_all')
          .get();

      for (final chatDoc in chatSnap.docs) {
        final chatId = chatDoc.id;
        batch.update(
          _db.collection('chat_rooms').doc(chatId).collection('room_members').doc(newOwnerUid),
          {'role': 'owner'},
        );
        batch.update(
          _db.collection('chat_rooms').doc(chatId).collection('room_members').doc(currentUserId),
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
  Future<bool> kickMember(String groupId, String targetUid, {bool ban = false, String displayName = ''}) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();

      // 그룹 members 서브컬렉션에서 제거
      batch.delete(
        _db.collection('groups').doc(groupId).collection('members').doc(targetUid),
      );

      // groups.member_count 감소
      batch.update(
        _db.collection('groups').doc(groupId),
        {'member_count': FieldValue.increment(-1)},
      );

      // 해당 유저의 joined_groups에서 제거
      batch.delete(
        _db.collection('users').doc(targetUid).collection('joined_groups').doc(groupId),
      );

      // 그룹 차단 → banned 컬렉션에 저장
      if (ban) {
        batch.set(
          _db.collection('groups').doc(groupId).collection('banned').doc(targetUid),
          {
            'display_name': displayName,
            'banned_at': FieldValue.serverTimestamp(),
            'banned_by': currentUserId,
          },
        );
      }

      // 그룹에 속한 모든 채팅방(group_all + group_sub)에서 제거
      final chatSnap = await _db
          .collection('chat_rooms')
          .where('ref_group_id', isEqualTo: groupId)
          .get();

      for (final chatDoc in chatSnap.docs) {
        final chatId = chatDoc.id;
        final memberIds = List<String>.from(chatDoc.data()['member_ids'] as List? ?? []);
        memberIds.remove(targetUid);

        batch.update(
          _db.collection('chat_rooms').doc(chatId),
          {'member_ids': memberIds},
        );
        batch.delete(
          _db.collection('chat_rooms').doc(chatId).collection('room_members').doc(targetUid),
        );
      }

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('kickMember error: $e');
      return false;
    }
  }

  // 그룹 차단 해제
  Future<void> unbanMember(String groupId, String targetUid) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .doc(targetUid)
        .delete();
  }

  // 차단된 멤버 목록
  Stream<QuerySnapshot> bannedMembersStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .snapshots();
  }

  // 가입 시 차단 여부 확인
  Future<bool> isBanned(String groupId, String uid) async {
    final doc = await _db
        .collection('groups')
        .doc(groupId)
        .collection('banned')
        .doc(uid)
        .get();
    return doc.exists;
  }
}