import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecommendationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  // ── 추천 그룹 목록 조회 (2차 고도화: 가중치 추천) ─────────────────────────────
  Future<List<Map<String, dynamic>>> getRecommendedGroups({
    int limit = 20,
  }) async {
    if (_uid.isEmpty) return [];

    // 1. 유저 정보 조회 (위치, 관심사, 행동 데이터, 이미 가입한 그룹)
    final userDoc = await _db.collection('users').doc(_uid).get();
    final userData = userDoc.data() ?? {};

    final userLocation = userData['activity_location'] as GeoPoint?;
    final userInterests =
        List<String>.from(userData['interests'] as List? ?? []);
    
    // 행동 데이터 (view_counts, join_attempts)
    final behaviorStats = userData['behavior_stats'] as Map<String, dynamic>? ?? {};
    final viewCounts = behaviorStats['view_counts'] as Map<String, dynamic>? ?? {};
    final joinAttempts = behaviorStats['join_attempts'] as Map<String, dynamic>? ?? {};

    final joinedSnap = await _db
        .collection('users')
        .doc(_uid)
        .collection('joined_groups')
        .get();
    final joinedIds = joinedSnap.docs.map((d) => d.id).toSet();

    // 2. 전체 그룹 조회 (최대 200개 — 이미 가입한 그룹 제외)
    final groupsSnap = await _db
        .collection('groups')
        .orderBy('member_count', descending: true)
        .limit(200)
        .get();

    final now = DateTime.now();
    final groups = <Map<String, dynamic>>[];

    for (final doc in groupsSnap.docs) {
      if (joinedIds.contains(doc.id)) continue;

      final data = doc.data();
      if ((data['status'] as String? ?? 'active') == 'deleted') continue;
      data['id'] = doc.id;

      // 점수 계산 (Total 100점 만점 설계)
      double score = 0;
      final groupCategory = data['category'] as String? ?? '';
      final groupType = data['type'] as String? ?? '';

      // ── A. 행동 데이터 점수 (최대 30점) ──
      // 자주 조회한 카테고리: 횟수당 5점 (최대 15점)
      // 가입 시도한 카테고리: 횟수당 10점 (최대 15점)
      final categoryViews = (viewCounts[groupCategory] as num?)?.toDouble() ?? 0;
      final categoryJoins = (joinAttempts[groupCategory] as num?)?.toDouble() ?? 0;
      score += (categoryViews * 5).clamp(0, 15).toDouble();
      score += (categoryJoins * 10).clamp(0, 15).toDouble();

      // ── B. 거리 점수 (최대 30점) ──
      final groupLocation = data['location'] as GeoPoint?;
      if (userLocation != null && groupLocation != null) {
        final distKm = _distanceKm(
          userLocation.latitude,
          userLocation.longitude,
          groupLocation.latitude,
          groupLocation.longitude,
        );
        if (distKm <= 5) score += 30;
        else if (distKm <= 10) score += 20;
        else if (distKm <= 30) score += 10;
        data['distance_km'] = distKm.toStringAsFixed(1);
      }

      // ── C. 관심사(Profile) 점수 (최대 20점) ──
      if (userInterests.isNotEmpty) {
        if (userInterests.contains(groupCategory)) score += 15;
        if (userInterests.contains(groupType)) score += 5;
      }

      // ── D. 태그 매칭 점수 (최대 10점) ──
      if (userInterests.isNotEmpty) {
        final groupTags = List<String>.from(data['tags'] as List? ?? []);
        final matchCount = groupTags.where((tag) => userInterests.contains(tag)).length;
        score += (matchCount * 5).clamp(0, 10).toDouble();
      }

      // ── E. 인기 및 최신성 점수 (최대 10점) ──
      final memberCount = (data['member_count'] as num?)?.toInt() ?? 0;
      final memberLimit = (data['member_limit'] as num?)?.toInt() ?? 50;
      if (memberLimit > 0) {
        score += (memberCount / memberLimit * 5).clamp(0, 5);
      }
      final createdAt = data['created_at'] as Timestamp?;
      if (createdAt != null) {
        final days = now.difference(createdAt.toDate()).inDays;
        if (days <= 14) score += 5;
        else if (days <= 30) score += 3;
      }

      data['_score'] = score;
      groups.add(data);
    }

    // 3. 점수 내림차순 정렬
    groups.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));

    return groups.take(limit).toList();
  }

  // ── Haversine 공식으로 두 좌표 간 거리 계산 (km) ─────────────────────────
  double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // 지구 반지름 (km)
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * pi / 180;
}
