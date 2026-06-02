import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
    debugPrint('--- AppNoticeService: Fetching Startup Notice (Build: $currentBuildNumber) ---');

    try {
      final now = Timestamp.now();
      
      // 보안 규칙(isVisibleAppNotice)을 통과하기 위해 쿼리를 두 개로 나눕니다.
      final results = await Future.wait([
        _db
            .collection('app_notices')
            .where('is_active', isEqualTo: true)
            .where('expired_at', isNull: true)
            .get()
            .then((snap) {
              debugPrint('AppNoticeService: Query 1 (No Expiry) returned ${snap.docs.length} docs.');
              return snap.docs.map(AppNotice.fromFirestore).toList();
            })
            .catchError((e) {
              debugPrint('AppNoticeService: Query 1 Error: $e');
              return <AppNotice>[];
            }),
        _db
            .collection('app_notices')
            .where('is_active', isEqualTo: true)
            .where('expired_at', isGreaterThan: now)
            .get()
            .then((snap) {
              debugPrint('AppNoticeService: Query 2 (Future Expiry) returned ${snap.docs.length} docs.');
              return snap.docs.map(AppNotice.fromFirestore).toList();
            })
            .catchError((e) {
              debugPrint('AppNoticeService: Query 2 Error: $e');
              return <AppNotice>[];
            }),
      ]);

      final notices = <AppNotice>[
        ...results[0],
        ...results[1],
      ];
      debugPrint('AppNoticeService: Total valid notices fetched: ${notices.length}');

      notices.sort(_compareNotices);

      for (final notice in notices) {
        final isApplicable = _isApplicableForCurrentBuild(
          notice,
          currentBuildNumber: currentBuildNumber,
        );

        if (!isApplicable) {
          debugPrint('AppNoticeService: Skipping [${notice.id}] "${notice.title}" - Not applicable for build $currentBuildNumber (Min: ${notice.minAppVersion}, Type: ${notice.noticeType.name})');
          continue;
        }

        final prefsKey = LocalPreferencesService.appNoticeReadKey(
          notice.id,
          notice.updatedAt,
        );
        final prefs = await SharedPreferences.getInstance();
        final isRead = prefs.getBool(prefsKey) == true;

        debugPrint('AppNoticeService: Checking [${notice.id}] "${notice.title}" - Key: $prefsKey, IsRead: $isRead');

        if (isRead) {
          continue;
        }

        debugPrint('AppNoticeService: >>> Target Selected: [${notice.id}] ${notice.title}');
        return notice;
      }
    } catch (e, stack) {
      debugPrint('AppNoticeService: Fatal Error during fetch: $e');
      debugPrint('Stack Trace: $stack');
    }

    debugPrint('AppNoticeService: No applicable unread notices found.');
    return null;
  }

  Future<void> markAsRead(AppNotice notice) async {
    final prefsKey = LocalPreferencesService.appNoticeReadKey(notice.id, notice.updatedAt);
    debugPrint('AppNoticeService: Marking as read - Key: $prefsKey');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
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
