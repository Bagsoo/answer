import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _uid = '';
  String _name = '';
  String _phoneNumber = '';
  String _locale = 'ko';
  String _timezone = 'Asia/Seoul';
  bool _loaded = false;

  String get uid => _uid;
  String get name => _name;
  String get phoneNumber => _phoneNumber;
  String get locale => _locale;
  String get timezone => _timezone;
  bool get isLoaded => _loaded;

  // ── 로그인 후 1번만 호출 ────────────────────────────────────────────────────
  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _uid = user.uid;
    final doc = await _db.collection('users').doc(_uid).get();
    final data = doc.data();

    _name = data?['name'] as String? ?? '';
    _phoneNumber = data?['phone_number'] as String? ?? '';
    _locale = data?['locale'] as String? ?? 'ko';
    _timezone = data?['timezone'] as String? ?? 'Asia/Seoul';
    _loaded = true;

    notifyListeners();
  }

  // ── 이름 변경 시 Firestore + 로컬 상태 동기화 ──────────────────────────────
  Future<void> updateName(String newName) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'name': newName});
    _name = newName;
    notifyListeners();
  }

  Future<void> updateTimezone(String newTimezone) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'timezone': newTimezone});
    _timezone = newTimezone;
    notifyListeners();
  }

  // ── 로그아웃 시 초기화 ─────────────────────────────────────────────────────
  void clear() {
    _uid = '';
    _name = '';
    _phoneNumber = '';
    _locale = 'ko';
    _timezone = 'Asia/Seoul';
    _loaded = false;
    notifyListeners();
  }

  // ── 계정 삭제 ──────────────────────────────────────────────────────────────
  Future<void> deleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final joinedGroupsSnap = await _db.collection('users').doc(uid)
        .collection('joined_groups').get();

    final batch = _db.batch();
    for (final doc in joinedGroupsSnap.docs) {
      final groupId = doc.id;
      batch.delete(_db.collection('groups').doc(groupId).collection('members').doc(uid));
      batch.update(_db.collection('groups').doc(groupId), {'member_count': FieldValue.increment(-1)});
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('users').doc(uid));
    await batch.commit();

    await FirebaseAuth.instance.currentUser?.delete();
    clear();
  }

  
}