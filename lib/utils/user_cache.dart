import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── 유저 프로필 메모리 캐시 (Micro-batching / DataLoader) ────────────────────────
class UserCache {
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final Map<String, Completer<Map<String, dynamic>>> _inFlight = {};
  static final Set<String> _pendingUids = {};
  static Timer? _batchTimer;

  static Future<Map<String, dynamic>> get(String uid) {
    if (_cache.containsKey(uid)) return Future.value(_cache[uid]!);
    if (_inFlight.containsKey(uid)) return _inFlight[uid]!.future;

    final completer = Completer<Map<String, dynamic>>();
    _inFlight[uid] = completer;
    _pendingUids.add(uid);

    _batchTimer?.cancel();
    // 1프레임(약 16ms) 동안 발생한 렌더링 요청을 모아서 처리
    _batchTimer = Timer(const Duration(milliseconds: 16), _executeBatch);

    return completer.future;
  }

  static Map<String, dynamic>? getCached(String uid) => _cache[uid];

  static Future<void> prefetch(Iterable<String> uids) async {
    final toFetch = uids
        .where((uid) => !_cache.containsKey(uid) && !_inFlight.containsKey(uid))
        .toSet();
    if (toFetch.isEmpty) return;

    for (var uid in toFetch) {
      _inFlight[uid] = Completer<Map<String, dynamic>>();
      _pendingUids.add(uid);
    }

    _batchTimer?.cancel();
    // Prefetch는 즉시 실행
    _executeBatch();
  }

  static Future<void> _executeBatch() async {
    final uidsToFetch = _pendingUids.toList();
    _pendingUids.clear();

    if (uidsToFetch.isEmpty) return;

    // Firestore whereIn은 최대 10개까지 허용
    for (var i = 0; i < uidsToFetch.length; i += 10) {
      final chunk = uidsToFetch.skip(i).take(10).toList();
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final isDeleted =
              (doc.data()['account_status'] as String? ?? 'active') == 'deleted';
          final data = {
            'name': isDeleted
                ? ''
                : doc.data()['name'] as String? ??
                    doc.data()['display_name'] as String? ??
                    '',
            'photo': isDeleted ? '' : doc.data()['profile_image'] as String? ?? '',
            'is_deleted': isDeleted,
          };
          _cache[doc.id] = data;
          _inFlight[doc.id]?.complete(data);
          _inFlight.remove(doc.id);
        }

        // DB에 존재하지 않는 유저 처리 방어 로직
        for (final uid in chunk) {
          if (_inFlight.containsKey(uid)) {
            final empty = {'name': '', 'photo': '', 'is_deleted': false};
            _cache[uid] = empty;
            _inFlight[uid]?.complete(empty);
            _inFlight.remove(uid);
          }
        }
      } catch (e) {
        // 네트워크 장애 시 안전판 (무한 대기 방지)
        for (final uid in chunk) {
          if (_inFlight.containsKey(uid)) {
            final empty = {'name': '', 'photo': '', 'is_deleted': false};
            _cache[uid] = empty;
            _inFlight[uid]?.complete(empty);
            _inFlight.remove(uid);
          }
        }
      }
    }
  }

  static void invalidate(String uid) => _cache.remove(uid);
}
