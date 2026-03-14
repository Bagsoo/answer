import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// 단일 그룹 화면에서 공유하는 데이터를 한 번만 구독합니다.
/// GroupDetailScreen에서 ChangeNotifierProvider로 생성/해제됩니다.
class GroupProvider extends ChangeNotifier {
  final String groupId;

  GroupProvider(this.groupId) {
    _init();
  }

  // ── 그룹 기본정보 ─────────────────────────────────────────────────────────
  String name = '';
  String type = '';
  String category = '';
  String plan = '';
  String ownerId = '';
  int memberCount = 0;
  int memberLimit = 50;
  bool requireApproval = false;
  bool allowPlanUpgrade = false;
  List<String> tags = [];
  List<String> likes = [];
  DateTime? createdAt;

  // ── 내 멤버 정보 ──────────────────────────────────────────────────────────
  String myRole = 'member';
  Map<String, dynamic> myPerms = {};

  // ── 편의 getter ───────────────────────────────────────────────────────────
  String get currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get isOwner => myRole == 'owner';
  bool get isLiked => likes.contains(currentUserId);

  bool get canPostSchedule =>
      isOwner || myPerms['can_post_schedule'] == true;
  bool get canManagePermissions =>
      isOwner || myPerms['can_manage_permissions'] == true;
  bool get canEditGroupInfo =>
      isOwner || myPerms['can_edit_group_info'] == true;
  bool get canCreateSubChat =>
      isOwner || myPerms['can_create_sub_chat'] == true;
  bool get canWritePost =>
      isOwner || myPerms['can_write_post'] == true;

  bool _loaded = false;
  bool get loaded => _loaded;

  StreamSubscription? _groupSub;
  StreamSubscription? _memberSub;

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
      plan = d['plan'] as String? ?? 'free';
      ownerId = d['owner_id'] as String? ?? '';
      memberCount = d['member_count'] as int? ?? 0;
      memberLimit = d['member_limit'] as int? ?? 50;
      requireApproval = d['require_approval'] as bool? ?? false;
      allowPlanUpgrade = d['allow_plan_upgrade'] as bool? ?? false;
      tags = List<String>.from(d['tags'] as List? ?? []);
      likes = List<String>.from(d['likes'] as List? ?? []);
      final ts = d['created_at'] as Timestamp?;
      createdAt = ts?.toDate();
      _loaded = true;
      notifyListeners();
    });

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
      notifyListeners();
    });
  }

  // ── 좋아요 토글 ───────────────────────────────────────────────────────────
  Future<void> toggleLike() async {
    final ref = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId);
    if (isLiked) {
      await ref.update({
        'likes': FieldValue.arrayRemove([currentUserId])
      });
    } else {
      await ref.update({
        'likes': FieldValue.arrayUnion([currentUserId])
      });
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _memberSub?.cancel();
    super.dispose();
  }
}