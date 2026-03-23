import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _keyUid          = 'user_uid';
  static const _keyName         = 'user_name';
  static const _keyPhone        = 'user_phone';
  static const _keyPhoto        = 'user_photo_url';
  static const _keyLocale       = 'user_locale';
  static const _keyTimezone     = 'user_timezone';
  static const _keyLocationName = 'user_location_name';
  static const _keyLocationLat  = 'user_location_lat';
  static const _keyLocationLng  = 'user_location_lng';
  static const _keyInterests    = 'user_interests';

  String  _uid          = '';
  String  _name         = '';
  String  _phoneNumber  = '';
  String? _photoUrl;
  String  _locale       = 'ko';
  String  _timezone     = 'Asia/Seoul';
  double? _locationLat;
  double? _locationLng;
  String  _locationName = '';
  List<String> _interests = [];
  bool _loaded = false;

  String  get uid          => _uid;
  String  get name         => _name;
  String  get phoneNumber  => _phoneNumber;
  String? get photoUrl     => _photoUrl;
  String  get locale       => _locale;
  String  get timezone     => _timezone;
  double? get locationLat  => _locationLat;
  double? get locationLng  => _locationLng;
  String  get locationName => _locationName;
  List<String> get interests => List.unmodifiable(_interests);
  bool    get isLoaded     => _loaded;
  bool    get hasLocation  => _locationLat != null && _locationLng != null;

  void setUser(String uid, String name, String? photoUrl, String phoneNumber,
      String locale, String timezone) {
    _uid         = uid;
    _name        = name;
    _photoUrl    = photoUrl;
    _phoneNumber = phoneNumber;
    _locale      = locale;
    _timezone    = timezone;
    notifyListeners();
  }

  // ── 로그인 후 호출 ──────────────────────────────────────────────────────────
  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _uid = user.uid;

    final prefs = await SharedPreferences.getInstance();

    // 1) 캐시 즉시 적용
    final cachedName = prefs.getString(_keyName) ?? '';
    if (cachedName.isNotEmpty) {
      _name         = cachedName;
      _photoUrl     = prefs.getString(_keyPhoto);
      _phoneNumber  = prefs.getString(_keyPhone) ?? '';
      _locale       = prefs.getString(_keyLocale) ?? 'ko';
      _timezone     = prefs.getString(_keyTimezone) ?? 'Asia/Seoul';
      _locationName = prefs.getString(_keyLocationName) ?? '';
      _locationLat  = prefs.getDouble(_keyLocationLat);
      _locationLng  = prefs.getDouble(_keyLocationLng);
      _interests    = prefs.getStringList(_keyInterests) ?? [];
      _loaded = true;
      notifyListeners();
    }

    // 2) Firebase 최신 데이터
    final doc  = await _db.collection('users').doc(_uid).get();
    final data = doc.data();
    if (data == null) return;

    final name      = data['name']          as String? ?? '';
    final phone     = data['phone_number']  as String? ?? '';
    final photo     = data['profile_image'] as String?;
    final locale    = data['locale']        as String? ?? 'ko';
    final timezone  = data['timezone']      as String? ?? 'Asia/Seoul';
    final locName   = data['activity_location_name'] as String? ?? '';
    final gp        = data['activity_location'] as GeoPoint?;
    final interests = List<String>.from(data['interests'] as List? ?? []);

    _name         = name;
    _phoneNumber  = phone;
    _photoUrl     = photo;
    _locale       = locale;
    _timezone     = timezone;
    _locationName = locName;
    _locationLat  = gp?.latitude;
    _locationLng  = gp?.longitude;
    _interests    = interests;
    _loaded = true;
    notifyListeners();

    // 3) 캐시 갱신
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
    await prefs.setString(_keyLocationName, locName);
    if (gp != null) {
      await prefs.setDouble(_keyLocationLat, gp.latitude);
      await prefs.setDouble(_keyLocationLng, gp.longitude);
    } else {
      await prefs.remove(_keyLocationLat);
      await prefs.remove(_keyLocationLng);
    }
    await prefs.setStringList(_keyInterests, interests);
  }

  // ── 활동 위치 업데이트 ───────────────────────────────────────────────────
  Future<void> updateActivityLocation({
    required double lat,
    required double lng,
    required String name,
  }) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({
      'activity_location': GeoPoint(lat, lng),
      'activity_location_name': name,
    });
    _locationLat  = lat;
    _locationLng  = lng;
    _locationName = name;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLocationLat, lat);
    await prefs.setDouble(_keyLocationLng, lng);
    await prefs.setString(_keyLocationName, name);
  }

  // ── 관심사 업데이트 ──────────────────────────────────────────────────────
  Future<void> updateInterests(List<String> interests) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'interests': interests});
    _interests = interests;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyInterests, interests);
  }

  // ── 프로필 사진 업로드 ───────────────────────────────────────────────────
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
      final snap = await _db
          .collection('users').doc(_uid).collection('friends').get();
      if (snap.docs.isEmpty) return;
      WriteBatch batch = _db.batch();
      int count = 0;
      for (final doc in snap.docs) {
        batch.update(
          _db.collection('users').doc(doc.id).collection('friends').doc(_uid),
          {'profile_image': newUrl},
        );
        if (++count == 490) {
          await batch.commit(); batch = _db.batch(); count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) { debugPrint('friends sync failed: $e'); }
  }

  Future<void> _syncProfileImageToGroups(String newUrl) async {
    try {
      final snap = await _db
          .collection('users').doc(_uid).collection('joined_groups').get();
      if (snap.docs.isEmpty) return;
      WriteBatch batch = _db.batch();
      int count = 0;
      for (final doc in snap.docs) {
        batch.update(
          _db.collection('groups').doc(doc.id).collection('members').doc(_uid),
          {'profile_image': newUrl},
        );
        if (++count == 490) {
          await batch.commit(); batch = _db.batch(); count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) { debugPrint('groups sync failed: $e'); }
  }

  // ── 이름 변경 ────────────────────────────────────────────────────────────
  Future<void> updateName(String newName) async {
    await _db.collection('users').doc(_uid).update({'name': newName});
    _name = newName;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, newName);
  }

  // ── 타임존 변경 ──────────────────────────────────────────────────────────
  Future<void> updateTimezone(String newTimezone) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'timezone': newTimezone});
    _timezone = newTimezone;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimezone, newTimezone);
  }

  // ── 로그아웃 시 초기화 ───────────────────────────────────────────────────
  Future<void> clear() async {
    _uid = ''; _name = ''; _phoneNumber = ''; _photoUrl = null;
    _locale = 'ko'; _timezone = 'Asia/Seoul';
    _locationLat = null; _locationLng = null; _locationName = '';
    _interests = [];
    _loaded = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _keyUid, _keyName, _keyPhone, _keyPhoto, _keyLocale, _keyTimezone,
      _keyLocationName, _keyLocationLat, _keyLocationLng, _keyInterests,
    ]) { await prefs.remove(key); }
  }

  // ── 계정 삭제 ────────────────────────────────────────────────────────────
  Future<void> deleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await _db
        .collection('users').doc(uid).collection('joined_groups').get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      final groupId = doc.id;
      batch.delete(_db.collection('groups').doc(groupId)
          .collection('members').doc(uid));
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