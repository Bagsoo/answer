import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  // 앱 시작 시 Firestore에서 유저의 locale 읽어오기
  Future<void> loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final localeCode = doc.data()?['locale'] as String? ?? 'en';
    _locale = Locale(localeCode);
    notifyListeners();
  }

  // 언어 변경 + Firestore 저장
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'locale': locale.languageCode});
  }

  // 로그아웃 시 초기화
  void reset() {
    _locale = const Locale('en');
    notifyListeners();
  }
}