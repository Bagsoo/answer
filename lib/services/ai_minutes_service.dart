import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AiMinutesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUid => _auth.currentUser?.uid ?? '';

  /// 현재 월의 사용량 문서 경로 반환 (ai_minutes_YYYY_MM)
  String _getUsageDocId() {
    final now = DateTime.now();
    return 'ai_minutes_${DateFormat('yyyy_MM').format(now)}';
  }

  /// 사용 가능 여부 확인 (월 10회 제한)
  Future<bool> checkQuota() async {
    if (_currentUid.isEmpty) return false;

    final doc = await _db
        .collection('users')
        .doc(_currentUid)
        .collection('usage')
        .doc(_getUsageDocId())
        .get();

    if (!doc.exists) return true; // 문서가 없으면 0회 사용이므로 통과

    final count = (doc.data()?['count'] as num?)?.toInt() ?? 0;
    return count < 10;
  }

  /// 사용 횟수 1회 증가
  Future<void> incrementUsage(int durationSeconds) async {
    if (_currentUid.isEmpty) return;

    final docRef = _db
        .collection('users')
        .doc(_currentUid)
        .collection('usage')
        .doc(_getUsageDocId());

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        transaction.set(docRef, {
          'count': 1,
          'total_seconds': durationSeconds,
          'last_used_at': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(docRef, {
          'count': FieldValue.increment(1),
          'total_seconds': FieldValue.increment(durationSeconds),
          'last_used_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
