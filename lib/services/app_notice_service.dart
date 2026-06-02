import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notice.dart';
import 'local_preferences_service.dart';

class AppNoticeService {
  AppNoticeService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<AppNotice?> fetchStartupNotice() async {
    try {
      final snap = await _db
          .collection('app_notices')
          .where('is_active', isEqualTo: true)
          .get();

      final List<AppNotice> allNotices = snap.docs.map(AppNotice.fromFirestore).toList();

      if (allNotices.isEmpty) return null;

      allNotices.sort(_compareNotices);

      final now = DateTime.now();
      for (final notice in allNotices) {
        // 이미 만료된 공지는 앱 내에서 걸러줍니다.
        if (notice.expiredAt != null && notice.expiredAt!.isBefore(now)) {
          continue;
        }

        final prefsKey = LocalPreferencesService.appNoticeReadKey(
          notice.id,
          notice.updatedAt,
        );
        final prefs = await SharedPreferences.getInstance();
        final isRead = prefs.getBool(prefsKey) == true;

        if (!isRead) {
          return notice;
        }
      }
    } catch (e) {
      debugPrint('fetchStartupNotice error: $e');
    }

    return null;
  }

  Future<void> markAsRead(AppNotice notice) async {
    final prefsKey = LocalPreferencesService.appNoticeReadKey(notice.id, notice.updatedAt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, true);
  }

  int _compareNotices(AppNotice a, AppNotice b) {
    final priorityDiff = b.priority.compareTo(a.priority);
    if (priorityDiff != 0) return priorityDiff;

    final updatedDiff = _millis(b.updatedAt).compareTo(_millis(a.updatedAt));
    if (updatedDiff != 0) return updatedDiff;

    return b.id.compareTo(a.id);
  }

  int _millis(DateTime? value) => value?.millisecondsSinceEpoch ?? 0;
}
