import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _keyUid = 'user_uid';
  static const _keyName = 'user_name';
  static const _keyPhone = 'user_phone';
  static const _keyPhoto = 'user_photo_url';
  static const _keyLocale = 'user_locale';
  static const _keyTimezone = 'user_timezone';

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

  void setUser(String uid, String name, String? photoUrl, String phoneNumber,
      String locale, String timezone) {
    _uid = uid;
    _name = name;
    _photoUrl = photoUrl;
    _phoneNumber = phoneNumber;
    _locale = locale;
    _timezone = timezone;
    notifyListeners();
  }

  // ── 로그인 후 호출 ──────────────────────────────────────────────────────────
  // 1) SharedPreferences 캐시 즉시 적용 → UI 즉시 표시
  // 2) Firebase 최신 데이터 fetch → 변경 시 갱신
  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _uid = user.uid;

    final prefs = await SharedPreferences.getInstance();

    // 1) 로컬 캐시 즉시 적용
    final cachedName = prefs.getString(_keyName) ?? '';
    if (cachedName.isNotEmpty) {
      _name = cachedName;
      _photoUrl = prefs.getString(_keyPhoto);
      _phoneNumber = prefs.getString(_keyPhone) ?? '';
      _locale = prefs.getString(_keyLocale) ?? 'ko';
      _timezone = prefs.getString(_keyTimezone) ?? 'Asia/Seoul';
      _loaded = true;
      notifyListeners(); // 캐시로 즉시 UI 업데이트
    }

    // 2) Firebase 최신 데이터 fetch
    final doc = await _db.collection('users').doc(_uid).get();
    final data = doc.data();
    if (data == null) return;

    final name = data['name'] as String? ?? '';
    final phone = data['phone_number'] as String? ?? '';
    final photo = data['profile_image'] as String?;
    final locale = data['locale'] as String? ?? 'ko';
    final timezone = data['timezone'] as String? ?? 'Asia/Seoul';

    _name = name;
    _phoneNumber = phone;
    _photoUrl = photo;
    _locale = locale;
    _timezone = timezone;
    _loaded = true;
    notifyListeners();

    // 3) 로컬 캐시 갱신
    await prefs.setString(_keyUid, _uid);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyPhone, phone);
    if (photo != null) {
      await prefs.setString(_keyPhoto, photo);
    } else {
      await prefs.remove(_keyPhoto);
    }
    await prefs.setString(_keyLocale, locale);
    await prefs.setString(_keyTimezone, timezone);
  }

  // ── 프로필 사진 업로드 + friends/groups 동기화 ──────────────────────────────
  Future<void> updateProfileImage(File compressedFile) async {
    try {
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        try {
          final oldRef = FirebaseStorage.instance.refFromURL(_photoUrl!);
          await oldRef.delete();
        } catch (e) {
          debugPrint('기존 이미지 삭제 실패(무시): $e');
        }
      }

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_profiles')
          .child('${_uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await storageRef.putFile(compressedFile);
      final newUrl = await storageRef.getDownloadURL();

      await _db.collection('users').doc(_uid).update({'profile_image': newUrl});

      _photoUrl = newUrl;
      notifyListeners();

      // 로컬 캐시 갱신
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPhoto, newUrl);

      await _syncProfileImageToFriends(newUrl);
      await _syncProfileImageToGroups(newUrl);
    } catch (e) {
      debugPrint('Upload Error: $e');
      rethrow;
    }
  }

  Future<void> _syncProfileImageToFriends(String newUrl) async {
    try {
      final friendsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('friends')
          .get();
      if (friendsSnap.docs.isEmpty) return;

      WriteBatch batch = _db.batch();
      int count = 0;
      for (final friendDoc in friendsSnap.docs) {
        final ref = _db
            .collection('users')
            .doc(friendDoc.id)
            .collection('friends')
            .doc(_uid);
        batch.update(ref, {'profile_image': newUrl});
        count++;
        if (count == 490) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      debugPrint('friends profile_image sync failed: $e');
    }
  }

  Future<void> _syncProfileImageToGroups(String newUrl) async {
    try {
      final joinedGroupsSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('joined_groups')
          .get();
      if (joinedGroupsSnap.docs.isEmpty) return;

      WriteBatch batch = _db.batch();
      int count = 0;
      for (final groupDoc in joinedGroupsSnap.docs) {
        final ref = _db
            .collection('groups')
            .doc(groupDoc.id)
            .collection('members')
            .doc(_uid);
        batch.update(ref, {'profile_image': newUrl});
        count++;
        if (count == 490) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      debugPrint('groups profile_image sync failed: $e');
    }
  }

  // ── 이름 변경 ───────────────────────────────────────────────────────────────
  Future<void> updateName(String newName) async {
    try {
      await _db.collection('users').doc(_uid).update({'name': newName});
      _name = newName;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyName, newName);
    } catch (e) {
      rethrow;
    }
  }

  // ── 타임존 변경 ─────────────────────────────────────────────────────────────
  Future<void> updateTimezone(String newTimezone) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'timezone': newTimezone});
    _timezone = newTimezone;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimezone, newTimezone);
  }

  // ── 로그아웃 시 초기화 ──────────────────────────────────────────────────────
  Future<void> clear() async {
    _uid = '';
    _name = '';
    _phoneNumber = '';
    _photoUrl = null;
    _locale = 'ko';
    _timezone = 'Asia/Seoul';
    _loaded = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUid);
    await prefs.remove(_keyName);
    await prefs.remove(_keyPhone);
    await prefs.remove(_keyPhoto);
    await prefs.remove(_keyLocale);
    await prefs.remove(_keyTimezone);
  }

  // ── 계정 삭제 ───────────────────────────────────────────────────────────────
  Future<void> deleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final joinedGroupsSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('joined_groups')
        .get();

    final batch = _db.batch();
    for (final doc in joinedGroupsSnap.docs) {
      final groupId = doc.id;
      batch.delete(_db
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(uid));
      batch.update(_db.collection('groups').doc(groupId),
          {'member_count': FieldValue.increment(-1)});
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('users').doc(uid));
    await batch.commit();

    await FirebaseAuth.instance.currentUser?.delete();
    await clear();
  }
}