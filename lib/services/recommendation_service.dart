import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum RecommendationSectionType {
  active,
  personalized,
  nearbyNew,
}

class RecommendationSections {
  final List<Map<String, dynamic>> activeGroups;
  final List<Map<String, dynamic>> personalizedGroups;
  final List<Map<String, dynamic>> nearbyNewGroups;

  const RecommendationSections({
    required this.activeGroups,
    required this.personalizedGroups,
    required this.nearbyNewGroups,
  });
}

class RecommendationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  // ── 추천 섹션 조회 ──────────────────────────────────────────────────────────
  Future<RecommendationSections> getRecommendationSections({
    int previewLimit = 8,
  }) async {
    if (_uid.isEmpty) {
      return const RecommendationSections(
        activeGroups: [],
        personalizedGroups: [],
        nearbyNewGroups: [],
      );
    }

    final data = await _loadRecommendationData();
    final personalized = _buildPersonalizedGroups(
      data.candidates,
      data.userData,
      data.joinedIds,
      limit: previewLimit,
    );
    final usedIds = personalized.map((g) => g['id'] as String? ?? '').toSet();
    final activeGroups = _buildActiveGroups(
      data.candidates,
      data.userData,
      data.joinedIds,
      excludeIds: usedIds,
      limit: previewLimit,
    );
    usedIds.addAll(activeGroups.map((g) => g['id'] as String? ?? ''));
    final nearbyNewGroups = _buildNearbyNewGroups(
      data.candidates,
      data.userData,
      data.joinedIds,
      excludeIds: usedIds,
      limit: previewLimit,
    );

    return RecommendationSections(
      activeGroups: activeGroups,
      personalizedGroups: personalized,
      nearbyNewGroups: nearbyNewGroups,
    );
  }

  Future<List<Map<String, dynamic>>> getRecommendationSectionGroups(
    RecommendationSectionType section, {
    int limit = 40,
  }) async {
    if (_uid.isEmpty) return [];
    final data = await _loadRecommendationData();
    return switch (section) {
      RecommendationSectionType.active => _buildActiveGroups(
          data.candidates,
          data.userData,
          data.joinedIds,
          limit: limit,
        ),
      RecommendationSectionType.personalized => _buildPersonalizedGroups(
          data.candidates,
          data.userData,
          data.joinedIds,
          limit: limit,
        ),
      RecommendationSectionType.nearbyNew => _buildNearbyNewGroups(
          data.candidates,
          data.userData,
          data.joinedIds,
          limit: limit,
        ),
    };
  }

  Future<_RecommendationData> _loadRecommendationData() async {
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

    final popularSnap = await _db
        .collection('groups')
        .orderBy('member_count', descending: true)
        .limit(200)
        .get();

    final recentSnap = await _db
        .collection('groups')
        .orderBy('created_at', descending: true)
        .limit(200)
        .get();

    final merged = <String, Map<String, dynamic>>{};
    for (final doc in [...popularSnap.docs, ...recentSnap.docs]) {
      final data = doc.data();
      if ((data['status'] as String? ?? 'active') == 'deleted') continue;
      data['id'] = doc.id;
      merged[doc.id] = data;
    }

    return _RecommendationData(
      userData: userData,
      userLocation: userLocation,
      userInterests: userInterests,
      viewCounts: viewCounts,
      joinAttempts: joinAttempts,
      joinedIds: joinedIds,
      candidates: merged.values.toList(),
    );
  }

  List<Map<String, dynamic>> _buildPersonalizedGroups(
    List<Map<String, dynamic>> candidates,
    Map<String, dynamic> userData,
    Set<String> joinedIds, {
    int limit = 20,
  }) {
    final scored = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final behaviorStats = userData['behavior_stats'] as Map<String, dynamic>? ?? {};
    final viewCounts = behaviorStats['view_counts'] as Map<String, dynamic>? ?? {};
    final joinAttempts = behaviorStats['join_attempts'] as Map<String, dynamic>? ?? {};
    final userLocation = userData['activity_location'] as GeoPoint?;
    final userInterests =
        List<String>.from(userData['interests'] as List? ?? []);

    for (final data in candidates) {
      final groupId = data['id'] as String? ?? '';
      if (groupId.isEmpty || joinedIds.contains(groupId)) continue;

      final groupCategory = data['category'] as String? ?? '';
      final groupType = data['type'] as String? ?? '';

      double score = 0;
      final categoryViews = (viewCounts[groupCategory] as num?)?.toDouble() ?? 0;
      final categoryJoins = (joinAttempts[groupCategory] as num?)?.toDouble() ?? 0;
      score += (categoryViews * 5).clamp(0, 15).toDouble();
      score += (categoryJoins * 10).clamp(0, 15).toDouble();

      if (userLocation != null) {
        final groupLocation = data['location'] as GeoPoint?;
        if (groupLocation != null) {
          final distKm = _distanceKm(
            userLocation.latitude,
            userLocation.longitude,
            groupLocation.latitude,
            groupLocation.longitude,
          );
          data['distance_km'] = distKm.toStringAsFixed(1);
          score += _distanceScore(distKm);
        }
      }

      if (userInterests.isNotEmpty) {
        if (userInterests.contains(groupCategory)) score += 15;
        if (userInterests.contains(groupType)) score += 5;
        final groupTags = List<String>.from(data['tags'] as List? ?? []);
        final matchCount = groupTags.where((tag) => userInterests.contains(tag)).length;
        data['matched_interest_count'] = matchCount;
        score += (matchCount * 5).clamp(0, 10).toDouble();
      }

      final memberCount = (data['member_count'] as num?)?.toInt() ?? 0;
      final memberLimit = (data['member_limit'] as num?)?.toInt() ?? 50;
      if (memberLimit > 0) {
      score += (memberCount / memberLimit * 5).clamp(0, 5).toDouble();
      }
      final createdAt = data['created_at'] as Timestamp?;
      if (createdAt != null) {
        final days = now.difference(createdAt.toDate()).inDays;
        if (days <= 14) score += 5;
        else if (days <= 30) score += 3;
      }

      data['_score'] = score;
      scored.add(Map<String, dynamic>.from(data));
    }

    scored.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));
    return scored.take(limit).toList();
  }

  List<Map<String, dynamic>> _buildActiveGroups(
    List<Map<String, dynamic>> candidates,
    Map<String, dynamic> userData,
    Set<String> joinedIds, {
    Set<String> excludeIds = const {},
    int limit = 20,
  }) {
    final scored = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final userLocation = userData['activity_location'] as GeoPoint?;

    for (final source in candidates) {
      final data = Map<String, dynamic>.from(source);
      final groupId = data['id'] as String? ?? '';
      if (groupId.isEmpty || joinedIds.contains(groupId) || excludeIds.contains(groupId)) {
        continue;
      }

      final memberCount = (data['member_count'] as num?)?.toInt() ?? 0;
      final likesCount = (data['likes_count'] as num?)?.toInt() ?? 0;
      final createdAt = data['created_at'] as Timestamp?;

      double score = 0;
      score += min(memberCount * 0.28, 24).toDouble();
      score += min(likesCount * 1.0, 20).toDouble();

      if (createdAt != null) {
        final days = now.difference(createdAt.toDate()).inDays;
        if (days <= 7) score += 18;
        else if (days <= 30) score += 10;
        else if (days <= 90) score += 5;
      }

      if (userLocation != null) {
        final groupLocation = data['location'] as GeoPoint?;
        if (groupLocation != null) {
          final distKm = _distanceKm(
            userLocation.latitude,
            userLocation.longitude,
            groupLocation.latitude,
            groupLocation.longitude,
          );
          data['distance_km'] = distKm.toStringAsFixed(1);
          score += max(0.0, 12 - distKm);
        }
      }

      data['_score'] = score;
      scored.add(data);
    }

    scored.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));
    return scored.take(limit).toList();
  }

  List<Map<String, dynamic>> _buildNearbyNewGroups(
    List<Map<String, dynamic>> candidates,
    Map<String, dynamic> userData,
    Set<String> joinedIds, {
    Set<String> excludeIds = const {},
    int limit = 20,
  }) {
    final userLocation = userData['activity_location'] as GeoPoint?;
    if (userLocation == null) return [];

    final scored = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final source in candidates) {
      final data = Map<String, dynamic>.from(source);
      final groupId = data['id'] as String? ?? '';
      if (groupId.isEmpty || joinedIds.contains(groupId) || excludeIds.contains(groupId)) {
        continue;
      }

      final createdAt = data['created_at'] as Timestamp?;
      if (createdAt == null) continue;

      final days = now.difference(createdAt.toDate()).inDays;
      if (days > 45) continue;

      final groupLocation = data['location'] as GeoPoint?;
      if (groupLocation == null) continue;

      final distKm = _distanceKm(
        userLocation.latitude,
        userLocation.longitude,
        groupLocation.latitude,
        groupLocation.longitude,
      );

      final newnessScore = max(0, 30 - (days * 1.2));
      final distanceScore = max(0, 28 - (distKm * 2.2));
      final smallGroupBonus = max(0.0, 10 - ((data['member_count'] as num?)?.toDouble() ?? 0) / 10);

      data['distance_km'] = distKm.toStringAsFixed(1);
      data['_score'] = newnessScore + distanceScore + smallGroupBonus;
      scored.add(data);
    }

    scored.sort((a, b) => (b['_score'] as double).compareTo(a['_score'] as double));
    return scored.take(limit).toList();
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

  double _distanceScore(double distanceKm) {
    if (distanceKm <= 3) {
      return 35 - (distanceKm * 1.0);
    }
    if (distanceKm <= 5) {
      return 32 - ((distanceKm - 3) * 6.5);
    }
    if (distanceKm <= 10) {
      return 19 - ((distanceKm - 5) * 2.4);
    }
    if (distanceKm <= 20) {
      return 7 - ((distanceKm - 10) * 0.35);
    }
    return 0;
  }

  double _toRad(double deg) => deg * pi / 180;
}

class _RecommendationData {
  final Map<String, dynamic> userData;
  final GeoPoint? userLocation;
  final List<String> userInterests;
  final Map<String, dynamic> viewCounts;
  final Map<String, dynamic> joinAttempts;
  final Set<String> joinedIds;
  final List<Map<String, dynamic>> candidates;

  const _RecommendationData({
    required this.userData,
    required this.userLocation,
    required this.userInterests,
    required this.viewCounts,
    required this.joinAttempts,
    required this.joinedIds,
    required this.candidates,
  });
}
