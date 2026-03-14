import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BlockService {
  final _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── 내 차단 목록 컬렉션 ref ───────────────────────────────────────────────
  CollectionReference get _blockedRef =>
      _db.collection('users').doc(_uid).collection('blocked');

  // ── 차단 ─────────────────────────────────────────────────────────────────
  Future<void> blockUser(String targetUid, String displayName) async {
    await _blockedRef.doc(targetUid).set({
      'display_name': displayName,
      'blocked_at': FieldValue.serverTimestamp(),
    });
  }

  // ── 차단 해제 ─────────────────────────────────────────────────────────────
  Future<void> unblockUser(String targetUid) async {
    await _blockedRef.doc(targetUid).delete();
  }

  // ── 차단 여부 단일 확인 ──────────────────────────────────────────────────
  Future<bool> isBlocked(String targetUid) async {
    final doc = await _blockedRef.doc(targetUid).get();
    return doc.exists;
  }

  // ── 차단 목록 스트림 ─────────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getBlockedUsers() {
    return _blockedRef
        .orderBy('blocked_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              return {'uid': d.id, ...data};
            }).toList());
  }

  // ── 차단 uid Set 스트림 (채팅 필터용) ────────────────────────────────────
  Stream<Set<String>> getBlockedUidSet() {
    return _blockedRef.snapshots().map(
        (snap) => snap.docs.map((d) => d.id).toSet());
  }

  // ── 그룹 차단 여부 확인 ──────────────────────────────────────────────────
  Future<bool> isGroupBanned(String groupId) async {
    final doc = await _db
        .collection('groups').doc(groupId)
        .collection('banned').doc(_uid)
        .get();
    return doc.exists;
  }
}