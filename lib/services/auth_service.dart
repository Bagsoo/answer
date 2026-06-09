import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../config/env_config.dart';
import 'analytics_service.dart';
import '../models/auth_meta.dart';
import 'hive_service.dart';

class AuthService extends ChangeNotifier {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  bool get _isFirebaseSupported => 
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || 
      defaultTargetPlatform == TargetPlatform.iOS || 
      defaultTargetPlatform == TargetPlatform.windows;

  GoogleSignIn? _googleSignIn;

  Future<void> setLastUsedProvider(String provider) async {
    final box = await HiveService.openBox<AuthMeta>('auth_meta');
    final meta = box.get('current') ?? AuthMeta();
    meta.lastUsedProvider = provider;
    await box.put('current', meta);
  }

  Future<String?> getLastUsedProvider() async {
    final box = await HiveService.openBox<AuthMeta>('auth_meta');
    final meta = box.get('current');
    return meta?.lastUsedProvider;
  }

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
  String? _pendingSignInProvider;

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
          final box = await HiveService.openBox<AuthMeta>('auth_meta');
          final meta = box.get('current');

          if (meta != null && meta.registeredUid == user.uid && meta.isRegistered != null) {
            _isRegisteredUser = meta.isRegistered;
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
      final data = doc.data() ?? {};
      final registered = doc.exists && (data['account_status'] as String? ?? 'active') == 'active';
      _isRegisteredUser = registered;
      notifyListeners();

      final locale = data['locale'] as String?;
      final analytics = AnalyticsService();
      await analytics.setUserProperties(uid: uid, locale: locale);

      final box = await HiveService.openBox<AuthMeta>('auth_meta');
      final meta = box.get('current') ?? AuthMeta();
      meta.isRegistered = registered;
      meta.registeredUid = uid;
      await box.put('current', meta);

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
      await setLastUsedProvider(_providerGoogle);

      if (userCredential.additionalUserInfo?.isNewUser == true) {
        _pendingDisplayName = displayName;
        _pendingSignInProvider = _providerGoogle;
      } else {
        await _syncLinkedAuthState(user: userCredential.user, lastSignInProvider: _providerGoogle);
      }
      return 'ok';
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return 'error';
    }
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  Future<String> signInWithApple() async {
    try {
      final rawNonce = generateNonce(length: 32);
      final nonce = _sha256ofString(rawNonce);
      final isWeb = kIsWeb;
      final supportsWebFlow =
          EnvConfig.appleServiceId.isNotEmpty && EnvConfig.appleRedirectUri.isNotEmpty;

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
        webAuthenticationOptions: (isWeb || defaultTargetPlatform == TargetPlatform.android)
            ? (supportsWebFlow
                ? WebAuthenticationOptions(
                    clientId: EnvConfig.appleServiceId,
                    redirectUri: Uri.parse(EnvConfig.appleRedirectUri),
                  )
                : null)
            : null,
      );

      final idToken = credential.identityToken;
      if (idToken == null) return 'error';

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      await setLastUsedProvider(_providerApple);
      
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        _pendingDisplayName = credential.givenName != null 
            ? '${credential.givenName} ${credential.familyName ?? ''}'.trim()
            : null;
        _pendingSignInProvider = _providerApple;
      } else {
        await _syncLinkedAuthState(user: userCredential.user, lastSignInProvider: _providerApple);
      }
      return 'ok';
    } on FirebaseAuthException catch (e) {
      final detail = _describeAppleAuthException(e);
      debugPrint('Apple sign in error: $detail');
      return 'error:$detail';
    } catch (e) {
      debugPrint('Apple sign in error: ${e.runtimeType}: $e');
      return 'error:${e.runtimeType}: $e';
    }
  }

  String _describeAppleAuthException(FirebaseAuthException e) {
    final message = e.message ?? 'unknown error';
    switch (e.code) {
      case 'operation-not-allowed':
        return 'Apple 로그인이 Firebase Console에서 아직 활성화되지 않았습니다. (${e.code})';
      case 'invalid-credential':
        return 'Apple 인증 토큰이 Firebase에서 거부되었습니다. Service ID, redirect URI, nonce 설정을 확인하세요. (${e.code})';
      case 'account-exists-with-different-credential':
        return '이 이메일은 이미 다른 로그인 방식으로 가입되어 있습니다. 계정 연결이 필요합니다. (${e.code})';
      case 'email-already-in-use':
        return '이 이메일은 이미 사용 중입니다. 기존 계정으로 로그인하거나 계정을 연결하세요. (${e.code})';
      default:
        return 'FirebaseAuthException(${e.code}): $message';
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
      UserCredential? uc;
      if (current != null) {
        if (_providerIds(current).contains(_providerPhone)) return null;
        uc = await current.linkWithCredential(credential);
        user = uc.user;
      } else {
        uc = await _auth.signInWithCredential(credential);
        user = uc.user;
      }
      if (user == null) return '인증 실패';
      
      final isNewUser = current == null && (uc.additionalUserInfo?.isNewUser ?? false);
      if (isNewUser) {
        _pendingSignInProvider = _providerPhone;
      } else {
        await _syncLinkedAuthState(user: user, lastSignInProvider: _providerPhone);
      }
      
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
        'profile_image': user.photoURL ?? '', 
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (_pendingSignInProvider != null) {
        await userRef.set({
          'last_sign_in_provider': _pendingSignInProvider,
          'preferred_login_provider': _pendingSignInProvider,
        }, SetOptions(merge: true));
      }
      _isRegisteredUser = true;
      _pendingDisplayName = null;
      notifyListeners();
      await _syncLinkedAuthState(user: user, lastSignInProvider: _pendingSignInProvider);
      _pendingSignInProvider = null;
      return true;
    } catch (e) { return false; }
  }

  Future<void> _syncLinkedAuthState({User? user, String? lastSignInProvider}) async {
    final u = user ?? currentUser;
    if (u == null) return;
    final ids = _providerIds(u);
    
    final updates = <String, dynamic>{
      'linked_google': ids.contains(_providerGoogle),
      'linked_apple': ids.contains(_providerApple),
      'linked_phone': ids.contains(_providerPhone),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (lastSignInProvider != null) {
      updates['last_sign_in_provider'] = lastSignInProvider;
    }

    for (final profile in u.providerData) {
      if (profile.providerId == _providerGoogle) {
        if (profile.email != null) {
          updates['google_email'] = profile.email;
          updates['email'] = profile.email;
        }
      } else if (profile.providerId == _providerApple) {
        if (profile.email != null) {
          updates['apple_email'] = profile.email;
          updates['email'] = profile.email;
        }
      }
    }

    await _db.collection('users').doc(u.uid).set(updates, SetOptions(merge: true));
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
      await _db.collection('users').doc(user.uid).set({
        'preferred_login_provider': providerId,
      }, SetOptions(merge: true));
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<void> signOut() async {
    final box = await HiveService.openBox<AuthMeta>('auth_meta');
    final meta = box.get('current');
    if (meta != null) {
      meta.isRegistered = null;
      meta.registeredUid = null;
      await box.put('current', meta);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _googleSignIn?.signOut();
    if (_isFirebaseSupported) await _auth.signOut();
    _isRegisteredUser = null;
    notifyListeners();
  }
}
