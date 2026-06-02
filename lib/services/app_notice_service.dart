import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notice.dart';
import 'local_preferences_service.dart';

class AppNoticeService {
  AppNoticeService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<AppNotice?> fetchStartupNotice({
    required int currentBuildNumber,
  }) async {
    final now = Timestamp.now();

    final results = await Future.wait([
      _fetchActiveNotices(
        query: _db
            .collection('app_notices')
            .where('is_active', isEqualTo: true)
            .where('expired_at', isNull: true),
      ),
      _fetchActiveNotices(
        query: _db
            .collection('app_notices')
            .where('is_active', isEqualTo: true)
            .where('expired_at', isGreaterThan: now)
            .orderBy('expired_at'),
      ),
    ]);

    final notices = <AppNotice>[
      ...results[0],
      ...results[1],
    ];

    notices.sort(_compareNotices);

    for (final notice in notices) {
      if (!_isApplicableForCurrentBuild(
        notice,
        currentBuildNumber: currentBuildNumber,
      )) {
        continue;
      }

      final prefsKey = LocalPreferencesService.appNoticeReadKey(
        notice.id,
        notice.updatedAt,
      );
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefsKey) == true) {
        continue;
      }

      return notice;
    }

    return null;
  }

  Future<void> markAsRead(AppNotice notice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      LocalPreferencesService.appNoticeReadKey(notice.id, notice.updatedAt),
      true,
    );
  }

  Future<List<AppNotice>> _fetchActiveNotices({
    required Query<Map<String, dynamic>> query,
  }) async {
    final snap = await query.get();
    return snap.docs.map(AppNotice.fromFirestore).toList();
  }

  int _compareNotices(AppNotice a, AppNotice b) {
    final priorityDiff = b.priority.compareTo(a.priority);
    if (priorityDiff != 0) return priorityDiff;

    final updatedDiff = _millis(b.updatedAt).compareTo(_millis(a.updatedAt));
    if (updatedDiff != 0) return updatedDiff;

    final createdDiff = _millis(b.createdAt).compareTo(_millis(a.createdAt));
    if (createdDiff != 0) return createdDiff;

    return b.id.compareTo(a.id);
  }

  bool _isApplicableForCurrentBuild(
    AppNotice notice, {
    required int currentBuildNumber,
  }) {
    if (notice.noticeType != AppNoticeType.update) {
      return true;
    }

    final minBuild = notice.minAppVersion;
    if (minBuild == null) return true;
    return currentBuildNumber < minBuild;
  }

  int _millis(DateTime? value) => value?.millisecondsSinceEpoch ?? 0;
}
