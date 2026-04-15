import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule.dart';
import 'notification_service.dart';

class MyScheduleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  static const String _cacheKey = 'my_schedules_cache';
  static const String _groupNamesKey = 'group_names_cache';

  String get currentUserId => _auth.currentUser?.uid ?? '';

  // ── 통합 스케줄 스트림 (Cache + Group + Personal) ───────────────────────
  Stream<List<Schedule>> getMySchedules() {
    final personalStream = _db
        .collection('users')
        .doc(currentUserId)
        .collection('personal_schedules')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Schedule.fromFirestore(doc)).toList());

    final groupScheduleStream = _db
        .collectionGroup('schedules')
        .where('rsvp.$currentUserId', isEqualTo: 'yes')
        .snapshots()
        .asyncMap((snap) async {
          final groupNames = await _getGroupNames();
          return snap.docs.map((doc) {
            final groupId = doc.reference.parent.parent?.id;
            return Schedule.fromFirestore(doc, groupName: groupNames[groupId]);
          }).toList();
        });

    return Rx.combineLatest2<List<Schedule>, List<Schedule>, List<Schedule>>(
      personalStream,
      groupScheduleStream,
      (personal, groups) {
        final combined = [...personal, ...groups];
        combined.sort((a, b) => a.startTime.compareTo(b.startTime));
        _cacheSchedules(combined);
        return combined;
      },
    ).startWith([]); // Simplified to emit empty list first
  }

  // ── 캐시 처리 ──────────────────────────────────────────────────────────
  Future<void> _cacheSchedules(List<Schedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = schedules.map((s) => s.toJson()).toList();
    await prefs.setString(_cacheKey, jsonEncode(jsonList));
  }

  Future<List<Schedule>> _getCachedSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((j) => Schedule.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── 그룹 이름 캐시 (N+1 방지용) ───────────────────────────────────────────
  Future<Map<String, String>> _getGroupNames() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheStr = prefs.getString(_groupNamesKey);
    Map<String, String> cache = {};
    if (cacheStr != null) {
      cache = Map<String, String>.from(jsonDecode(cacheStr));
    }

    // 현재 사용자가 가입된 그룹 목록에서 최신 이름들 가져오기
    // 이 부분은 효율을 위해 사용자가 가입한 그룹 정보(joined_groups)를 활용
    final joinedGroupsSnap = await _db
        .collection('users')
        .doc(currentUserId)
        .collection('joined_groups')
        .get();

    bool changed = false;
    for (var doc in joinedGroupsSnap.docs) {
      final name = doc.data()['name'] as String?;
      if (name != null && cache[doc.id] != name) {
        cache[doc.id] = name;
        changed = true;
      }
    }

    if (changed) {
      await prefs.setString(_groupNamesKey, jsonEncode(cache));
    }
    return cache;
  }

  // ── 개인 일정 추가/수정/삭제 ──────────────────────────────────────────────
  Future<String> savePersonalSchedule(Map<String, dynamic> data, {String? id}) async {
    final col = _db.collection('users').doc(currentUserId).collection('personal_schedules');
    
    data['updated_at'] = FieldValue.serverTimestamp();
    if (id != null) {
      await col.doc(id).update(data);
      return id;
    } else {
      data['created_by'] = currentUserId;
      data['created_at'] = FieldValue.serverTimestamp();
      final docRef = await col.add(data);
      return docRef.id;
    }
  }

  Future<void> deletePersonalSchedule(String id) async {
    await _db
        .collection('users')
        .doc(currentUserId)
        .collection('personal_schedules')
        .doc(id)
        .delete();
  }

  /// 모든 다가오는 개인 일정을 알림 서비스에 등록 (기기 변경/재설치 시 유용)
  Future<void> syncPersonalNotifications(String bodyText) async {
    if (currentUserId.isEmpty) return;
    
    final now = DateTime.now();
    final snap = await _db
        .collection('users')
        .doc(currentUserId)
        .collection('personal_schedules')
        .where('start_time', isGreaterThan: now)
        .get();

    final notif = NotificationService();
    for (var doc in snap.docs) {
      final s = Schedule.fromFirestore(doc);
      await notif.scheduleNotification(
        id: NotificationService.notificationId(s.id),
        title: s.title,
        body: bodyText,
        scheduledTime: s.startTime,
      );
    }
  }
}
