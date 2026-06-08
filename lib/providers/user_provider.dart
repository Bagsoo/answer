import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/user_cache.dart';
import '../services/group_cache_service.dart';
import '../services/hive_service.dart';
import '../models/user_profile_cache.dart';
import '../models/notification_settings_cache.dart';
import '../repositories/user_repository.dart';

class UserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final UserRepository _userRepo = UserRepository();

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

    // 1) 캐시 즉시 적용 (UserProfileCache에서 로드)
    final cachedProfile = await _userRepo.getCachedProfile(_uid);
    if (cachedProfile != null) {
      _name         = cachedProfile.name ?? '';
      _photoUrl     = cachedProfile.photoUrl;
      _phoneNumber  = cachedProfile.phone ?? '';
      _locationName = cachedProfile.locationName ?? '';
      _locationLat  = cachedProfile.locationLat;
      _locationLng  = cachedProfile.locationLng;
      _interests    = cachedProfile.interests ?? [];
      
      // 로케일 및 시간대는 기존대로 SharedPreferences 유지
      _locale       = prefs.getString(_keyLocale) ?? 'ko';
      _timezone     = prefs.getString(_keyTimezone) ?? 'Asia/Seoul';
      notifyListeners();
    } else {
      _locale       = prefs.getString(_keyLocale) ?? 'ko';
      _timezone     = prefs.getString(_keyTimezone) ?? 'Asia/Seoul';
      notifyListeners();
    }

    // 2) Firebase 최신 데이터 및 캐시 갱신
    final freshProfile = await _userRepo.fetchAndCacheProfile(_uid);
    if (freshProfile != null) {
      _name         = freshProfile.name ?? '';
      _photoUrl     = freshProfile.photoUrl;
      _phoneNumber  = freshProfile.phone ?? '';
      _locationName = freshProfile.locationName ?? '';
      _locationLat  = freshProfile.locationLat;
      _locationLng  = freshProfile.locationLng;
      _interests    = freshProfile.interests ?? [];
      _loaded = true;
      notifyListeners();
    }

    // Firebase 최신 locale / timezone 불러와 SharedPreferences 갱신
    final doc  = await _db.collection('users').doc(_uid).get();
    final data = doc.data();
    if (data != null) {
      if ((data['account_status'] as String? ?? 'active') == 'deleted') {
        await clear();
        return;
      }
      final locale    = data['locale']        as String? ?? 'ko';
      final timezone  = data['timezone']      as String? ?? 'Asia/Seoul';
      _locale = locale;
      _timezone = timezone;
      await prefs.setString(_keyLocale, locale);
      await prefs.setString(_keyTimezone, timezone);
      notifyListeners();
    }
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

    // 로컬 캐시 갱신
    final cache = await _userRepo.getCachedProfile(_uid) ?? UserProfileCache(uid: _uid);
    cache.locationLat = lat;
    cache.locationLng = lng;
    cache.locationName = name;
    await _userRepo.saveProfileLocal(cache);
  }

  // ── 관심사 업데이트 ──────────────────────────────────────────────────────
  Future<void> updateInterests(List<String> interests) async {
    if (_uid.isEmpty) return;
    await _db.collection('users').doc(_uid).update({'interests': interests});
    _interests = interests;
    notifyListeners();

    // 로컬 캐시 갱신
    final cache = await _userRepo.getCachedProfile(_uid) ?? UserProfileCache(uid: _uid);
    cache.interests = interests;
    await _userRepo.saveProfileLocal(cache);
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
      UserCache.invalidate(_uid);
      notifyListeners();

      // 로컬 캐시 갱신
      final cache = await _userRepo.getCachedProfile(_uid) ?? UserProfileCache(uid: _uid);
      cache.photoUrl = newUrl;
      await _userRepo.saveProfileLocal(cache);

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
          {
            'profile_image': newUrl,
            'photo_url': FieldValue.delete(),
          },
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
    UserCache.invalidate(_uid);
    notifyListeners();

    // 로컬 캐시 갱신
    final cache = await _userRepo.getCachedProfile(_uid) ?? UserProfileCache(uid: _uid);
    cache.name = newName;
    await _userRepo.saveProfileLocal(cache);
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
    final oldUid = _uid;
    _uid = ''; _name = ''; _phoneNumber = ''; _photoUrl = null;
    _locale = 'ko'; _timezone = 'Asia/Seoul';
    _locationLat = null; _locationLng = null; _locationName = '';
    _interests = [];
    _loaded = false;
    notifyListeners();

    // Hive 캐시 초기화
    await GroupCacheService.clearAll();
    if (oldUid.isNotEmpty) {
      await _userRepo.clearProfileCache(oldUid);
      final notifBox = await HiveService.openBox<NotificationSettingsCache>('notification_settings');
      await notifBox.delete(oldUid);
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _keyUid, _keyName, _keyPhone, _keyPhoto, _keyLocale, _keyTimezone,
      _keyLocationName, _keyLocationLat, _keyLocationLng, _keyInterests,
    ]) { await prefs.remove(key); }
  }

  // ── 계정 삭제 ────────────────────────────────────────────────────────────
  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;
    final providerIds = user!.providerData.map((p) => p.providerId).toSet();
    await _db.collection('users').doc(uid).set({
      'account_status': 'deleted',
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': uid,
      'search_hidden': true,
      'linked_google': false,
      'linked_apple': false,
      'linked_phone': false,
      'retention_snapshot': {
        'name': _name,
        'phone_number': _phoneNumber,
        'profile_image': _photoUrl ?? '',
        'locale': _locale,
        'timezone': _timezone,
        'linked_google': providerIds.contains('google.com'),
        'linked_apple': providerIds.contains('apple.com'),
        'linked_phone': providerIds.contains('phone'),
      },
    }, SetOptions(merge: true));
    await FirebaseAuth.instance.signOut();
    await clear();
  }
}
