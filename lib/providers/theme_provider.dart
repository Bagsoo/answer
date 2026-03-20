import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _keyTheme = 'app_theme';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  String get themeModeCode {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  /// 생성자에서 SharedPreferences 즉시 로드
  /// → 앱 시작 시 Firebase 응답 전에 이전 테마 즉시 적용 (깜빡임 없음)
  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyTheme);
    if (saved != null) {
      _themeMode = _fromCode(saved);
      notifyListeners();
    }
  }

  /// 로그인 후 Firebase에서 최신 테마 설정 fetch → 로컬 캐시 갱신
  Future<void> loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final themeCode = doc.data()?['theme'] as String? ?? 'system';
    _themeMode = _fromCode(themeCode);
    notifyListeners();

    // 로컬 캐시 갱신
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, themeCode);
  }

  /// 테마 변경 + Firebase 저장 + 로컬 캐시 갱신
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    // 로컬 캐시 즉시 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, themeModeCode);

    // Firebase 저장
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'theme': themeModeCode});
  }

  /// 로그아웃 시 초기화 (로컬 캐시는 유지)
  void reset() {
    _themeMode = ThemeMode.system;
    notifyListeners();
  }

  ThemeMode _fromCode(String code) {
    switch (code) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}