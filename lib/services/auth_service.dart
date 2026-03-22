import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static const _keyIsRegistered = 'auth_is_registered';
  static const _keyRegisteredUid = 'auth_registered_uid';

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _verificationId;

  bool? _isRegisteredUser;
  bool? get isRegisteredUser => _isRegisteredUser;

  // Google 로그인 후 가져온 displayName — RegistrationScreen 자동 입력용
  String? _pendingDisplayName;
  String? get pendingDisplayName => _pendingDisplayName;

  AuthService() {
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        // 1) SharedPreferences 캐시 즉시 확인
        final prefs = await SharedPreferences.getInstance();
        final cachedUid = prefs.getString(_keyRegisteredUid);
        final cachedRegistered = prefs.getBool(_keyIsRegistered);

        if (cachedUid == user.uid && cachedRegistered != null) {
          _isRegisteredUser = cachedRegistered;
          notifyListeners();
        }

        // 2) 백그라운드에서 Firestore 최신화
        await _checkAndSetRegisteredUser(user.uid);
      } else {
        _isRegisteredUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _checkAndSetRegisteredUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final registered = doc.exists;

      _isRegisteredUser = registered;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsRegistered, registered);
      await prefs.setString(_keyRegisteredUid, uid);

      if (registered) {
        await _db.collection('users').doc(uid).update({
          'last_login': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error checking user doc: $e');
      if (_isRegisteredUser == null) {
        _isRegisteredUser = false;
        notifyListeners();
      }
    }
  }

  // ── 전화번호 인증 ────────────────────────────────────────────────────────────
  Future<void> verifyPhoneNumber(
      String phoneNumber,
      Function(String error) onError,
      Function() onCodeSent) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Verification failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          onCodeSent();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<bool> verifyOTP(String smsCode) async {
    if (_verificationId == null) return false;
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user != null;
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      return false;
    }
  }

  // ── Google 로그인 ────────────────────────────────────────────────────────────
  /// 반환값: 'ok' | 'cancel' | 'error'
  Future<String> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return 'cancel';

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // 신규 유저라면 Google displayName을 RegistrationScreen에서 쓸 수 있게 저장
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        _pendingDisplayName = googleUser.displayName;
      }

      return 'ok';
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return 'error';
    }
  }

  // ── 신규 유저 등록 ──────────────────────────────────────────────────────────
  Future<bool> registerUser({
    required String name,
    required String locale,
    required String timezone,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    try {
      await _db.collection('users').doc(user.uid).set({
        'phone_number': user.phoneNumber ?? '',
        'name': name,
        'locale': locale,
        'timezone': timezone,
        'total_unread': 0,
        'created_at': FieldValue.serverTimestamp(),
        'last_login': FieldValue.serverTimestamp(),
        // Google 로그인이면 Google 프로필 사진 자동 저장
        'profile_image': user.photoURL ?? '',
        'fcm_token': '',
      });

      _isRegisteredUser = true;
      _pendingDisplayName = null;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsRegistered, true);
      await prefs.setString(_keyRegisteredUid, user.uid);

      return true;
    } catch (e) {
      debugPrint('Error registering user: $e');
      return false;
    }
  }

  // ── 로그아웃 ────────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsRegistered);
    await prefs.remove(_keyRegisteredUid);

    await _googleSignIn.signOut();
    await _auth.signOut();

    _isRegisteredUser = null;
    _pendingDisplayName = null;
    notifyListeners();
  }
}