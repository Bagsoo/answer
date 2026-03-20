import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const _keyLocale = 'app_locale';

  Locale _locale = const Locale('ko');

  Locale get locale => _locale;

  /// 생성자에서 SharedPreferences 즉시 로드
  /// → 앱 시작 시 Firebase 응답 전에 이전 언어 즉시 적용 (깜빡임 없음)
  LocaleProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyLocale);
    if (saved != null && saved.isNotEmpty) {
      _locale = Locale(saved);
      notifyListeners();
    }
  }

  /// 로그인 후 Firebase에서 최신 언어 설정 fetch → 로컬 캐시 갱신
  Future<void> loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final localeCode = doc.data()?['locale'] as String? ?? 'ko';
    _locale = Locale(localeCode);
    notifyListeners();

    // 로컬 캐시 갱신
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, localeCode);
  }

  /// 언어 변경 + Firebase 저장 + 로컬 캐시 갱신
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();

    // 로컬 캐시 즉시 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale.languageCode);

    // Firebase 저장
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'locale': locale.languageCode});
  }

  /// 로그아웃 시 초기화 (로컬 캐시는 유지 — 다음 앱 시작에도 쓸 수 있음)
  void reset() {
    _locale = const Locale('ko');
    notifyListeners();
  }
}