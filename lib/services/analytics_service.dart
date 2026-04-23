import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._internal();
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  bool get _isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  FirebaseAnalyticsObserver getAnalyticsObserver() =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ── 유저 속성 설정 ────────────────────────────────────────────────────────
  Future<void> setUserProperties({required String uid, String? locale}) async {
    if (!_isSupported) return;
    try {
      await _analytics.setUserId(id: uid);
      if (locale != null) {
        await _analytics.setUserProperty(name: 'user_locale', value: locale);
      }
    } catch (e) {
      debugPrint('Analytics error (setUserProperties): $e');
    }
  }

  // ── 그룹 관련 이벤트 ──────────────────────────────────────────────────────

  /// 그룹 상세 조회 (관심 가중치용)
  Future<void> logViewGroup({
    required String groupId,
    required String groupName,
    required String category,
  }) async {
    if (!_isSupported) return;
    try {
      await _analytics.logEvent(
        name: 'view_group',
        parameters: {
          'group_id': groupId,
          'group_name': groupName,
          'category': category,
        },
      );

      // ── 취향 점수 Firestore 업데이트 ──
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'behavior_stats': {
            'view_counts': {
              category: FieldValue.increment(1),
            }
          }
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Analytics error (logViewGroup): $e');
    }
  }

  /// 그룹 가입 시도/성공
  Future<void> logJoinGroup({
    required String groupId,
    required String groupName,
    required String category,
  }) async {
    if (!_isSupported) return;
    try {
      await _analytics.logEvent(
        name: 'join_group',
        parameters: {
          'group_id': groupId,
          'group_name': groupName,
          'category': category,
        },
      );

      // ── 취향 점수 Firestore 업데이트 (가입은 조회보다 큰 가중치) ──
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'behavior_stats': {
            'join_attempts': {
              category: FieldValue.increment(1),
            }
          }
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Analytics error (logJoinGroup): $e');
    }
  }

  /// 그룹 검색
  Future<void> logSearchGroup(String query) async {
    if (!_isSupported) return;
    try {
      await _analytics.logSearch(searchTerm: query);
    } catch (e) {
      debugPrint('Analytics error (logSearchGroup): $e');
    }
  }

  /// 추천 그룹 클릭
  Future<void> logClickRecommendation({
    required String groupId,
    required String groupName,
    required double score,
  }) async {
    if (!_isSupported) return;
    try {
      await _analytics.logEvent(
        name: 'click_recommendation',
        parameters: {
          'group_id': groupId,
          'group_name': groupName,
          'recommendation_score': score,
        },
      );
    } catch (e) {
      debugPrint('Analytics error (logClickRecommendation): $e');
    }
  }

  // ── 화면 전환 (기본 logScreenView 활용 가능) ──────────────────────────────
  Future<void> logScreenView(String screenName) async {
    if (!_isSupported) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('Analytics error (logScreenView): $e');
    }
  }
}
