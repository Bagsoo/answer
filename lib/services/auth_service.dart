import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../config/env_config.dart';

class AuthService extends ChangeNotifier {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  bool get _isFirebaseSupported => 
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || 
      defaultTargetPlatform == TargetPlatform.iOS || 
      defaultTargetPlatform == TargetPlatform.windows;

  GoogleSignIn? _googleSignIn;

  static const _keyIsRegistered = 'auth_is_registered';
  static const _keyRegisteredUid = 'auth_registered_uid';

  User? get currentUser {
    if (!_isFirebaseSupported) return null;
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  Stream<User?> get authStateChanges {
    if (!_isFirebaseSupported) return Stream.value(null);
    return _auth.authStateChanges();
  }

  String? _verificationId;
  bool? _isRegisteredUser;
  bool? get isRegisteredUser => _isRegisteredUser;
  String? _pendingDisplayName;
  String? get pendingDisplayName => _pendingDisplayName;

  static const _providerGoogle = 'google.com';
  static const _providerApple = 'apple.com';
  static const _providerPhone = 'phone';

  AuthService() {
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    
    if (isMobile) {
       _googleSignIn = GoogleSignIn();
    } else if (kIsWeb) {
       _googleSignIn = GoogleSignIn(clientId: EnvConfig.googleClientId);
    }

    if (_isFirebaseSupported) {
      _auth.authStateChanges().listen((user) async {
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          final cachedUid = prefs.getString(_keyRegisteredUid);
          final cachedRegistered = prefs.getBool(_keyIsRegistered);

          if (cachedUid == user.uid && cachedRegistered != null) {
            _isRegisteredUser = cachedRegistered;
            notifyListeners();
          }
          await _checkAndSetRegisteredUser(user.uid);
        } else {
          _isRegisteredUser = null;
          notifyListeners();
        }
      });
    }
  }

  Future<void> _checkAndSetRegisteredUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final registered = doc.exists && (doc.data()?['account_status'] as String? ?? 'active') == 'active';
      _isRegisteredUser = registered;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsRegistered, registered);
      await prefs.setString(_keyRegisteredUid, uid);

      if (registered) {
        await _db.collection('users').doc(uid).update({
          'last_login': FieldValue.serverTimestamp(),
        });
        
        final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
        if (isMobile) {
          await _syncLinkedAuthState();
        } else {
          await _syncLinkedAuthStateForDesktop();
        }
      }
    } catch (_) {}
  }

  Future<void> _syncLinkedAuthStateForDesktop() async {
    final u = currentUser;
    if (u == null) return;
    final userRef = _db.collection('users').doc(u.uid);
    await userRef.set({
      'last_login': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Windows PKCE Login
  Future<Map<String, String?>?> _performWindowsPkceLogin() async {
    final googleClientId = ClientId(EnvConfig.googleClientId, '');
    final scopes = ['email', 'profile', 'openid'];
    try {
      final client = await clientViaUserConsent(googleClientId, scopes, (url) async {
        await url_launcher.launchUrl(Uri.parse(url), mode: url_launcher.LaunchMode.externalApplication);
      });
      return {
        'idToken': client.credentials.idToken,
        'accessToken': client.credentials.accessToken.data,
      };
    } catch (e) {
      debugPrint('PKCE Login error: $e');
      return null;
    }
  }

  Future<String> signInWithGoogle() async {
    try {
      String? idToken;
      String? accessToken;
      String? displayName;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final res = await _performWindowsPkceLogin();
        if (res == null) return 'cancel';
        idToken = res['idToken'];
        accessToken = res['accessToken'];
      } else {
        final googleUser = await _googleSignIn?.signIn();
        if (googleUser == null) return 'cancel';
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
        accessToken = googleAuth.accessToken;
        displayName = googleUser.displayName;
      }

      if (idToken == null) return 'error';
      final credential = GoogleAuthProvider.credential(accessToken: accessToken, idToken: idToken);
      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.additionalUserInfo?.isNewUser == true) {
        _pendingDisplayName = displayName;
      } else {
        await _syncLinkedAuthState(user: userCredential.user, lastSignInProvider: _providerGoogle);
      }
      return 'ok';
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return 'error';
    }
  }

  Future<void> verifyPhoneNumber(String phoneNumber, Function(String error) onError, Function() onCodeSent, {VoidCallback? onAutoLinked}) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      onError('데스크톱 앱에서는 지원되지 않습니다. 모바일에서 계정을 연결해 주세요.');
      return;
    }
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          final current = currentUser;
          if (current != null) {
            if (!_providerIds(current).contains(_providerPhone)) await current.linkWithCredential(credential);
          } else {
            await _auth.signInWithCredential(credential);
          }
          await _syncLinkedAuthState(user: currentUser, lastSignInProvider: _providerPhone);
          onAutoLinked?.call();
        },
        verificationFailed: (e) => onError(e.message ?? 'Verification failed'),
        codeSent: (id, _) { _verificationId = id; onCodeSent(); },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
    } catch (e) { onError(e.toString()); }
  }

  Future<String?> verifyOTP(String smsCode) async {
    if (_verificationId == null) return '인증 세션 만료';
    try {
      final credential = PhoneAuthProvider.credential(verificationId: _verificationId!, smsCode: smsCode);
      final current = currentUser;
      User? user;
      if (current != null) {
        if (_providerIds(current).contains(_providerPhone)) return null;
        final uc = await current.linkWithCredential(credential);
        user = uc.user;
      } else {
        final uc = await _auth.signInWithCredential(credential);
        user = uc.user;
      }
      if (user == null) return '인증 실패';
      await _syncLinkedAuthState(user: user, lastSignInProvider: _providerPhone);
      _verificationId = null;
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<bool> registerUser({required String name, required String locale, required String timezone, required bool termsAgreed, required bool privacyAgreed}) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      final userRef = _db.collection('users').doc(user.uid);
      await userRef.set({
        'name': name, 'locale': locale, 'timezone': timezone, 'account_status': 'active',
        'profile_image': user.photoURL ?? '', 'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _isRegisteredUser = true;
      _pendingDisplayName = null;
      notifyListeners();
      await _syncLinkedAuthState(user: user);
      return true;
    } catch (e) { return false; }
  }

  Future<void> _syncLinkedAuthState({User? user, String? lastSignInProvider}) async {
    final u = user ?? currentUser;
    if (u == null) return;
    final ids = _providerIds(u);
    await _db.collection('users').doc(u.uid).set({
      'linked_google': ids.contains(_providerGoogle),
      'linked_apple': ids.contains(_providerApple),
      'linked_phone': ids.contains(_providerPhone),
      'last_sign_in_provider': lastSignInProvider,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Set<String> _providerIds(User user) => user.providerData.map((p) => p.providerId).toSet();

  Future<void> markCurrentUserPhoneIndexDeleted() async {
    final user = currentUser;
    if (user == null) return;
    final phone = user.phoneNumber;
    if (phone != null) await _db.collection('phone_index').doc(phone).set({'is_deleted': true}, SetOptions(merge: true));
  }

  Future<String?> linkGoogleProvider() async {
    final user = currentUser;
    if (user == null) return 'No user';
    try {
      final res = await _performWindowsPkceLogin();
      if (res == null) return 'cancel';
      final credential = GoogleAuthProvider.credential(accessToken: res['accessToken'], idToken: res['idToken']);
      await user.linkWithCredential(credential);
      await _syncLinkedAuthState(user: currentUser);
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<String?> unlinkProvider(String providerId) async {
    final user = currentUser;
    if (user == null) return 'No user';
    try {
      await user.unlink(providerId);
      await _syncLinkedAuthState(user: currentUser);
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<String?> setPreferredLoginProvider(String providerId) async {
    final user = currentUser;
    if (user == null) return 'No user';
    try {
      await _db.collection('users').doc(user.uid).update({'preferred_login_provider': providerId});
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _googleSignIn?.signOut();
    if (_isFirebaseSupported) await _auth.signOut();
    _isRegisteredUser = null;
    notifyListeners();
  }
}
