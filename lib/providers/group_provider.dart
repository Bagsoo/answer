import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// 단일 그룹 화면에서 공유하는 데이터를 한 번만 구독합니다.
/// GroupDetailScreen에서 ChangeNotifierProvider로 생성/해제됩니다.
class GroupProvider extends ChangeNotifier {
  final String groupId;

  GroupProvider(this.groupId, {Map<String, dynamic>? initialData}) {
    if (initialData != null) {
      _applySeed(initialData);
    }
    _init();
  }

  // ── 그룹 기본정보 ─────────────────────────────────────────────────────────
  String name = '';
  String type = '';
  String category = '';
  String plan = '';
  String status = 'active';
  String ownerId = '';
  String profileImageUrl = '';
  int memberCount = 0;
  int memberLimit = 50;
  int maxMemberLimit = 50;
  int boardCount = 0;
  int chatCount = 0;
  bool requireApproval = false;
  bool allowPlanUpgrade = false;
  bool qrEnabled = false;
  String inviteToken = '';
  List<String> tags = [];
  int likesCount = 0;
  DateTime? createdAt;

  GeoPoint? location;
  String locationName = ''; 

  // ── 내 멤버 정보 ──────────────────────────────────────────────────────────
  String myRole = 'member';
  Map<String, dynamic> myPerms = {};
  DateTime? myLastReadNoticeTime;

  // ── 편의 getter ───────────────────────────────────────────────────────────
  String get currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get isOwner => myRole == 'owner';
  bool _isLiked = false;
  bool get isLiked => _isLiked;
  bool get isPaidPlan => plan == 'plus' || plan == 'pro';
  bool get isDeleted => status == 'deleted';

  bool get canPostSchedule =>
      isOwner || myPerms['can_post_schedule'] == true;
  bool get canManagePermissions =>
      isOwner || myPerms['can_manage_permissions'] == true;
  bool get canEditGroupInfo =>
      isOwner || myPerms['can_edit_group_info'] == true;
  bool get canCreateSubChat =>
      isOwner || myPerms['can_create_sub_chat'] == true;
  bool get canStartVoiceCall =>
      isOwner || myPerms['can_start_voice_call'] == true;
  bool get canWritePost =>
      isOwner || myPerms['can_write_post'] == true;

  bool _loaded = false;
  bool get loaded => _loaded;

  int get absoluteMaxLimit {
    if (maxMemberLimit > 0) return maxMemberLimit;
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

  int getMaxBoards() {
    switch (plan) {
      case 'pro':
        return 1000000; // 무제한 (사실상 매우 큰 수)
      case 'plus':
        return 5;
      case 'free':
      default:
        return 3;
    }
  }

  int getMaxChats() {
    switch (plan) {
      case 'pro':
        return 1000000; // 무제한
      case 'plus':
        return 10;
      case 'free':
      default:
        return 5;
    }
  }

  double? get locationLat => location?.latitude;
  double? get locationLng => location?.longitude;
  String get currentLocationName => locationName;

  StreamSubscription? _groupSub;
  StreamSubscription? _memberSub;
  StreamSubscription? _likeSub;

  void _applySeed(Map<String, dynamic> d) {
    name = d['name'] as String? ?? name;
    type = d['type'] as String? ?? type;
    category = d['category'] as String? ?? category;
    status = d['status'] as String? ?? status;
    memberCount = (d['member_count'] as num?)?.toInt() ?? memberCount;
    profileImageUrl = d['group_profile_image'] as String? ?? profileImageUrl;
    likesCount = (d['likes_count'] as num?)?.toInt() ?? likesCount;
    _loaded = true;
  }

  void _init() {
    final db = FirebaseFirestore.instance;

    // 1) 그룹 기본정보 구독
    _groupSub = db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .listen((snap) {
      final d = snap.data() ?? {};
      name = d['name'] as String? ?? '';
      type = d['type'] as String? ?? '';
      category = d['category'] as String? ?? '';
      status = d['status'] as String? ?? 'active';
      plan = d['plan'] as String? ?? 'free';
      ownerId = d['owner_id'] as String? ?? '';
      memberCount = d['member_count'] as int? ?? 0;
      memberLimit = d['member_limit'] as int? ?? 50;
      maxMemberLimit = d['max_member_limit'] as int? ?? 0;
      boardCount = d['board_count'] as int? ?? 0;
      chatCount = d['chat_count'] as int? ?? 0;
      profileImageUrl = d['group_profile_image'] as String? ?? '';
      requireApproval = d['require_approval'] as bool? ?? false;
      allowPlanUpgrade = d['allow_plan_upgrade'] as bool? ?? false;
      qrEnabled = d['qr_enabled'] as bool? ?? false;
      inviteToken = d['invite_token'] as String? ?? '';
      tags = List<String>.from(d['tags'] as List? ?? []);
      likesCount = (d['likes_count'] as num?)?.toInt() ?? 0;
      final ts = d['created_at'] as Timestamp?;
      location = d['location'] as GeoPoint?;
      locationName = d['location_name'] as String? ?? '';
      createdAt = ts?.toDate();
      _loaded = true;
      notifyListeners();
    });

    // 3) 좋아요 상태 구독
    _likeSub?.cancel();
    if (currentUserId.isNotEmpty) {
      _likeSub = db
          .collection('groups')
          .doc(groupId)
          .collection('likes')
          .doc(currentUserId)
          .snapshots()
          .listen((snap) {
        _isLiked = snap.exists;
        notifyListeners();
      });
    }

    // 2) 내 멤버 정보 구독
    _memberSub = db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(currentUserId)
        .snapshots()
        .listen((snap) {
      final d = snap.data() ?? {};
      myRole = d['role'] as String? ?? 'member';
      myPerms =
          Map<String, dynamic>.from(d['permissions'] as Map? ?? {});
      myLastReadNoticeTime = (d['last_read_notice_time'] as Timestamp?)?.toDate();
      notifyListeners();
    });
  }

  // ── 좋아요 토글 ───────────────────────────────────────────────────────────
  Future<void> toggleLike() async {
    if (currentUserId.isEmpty) return;
    
    final db = FirebaseFirestore.instance;
    final groupsLikeRef = db
        .collection('groups')
        .doc(groupId)
        .collection('likes')
        .doc(currentUserId);
    final usersLikeRef = db
        .collection('users')
        .doc(currentUserId)
        .collection('liked_groups')
        .doc(groupId);
        
    final snap = await groupsLikeRef.get();
    final batch = db.batch();
    
    if (snap.exists) {
      batch.delete(groupsLikeRef);
      batch.delete(usersLikeRef);
    } else {
      batch.set(groupsLikeRef, {
        'createdAt': FieldValue.serverTimestamp(),
        'uid': currentUserId,
      });
      batch.set(usersLikeRef, {
        'createdAt': FieldValue.serverTimestamp(),
        'groupId': groupId,
      });
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _memberSub?.cancel();
    _likeSub?.cancel();
    super.dispose();
  }
}
