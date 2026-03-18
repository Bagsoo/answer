import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _uid = '';
  String _name = '';
  String _phoneNumber = '';
  String? _photoUrl;
  String _locale = 'ko';
  String _timezone = 'Asia/Seoul';
  bool _loaded = false;

  String get uid => _uid;
  String get name => _name;
  String get phoneNumber => _phoneNumber;
  String? get photoUrl => _photoUrl;
  String get locale => _locale;
  String get timezone => _timezone;
  bool get isLoaded => _loaded;

  // 유저 정보 초기화 로직
  void setUser(String uid, String name, String? photoUrl, String phoneNumber, String locale, String timezone) {
    _uid = uid;
    _name = name;
    _photoUrl = photoUrl;
    _phoneNumber = phoneNumber;
    _locale = locale;
    _timezone = timezone;
    notifyListeners();
  }

  // ── 로그인 후 1번만 호출 ────────────────────────────────────────────────────
  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _uid = user.uid;
    final doc = await _db.collection('users').doc(_uid).get();
    final data = doc.data();

    _name = data?['name'] as String? ?? '';
    _phoneNumber = data?['phone_number'] as String? ?? '';
    _photoUrl = data?['photo_url'] as String?;
    _locale = data?['locale'] as String? ?? 'ko';
    _timezone = data?['timezone'] as String? ?? 'Asia/Seoul';
    _loaded = true;

    notifyListeners();
  }

  // ── 프로필 사진 ─────────────────────────────────────────────────────────
  Future<void> updateProfileImage(File compressedFile) async {
    try {
      // 1. 기존 이미지가 있다면 Storage에서 삭제 (비용 절감)
      if (_photoUrl != null) {
        try {
          final oldRef = FirebaseStorage.instance.refFromURL(_photoUrl!);
          await oldRef.delete();
        } catch (e) {
          debugPrint("기존 이미지 삭제 실패(무시 가능): $e");
        }
      }

      // 2. Storage 업로드 (파일명에 타임스탬프를 붙여 고유성 확보)
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_profiles')
          .child('$_uid\_${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(compressedFile);

      // 3. 새로운 URL 획득
      final newUrl = await storageRef.getDownloadURL();

      // 4. Firestore 본인 정보 업데이트
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .update({'photo_url': newUrl});

      // 5. 로컬 상태 갱신
      _photoUrl = newUrl;
      notifyListeners();
    } catch (e) {
      debugPrint("Upload Error: $e");
      rethrow;
    }
  }

  // ── 이름 변경 시 Firestore + 로컬 상태 동기화 ──────────────────────────────
  Future<void> updateName(String newName) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .update({'display_name': newName});
      
      _name = newName;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
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