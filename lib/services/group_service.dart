import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../utils/search_dictionary.dart';
import '../l10n/app_localizations.dart';
import '../screens/group_tabs/group_type_category_data.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  int defaultMaxMemberLimitForPlan(String plan) {
    switch (plan) {
      case 'plus':
        return 300;
      case 'pro':
        return 1000;
      case 'free':
      default:
        return 50;
    }
  }

  // ── 그룹 생성 ──────────────────────────────────────────────────────────────
  Future<String?> createGroup({
    required String name,
    required String type,
    required String category,
    required bool requireApproval,
    required String displayName,
    String profileImage = '',
    int? memberLimit,
    String plan = 'free',
    String status = 'active',
    bool allowPlanUpgrade = true,
    GeoPoint? location,
    String locationName = '',
    String ownerName = '',
    String ownerPhotoUrl = '',
  }) async {
    if (currentUserId.isEmpty) return null;

    final batch = _db.batch();
    final groupDoc = _db.collection('groups').doc();
    final maxMemberLimit = defaultMaxMemberLimitForPlan(plan);
    final initialMemberLimit = memberLimit ?? maxMemberLimit;

    final lEn = AppLocalizations.en();
    final lKo = AppLocalizations.ko();
    final lJa = AppLocalizations.ja();

    final Map<String, String> localizedCategories = {
      'en': GroupTypeCategoryData.localizeKey(category, lEn),
      'ko': GroupTypeCategoryData.localizeKey(category, lKo),
      'ja': GroupTypeCategoryData.localizeKey(category, lJa),
    };

    List<String> keywords = name.toLowerCase().split(' ');
    keywords.add(name.toLowerCase());

    batch.set(groupDoc, {
      'name': name,
      'status': 'active',
      'type': type,
      'category': category,
      'require_approval': requireApproval,
      'owner_id': currentUserId,
      'member_count': 1,
      'member_limit': initialMemberLimit,
      'max_member_limit': maxMemberLimit,
      'plan': plan,
      'invite_token': null,
      'qr_enabled': false,
      'allow_plan_upgrade': allowPlanUpgrade,
      'created_at': FieldValue.serverTimestamp(),
      'searchable_keywords': keywords,
      'search_tokens': SearchDictionary.generateSearchTokens(
        name: name,
        localizedCategories: localizedCategories,
        tags: [],
        locationName: locationName,
      ),
      'owner_name': ownerName,
      'owner_photo_url': ownerPhotoUrl,
    });

    batch.set(groupDoc.collection('members').doc(currentUserId), {
      'user_id': currentUserId,
      'display_name': displayName,
      'profile_image': profileImage,
      'joined_at': FieldValue.serverTimestamp(),
      'role': 'owner',
      'permissions': {
        'can_post_schedule': true,
        'can_create_sub_chat': true,
        'can_start_voice_call': true,
        'can_write_post': true,
        'can_edit_group_info': true,
        'can_manage_permissions': true,
      },
    });

    batch.set(
      _db.collection('users').doc(currentUserId).collection('joined_groups').doc(groupDoc.id),
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

  // ── 그룹 검색 (고도화: 연관어 + 위치 기반 랭킹) ─────────────────────────────
  Stream<List<Map<String, dynamic>>> searchGroups(String query, {GeoPoint? userLocation}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Stream.value([]);
    final expandedTerms = SearchDictionary.expandQuery(trimmed);

    return _db
        .collection('groups')
        .where('search_tokens', arrayContainsAny: expandedTerms)
        .limit(40)
        .snapshots()
        .map((snapshot) {
      final results = snapshot.docs
          .map((doc) {
            final data = doc.data();
            if ((data['status'] as String? ?? 'active') == 'deleted') return null;
            data['id'] = doc.id;
            double rankingScore = 0;
            final groupLoc = data['location'] as GeoPoint?;
            final groupName = (data['name'] as String? ?? '').toLowerCase();
            if (groupName.contains(trimmed.toLowerCase())) rankingScore += 100;
            if (userLocation != null && groupLoc != null) {
              final dist = _calculateDistance(userLocation.latitude, userLocation.longitude, groupLoc.latitude, groupLoc.longitude);
              data['distance_km'] = dist.toStringAsFixed(1);
              if (dist <= 5) rankingScore += 50;
              else if (dist <= 15) rankingScore += 30;
              else if (dist <= 30) rankingScore += 10;
            }
            data['_ranking_score'] = rankingScore;
            return data;
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      results.sort((a, b) => (b['_ranking_score'] as double).compareTo(a['_ranking_score'] as double));
      return results;
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  // ── 그룹 가입 요청 ──────────────────────────────────────────────────────────
  Future<String> requestToJoin(String groupId, bool requireApproval, String groupName, String groupType, String groupCategory, int currentMemberCount, String displayName, String phoneNumber, String profileImage) async {
    if (currentUserId.isEmpty) return 'error';
    try {
      final bannedDoc = await _db.collection('groups').doc(groupId).collection('banned').doc(currentUserId).get();
      if (bannedDoc.exists) return 'banned';

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      if ((groupData?['status'] as String? ?? 'active') == 'deleted') return 'error';
      final memberLimit = groupData?['member_limit'] as int? ?? 50;
      final memberCount = groupData?['member_count'] as int? ?? currentMemberCount;
      if (memberCount >= memberLimit) return 'full';

      if (requireApproval) {
        await _db.collection('groups').doc(groupId).collection('join_requests').doc(currentUserId).set({
          'user_id': currentUserId,
          'display_name': displayName,
          'phone_number': phoneNumber,
          'profile_image': profileImage,
          'requested_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      } else {
        final batch = _db.batch();
        batch.set(_db.collection('groups').doc(groupId).collection('members').doc(currentUserId), {
          'user_id': currentUserId,
          'display_name': displayName,
          'profile_image': profileImage,
          'joined_at': FieldValue.serverTimestamp(),
          'role': 'member',
          'permissions': {'can_post_schedule': false, 'can_create_sub_chat': false, 'can_start_voice_call': false, 'can_write_post': true, 'can_edit_group_info': false, 'can_manage_permissions': false},
        });
        batch.update(_db.collection('groups').doc(groupId), {'member_count': FieldValue.increment(1)});
        batch.set(_db.collection('users').doc(currentUserId).collection('joined_groups').doc(groupId), {
          'joined_at': FieldValue.serverTimestamp(),
          'name': groupName,
          'type': groupType,
          'category': groupCategory,
          'member_count': currentMemberCount + 1,
        });
        final chatRoomsSnapshot = await _db.collection('chat_rooms').where('ref_group_id', isEqualTo: groupId).where('type', isEqualTo: 'group_all').limit(1).get();
        if (chatRoomsSnapshot.docs.isNotEmpty) {
          final chatId = chatRoomsSnapshot.docs.first.id;
          batch.update(_db.collection('chat_rooms').doc(chatId), {'member_ids': FieldValue.arrayUnion([currentUserId]), 'unread_counts.$currentUserId': 0});
          batch.set(_db.collection('chat_rooms').doc(chatId).collection('room_members').doc(currentUserId), {
            'uid': currentUserId,
            'display_name': displayName,
            'role': 'member',
            'joined_at': FieldValue.serverTimestamp(),
            'last_read_time': FieldValue.serverTimestamp(),
            'unread_cnt': 0,
          });
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
    return _db.collection('users').doc(currentUserId).collection('joined_groups').snapshots().switchMap((snapshot) {
      final ids = snapshot.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return Stream.value([]);
      return _db.collection('groups').where(FieldPath.documentId, whereIn: ids).snapshots().map((groupsSnap) => groupsSnap.docs
          .map((doc) {
            final data = doc.data();
            if ((data['status'] as String? ?? 'active') == 'deleted') return null;
            data['id'] = doc.id;
            return data;
          })
          .whereType<Map<String, dynamic>>()
          .toList());
    });
  }

  // ── 가입 요청 대기 목록 ────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getPendingJoinRequests(String groupId) {
    return _db.collection('groups').doc(groupId).collection('join_requests').where('status', isEqualTo: 'pending').snapshots().map((snap) {
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
  Future<String> approveJoinRequest(String groupId, String applicantUid) async {
    try {
      final bannedDoc = await _db.collection('groups').doc(groupId).collection('banned').doc(applicantUid).get();
      if (bannedDoc.exists) {
        await _db.collection('groups').doc(groupId).collection('join_requests').doc(applicantUid).delete();
        return 'banned';
      }
      final requestDoc = await _db.collection('groups').doc(groupId).collection('join_requests').doc(applicantUid).get();
      final requestData = requestDoc.data();
      if (requestData == null) return 'error';
      final displayName = requestData['display_name'] as String? ?? 'Unknown';
      final profileImage = requestData['profile_image'] as String? ?? '';

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      final groupData = groupDoc.data();
      if ((groupData?['status'] as String? ?? 'active') == 'deleted') return 'error';
      final groupName = groupData?['name'] as String? ?? '';
      final groupType = groupData?['type'] as String? ?? 'club';
      final groupCategory = groupData?['category'] as String? ?? '';
      final memberCount = groupData?['member_count'] as int? ?? 0;
      final memberLimit = groupData?['member_limit'] as int? ?? 50;
      if (memberCount >= memberLimit) return 'full';

      final batch = _db.batch();
      batch.set(_db.collection('groups').doc(groupId).collection('members').doc(applicantUid), {
        'user_id': applicantUid,
        'display_name': displayName,
        'profile_image': profileImage,
        'joined_at': FieldValue.serverTimestamp(),
        'role': 'member',
        'permissions': {'can_post_schedule': false, 'can_create_sub_chat': false, 'can_start_voice_call': false, 'can_write_post': true, 'can_edit_group_info': false, 'can_manage_permissions': false},
      });
      batch.update(_db.collection('groups').doc(groupId), {'member_count': FieldValue.increment(1)});
      batch.set(_db.collection('users').doc(applicantUid).collection('joined_groups').doc(groupId), {
        'joined_at': FieldValue.serverTimestamp(),
        'name': groupName,
        'type': groupType,
        'category': groupCategory,
        'member_count': memberCount + 1,
      });
      batch.delete(_db.collection('groups').doc(groupId).collection('join_requests').doc(applicantUid));

      final chatSnap = await _db.collection('chat_rooms').where('ref_group_id', isEqualTo: groupId).where('type', isEqualTo: 'group_all').limit(1).get();
      if (chatSnap.docs.isNotEmpty) {
        final chatId = chatSnap.docs.first.id;
        batch.update(_db.collection('chat_rooms').doc(chatId), {'member_ids': FieldValue.arrayUnion([applicantUid]), 'unread_counts.$applicantUid': 0});
        batch.set(_db.collection('chat_rooms').doc(chatId).collection('room_members').doc(applicantUid), {
          'uid': applicantUid,
          'display_name': displayName,
          'role': 'member',
          'joined_at': FieldValue.serverTimestamp(),
          'last_read_time': FieldValue.serverTimestamp(),
          'unread_cnt': 0,
        });
      }
      await batch.commit();
      return 'ok';
    } catch (e) {
      debugPrint('approveJoinRequest error: $e');
      return 'error';
    }
  }

  Future<bool> rejectJoinRequest(String groupId, String applicantUid) async {
    try {
      await _db.collection('groups').doc(groupId).collection('join_requests').doc(applicantUid).delete();
      return true;
    } catch (e) {
      debugPrint('rejectJoinRequest error: $e');
      return false;
    }
  }

  // ── 태그 및 알림 관리 ──
  Stream<List<String>> getGroupTags(String groupId) {
    return _db.collection('groups').doc(groupId).snapshots().map((snap) => List<String>.from(snap.data()?['tags'] as List? ?? []));
  }
  Future<bool> addGroupTag(String groupId, String tag) async {
    try { await _db.collection('groups').doc(groupId).update({'tags': FieldValue.arrayUnion([tag])}); return true; } catch (e) { return false; }
  }
  Future<bool> removeGroupTag(String groupId, String tag) async {
    try { await _db.collection('groups').doc(groupId).update({'tags': FieldValue.arrayRemove([tag])}); return true; } catch (e) { return false; }
  }
  Future<bool> updateMemberTags(String groupId, String uid, List<String> tags) async {
    try { await _db.collection('groups').doc(groupId).collection('members').doc(uid).update({'tags': tags}); return true; } catch (e) { return false; }
  }
  Future<void> updateLastReadNoticeTime(String groupId) async {
    if (currentUserId.isEmpty) return;
    try { await _db.collection('groups').doc(groupId).collection('members').doc(currentUserId).update({'last_read_notice_time': FieldValue.serverTimestamp()}); } catch (e) {}
  }

  Stream<Map<String, dynamic>?> streamLatestGroupNotice(String groupId) {
    return _db.collection('groups').doc(groupId).collection('notices').orderBy('created_at', descending: true).limit(1).snapshots().map((snap) {
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      data['id'] = snap.docs.first.id;
      return data;
    });
  }

  Stream<List<Map<String, dynamic>>> streamGroupNotices(String groupId) {
    return _db.collection('groups').doc(groupId).collection('notices').orderBy('created_at', descending: true).snapshots().map((snap) => snap.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList());
  }

  Future<bool> createGroupNotice({required String groupId, required String text, required String authorName}) async {
    if (currentUserId.isEmpty) return false;
    try { await _db.collection('groups').doc(groupId).collection('notices').add({'text': text.trim(), 'author_uid': currentUserId, 'author_name': authorName, 'created_at': FieldValue.serverTimestamp()}); return true; } catch (e) { return false; }
  }

  // ── 게시판 및 포스트 관리 ──
  Stream<List<Map<String, dynamic>>> getBoards(String groupId) {
    return _db.collection('groups').doc(groupId).collection('boards').orderBy('order', descending: false).snapshots().map((snap) => snap.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList());
  }

  Future<bool> createBoard(String groupId, Map<String, dynamic> boardData) async {
    try {
      return await _db.runTransaction((tx) async {
        final groupRef = _db.collection('groups').doc(groupId);
        final groupDoc = await tx.get(groupRef);
        final data = groupDoc.data()!;
        final plan = data['plan'] ?? 'free';
        final boardCount = data['board_count'] ?? 0;
        int maxBoards = (plan == 'pro') ? 1000000 : (plan == 'plus' ? 5 : 3);
        if (boardCount >= maxBoards) throw Exception('limit_reached');
        tx.set(groupRef.collection('boards').doc(), {...boardData, 'order': boardCount, 'created_at': FieldValue.serverTimestamp()});
        tx.update(groupRef, {'board_count': FieldValue.increment(1)});
        return true;
      });
    } catch (e) { return false; }
  }

  Future<bool> updateBoard(String groupId, String boardId, Map<String, dynamic> data) async {
    try { await _db.collection('groups').doc(groupId).collection('boards').doc(boardId).update(data); return true; } catch (e) { return false; }
  }

  Future<bool> deleteBoard(String groupId, String boardId) async {
    try {
      final postsSnap = await _db.collection('groups').doc(groupId).collection('posts').where('board_id', isEqualTo: boardId).get();
      final batch = _db.batch();
      for (final doc in postsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db.collection('groups').doc(groupId).collection('boards').doc(boardId));
      batch.update(_db.collection('groups').doc(groupId), {'board_count': FieldValue.increment(-1)});
      await batch.commit();
      return true;
    } catch (e) { return false; }
  }

  Stream<List<Map<String, dynamic>>> getPosts(String groupId, String boardId) {
    return _db.collection('groups').doc(groupId).collection('posts').where('board_id', isEqualTo: boardId).orderBy('is_pinned', descending: true).orderBy('created_at', descending: true).snapshots().map((snap) => snap.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList());
  }

  Future<String?> createPost(String groupId, Map<String, dynamic> postData) async {
    try { final doc = await _db.collection('groups').doc(groupId).collection('posts').add({...postData, 'is_pinned': false, 'reactions': {}, 'comment_count': 0, 'created_at': FieldValue.serverTimestamp(), 'updated_at': FieldValue.serverTimestamp()}); return doc.id; } catch (e) { return null; }
  }

  Future<bool> updatePost(String groupId, String postId, Map<String, dynamic> data) async {
    try { await _db.collection('groups').doc(groupId).collection('posts').doc(postId).update({...data, 'updated_at': FieldValue.serverTimestamp()}); return true; } catch (e) { return false; }
  }

  Future<bool> deletePost(String groupId, String postId) async {
    try {
      final commentsSnap = await _db.collection('groups').doc(groupId).collection('posts').doc(postId).collection('comments').get();
      final batch = _db.batch();
      for (final doc in commentsSnap.docs) batch.delete(doc.reference);
      batch.delete(_db.collection('groups').doc(groupId).collection('posts').doc(postId));
      await batch.commit();
      return true;
    } catch (e) { return false; }
  }

  Future<void> toggleReaction(String groupId, String postId, String emoji) async {
    final ref = _db.collection('groups').doc(groupId).collection('posts').doc(postId);
    final snap = await ref.get();
    final reactions = Map<String, dynamic>.from(snap.data()?['reactions'] as Map? ?? {});
    if (reactions[currentUserId] == emoji) reactions.remove(currentUserId);
    else reactions[currentUserId] = emoji;
    await ref.update({'reactions': reactions});
  }

  // ── 멤버 관리 및 권한 (Core) ──
  Future<bool> transferOwnership(String groupId, String newOwnerUid, String newOwnerName, String newOwnerPhotoUrl) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();
      final groupRef = _db.collection('groups').doc(groupId);
      batch.update(groupRef.collection('members').doc(newOwnerUid), {'role': 'owner', 'permissions': {'can_post_schedule': true, 'can_create_sub_chat': true, 'can_start_voice_call': true, 'can_write_post': true, 'can_edit_group_info': true, 'can_manage_permissions': true}});
      batch.update(groupRef.collection('members').doc(currentUserId), {'role': 'member', 'permissions': {'can_post_schedule': false, 'can_create_sub_chat': false, 'can_start_voice_call': false, 'can_write_post': true, 'can_edit_group_info': false, 'can_manage_permissions': false}});
      batch.update(groupRef, {'owner_id': newOwnerUid, 'owner_name': newOwnerName, 'owner_photo_url': newOwnerPhotoUrl});
      
      final chatSnap = await _db.collection('chat_rooms').where('ref_group_id', isEqualTo: groupId).where('type', isEqualTo: 'group_all').get();
      for (final chatDoc in chatSnap.docs) {
        batch.update(chatDoc.reference.collection('room_members').doc(newOwnerUid), {'role': 'owner'});
        batch.update(chatDoc.reference.collection('room_members').doc(currentUserId), {'role': 'member'});
      }
      await batch.commit();
      return true;
    } catch (e) { return false; }
  }

  Future<bool> updateMemberRoleAndPermissions({required String groupId, required String targetUid, required String role, required Map<String, bool> permissions}) async {
    try { await _db.collection('groups').doc(groupId).collection('members').doc(targetUid).update({'role': role, 'permissions': permissions}); return true; } catch (e) { return false; }
  }

  Future<bool> kickMember(String groupId, String targetUid, {bool ban = false, String displayName = '', String reason = ''}) async {
    if (currentUserId.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.delete(_db.collection('groups').doc(groupId).collection('members').doc(targetUid));
      batch.update(_db.collection('groups').doc(groupId), {'member_count': FieldValue.increment(-1)});
      batch.delete(_db.collection('users').doc(targetUid).collection('joined_groups').doc(groupId));
      if (ban) {
        batch.set(_db.collection('groups').doc(groupId).collection('banned').doc(targetUid), {
          'display_name': displayName, 'banned_at': FieldValue.serverTimestamp(), 'banned_by': currentUserId, 'reason': reason,
        });
      }
      final chatSnap = await _db.collection('chat_rooms').where('ref_group_id', isEqualTo: groupId).get();
      for (final chatDoc in chatSnap.docs) {
        final memberIds = List<String>.from(chatDoc.data()['member_ids'] as List? ?? []);
        if (memberIds.contains(targetUid)) {
          memberIds.remove(targetUid);
          batch.update(chatDoc.reference, {'member_ids': memberIds});
          batch.delete(chatDoc.reference.collection('room_members').doc(targetUid));
        }
      }
      await batch.commit();
      return true;
    } catch (e) { debugPrint('kickMember error: $e'); return false; }
  }

  Future<void> unbanMember(String groupId, String targetUid) async {
    await _db.collection('groups').doc(groupId).collection('banned').doc(targetUid).delete();
  }

  Stream<QuerySnapshot> bannedMembersStream(String groupId) {
    return _db.collection('groups').doc(groupId).collection('banned').snapshots();
  }

  Future<void> updateGroupLocation({required String groupId, required double lat, required double lng, required String locationName}) async {
    await _db.collection('groups').doc(groupId).update({'location': GeoPoint(lat, lng), 'location_name': locationName});
  }

  Future<void> updateGroupProfileImage({required String groupId, required String imageUrl}) async {
    final batch = _db.batch();
    batch.update(_db.collection('groups').doc(groupId), {'group_profile_image': imageUrl});
    final chatSnap = await _db.collection('chat_rooms').where('ref_group_id', isEqualTo: groupId).where('type', isEqualTo: 'group_all').get();
    for (final chatDoc in chatSnap.docs) batch.update(chatDoc.reference, {'group_profile_image': imageUrl});
    await batch.commit();
  }
}
