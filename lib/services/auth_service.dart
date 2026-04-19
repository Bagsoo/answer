import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart' as desktop;

class AuthService extends ChangeNotifier {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  
  /// Windows에서는 `package:google_sign_in` 플러그인이 등록되지 않아
  /// `GoogleSignIn()` 생성만으로도 네이티브가 불안정해질 수 있다. 데스크톱 OAuth는 [_lazyDesktopSignIn]만 쓴다.
  GoogleSignIn? _googleSignIn;
  desktop.GoogleSignIn? _desktopSignIn;

  bool get _useDesktopGoogle =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Windows용 OAuth 클라이언트는 로그인/연동 시에만 생성한다.
  /// 기동 직후 Firestore 등과 동시에 초기화되면 일부 환경에서 프로세스가 종료되는 증상이 있었다.
  desktop.GoogleSignIn _lazyDesktopSignIn() {
    _desktopSignIn ??= desktop.GoogleSignIn(
      params: desktop.GoogleSignInParams(
        clientId: dotenv.env['GOOGLE_CLIENT_ID'] ?? '',
        clientSecret: dotenv.env['GOOGLE_CLIENT_SECRET'],
        scopes: ['email', 'profile', 'openid'],
        redirectPort: 8080,
      ),
    );
    return _desktopSignIn!;
  }

  static const _keyIsRegistered = 'auth_is_registered';
  static const _keyRegisteredUid = 'auth_registered_uid';

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _verificationId;
  bool? _isRegisteredUser;
  bool? get isRegisteredUser => _isRegisteredUser;
  String? _pendingDisplayName;
  String? get pendingDisplayName => _pendingDisplayName;

  static const _providerGoogle = 'google.com';
  static const _providerApple = 'apple.com';
  static const _providerPhone = 'phone';

  AuthService() {
    final clientId = dotenv.env['GOOGLE_CLIENT_ID'];
    debugPrint('AuthService GOOGLE_CLIENT_ID from dotenv: $clientId');

    if (kIsWeb) {
      _googleSignIn = GoogleSignIn(clientId: clientId);
    } else if (defaultTargetPlatform != TargetPlatform.windows) {
      _googleSignIn = GoogleSignIn(
        clientId: null,
      );
    }

    // ✅ 모바일/Windows 공통 authStateChanges 리스너
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

  Future<void> _checkAndSetRegisteredUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      debugPrint('doc.exists: ${doc.exists}');
      debugPrint('account_status: ${data?['account_status']}');
      final registered = doc.exists &&
          (data?['account_status'] as String? ?? 'active') == 'active';
      debugPrint('_isRegisteredUser will be: $registered');
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
    } catch (e) {
      debugPrint('Error checking user doc: $e');
      if (_isRegisteredUser == null) {
        _isRegisteredUser = false;
        notifyListeners();
      }
    }
  }

  Future<void> _syncLinkedAuthStateForDesktop() async {
    final u = _auth.currentUser;
    if (u == null) return;
    final userRef = _db.collection('users').doc(u.uid);
    await userRef.set({
      'last_login': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── 전화번호 인증 ────────────────────────────────────────────────────────────
  Future<void> verifyPhoneNumber(
      String phoneNumber,
      Function(String error) onError,
      Function() onCodeSent, {
      VoidCallback? onAutoLinked,
    }) async {
    final isDesktopUnsupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);

    if (isDesktopUnsupported) {
      onError(
        '현재 Firebase 전화번호 인증은 데스크톱 앱(Windows/macOS/Linux)에서 지원되지 않습니다. '
        '모바일 앱 또는 웹(Chrome)에서 Google/Apple 계정을 먼저 연결한 후 해당 계정으로 로그인해 주세요.',
      );
      return;
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final current = _auth.currentUser;
            if (current != null) {
              if (!_providerIds(current).contains(_providerPhone)) {
                await current.linkWithCredential(credential);
              }
            } else {
              await _auth.signInWithCredential(credential);
            }
            await _syncLinkedAuthState(
              user: _auth.currentUser,
              lastSignInProvider: _providerPhone,
            );
            onAutoLinked?.call();
          } catch (e) {
            onError(e.toString());
          }
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
    } on TypeError {
      onError(
        '전화번호 인증 처리 중 플랫폼 호환 오류가 발생했습니다. '
        '모바일 앱 또는 웹(Chrome)에서 진행해 주세요.',
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Set<String> _providerIds(User user) {
    return user.providerData
        .map((p) => p.providerId)
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  String _detectPreferredProvider(Set<String> ids) {
    if (ids.contains(_providerGoogle)) return _providerGoogle;
    if (ids.contains(_providerApple)) return _providerApple;
    if (ids.contains(_providerPhone)) return _providerPhone;
    return 'unknown';
  }

  String _normalizePhoneE164(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (trimmed.startsWith('+')) return '+$digits';
    return '+$digits';
  }

  String? _normalizedAccessToken(String? token) {
    if (token == null) return null;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _debugLogGoogleIdToken(String idToken) {
    final claims = _decodeJwtPayload(idToken);
    if (claims == null) {
      debugPrint('Google ID Token decode failed.');
      return;
    }
    final aud = claims['aud'];
    final azp = claims['azp'];
    final iss = claims['iss'];
    final exp = claims['exp'];
    final iat = claims['iat'];
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    debugPrint(
      'Google ID Token claims => aud: $aud, azp: $azp, iss: $iss, iat: $iat, exp: $exp, now: $nowSec',
    );
  }

  Future<void> _claimPhoneIndex({
    required String phoneE164,
    required String uid,
  }) async {
    if (phoneE164.isEmpty) return;
    final indexRef = _db.collection('phone_index').doc(phoneE164);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(indexRef);
      final data = snap.data();
      final existingUid = data?['uid'] as String?;

      if (existingUid != null && existingUid.isNotEmpty && existingUid != uid) {
        throw FirebaseAuthException(
          code: 'phone-number-already-linked',
          message: 'This phone number is already linked to another account.',
        );
      }

      tx.set(indexRef, {
        'uid': uid,
        'is_deleted': false,
        'updated_at': FieldValue.serverTimestamp(),
        'claimed_at': data?['claimed_at'] ?? FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _markPhoneIndexDeleted({
    required String phoneE164,
    required String uid,
  }) async {
    if (phoneE164.isEmpty) return;
    final indexRef = _db.collection('phone_index').doc(phoneE164);
    await indexRef.set({
      'uid': uid,
      'is_deleted': true,
      'deleted_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncLinkedAuthState({
    User? user,
    String? lastSignInProvider,
  }) async {
    final u = user ?? _auth.currentUser;
    if (u == null) return;

    final userRef = _db.collection('users').doc(u.uid);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      debugPrint("Windows: Performing minimal sync...");
      await userRef.set({
        'last_login': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    
    final doc = await userRef.get();
    if (!doc.exists) return;

    final ids = _providerIds(u);
    final googleData = u.providerData.where((p) => p.providerId == _providerGoogle).firstOrNull;
    final appleData = u.providerData.where((p) => p.providerId == _providerApple).firstOrNull;
    final phoneData = u.providerData.where((p) => p.providerId == _providerPhone).firstOrNull;
    
    final phoneE164 = _normalizePhoneE164(u.phoneNumber ?? phoneData?.phoneNumber ?? '');

    if (phoneE164.isNotEmpty) {
      await _claimPhoneIndex(phoneE164: phoneE164, uid: u.uid);
    }

    final preferred = _detectPreferredProvider(ids);

    await userRef.set({
      'linked_google': ids.contains(_providerGoogle),
      'linked_apple': ids.contains(_providerApple),
      'linked_phone': ids.contains(_providerPhone),
      'google_email': googleData?.email ?? '',
      'apple_email': appleData?.email ?? '',
      'email': u.email ?? '',
      'phone_number': phoneE164,
      'last_sign_in_provider':
          lastSignInProvider ?? doc.data()?['last_sign_in_provider'] ?? preferred,
      'preferred_login_provider':
          doc.data()?['preferred_login_provider'] ?? preferred,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> verifyOTP(String smsCode) async {
    if (_verificationId == null) return '인증 세션이 만료되었습니다. 다시 시도해주세요.';
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final current = _auth.currentUser;
      User? user;

      if (current != null) {
        if (_providerIds(current).contains(_providerPhone)) {
          _verificationId = null;
          return null;
        }
        final userCredential = await current.linkWithCredential(credential);
        user = userCredential.user;
      } else {
        final userCredential = await _auth.signInWithCredential(credential);
        user = userCredential.user;
      }

      if (user == null) return '인증에 실패했습니다.';

      final phoneE164 = _normalizePhoneE164(user.phoneNumber ?? '');
      if (phoneE164.isNotEmpty) {
        await _claimPhoneIndex(phoneE164: phoneE164, uid: user.uid);
      }
      await _syncLinkedAuthState(
        user: user,
        lastSignInProvider: _providerPhone,
      );
      _verificationId = null;
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error during OTP verify: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'invalid-verification-code':
          return '인증번호가 잘못되었습니다.';
        case 'credential-already-in-use':
          return '이 전화번호는 이미 다른 계정에 연결되어 있습니다.';
        case 'provider-already-linked':
          return '이미 전화번호가 연결된 계정입니다.';
        default:
          return e.message ?? '인증 실패: ${e.code}';
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      return e.toString();
    }
  }

  // ── Google 로그인 ────────────────────────────────────────────────────────────
  Future<String> signInWithGoogle() async {
    try {
      String? idToken;
      String? accessToken;
      String? displayName;

      if (_useDesktopGoogle) {
        final d = _lazyDesktopSignIn();
        debugPrint('Desktop Google OAuth requested with clientId: ${dotenv.env['GOOGLE_CLIENT_ID']}');
        await d.signOut();
        final res = await d.signInOnline();
        if (res == null) return 'cancel';
        idToken = res.idToken;
        accessToken = res.accessToken;
        displayName = null;
        debugPrint('Desktop Google Sign-in successful. ID Token: ${idToken?.substring(0, 10)}...');
      } else {
        final mobile = _googleSignIn;
        if (mobile == null) {
          debugPrint('signInWithGoogle: GoogleSignIn not available on this platform');
          return 'error';
        }
        final googleUser = await mobile.signIn();
        if (googleUser == null) return 'cancel';
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
        accessToken = googleAuth.accessToken;
        displayName = googleUser.displayName;
      }

      if (idToken == null) {
        debugPrint('Error: idToken is null');
        return 'error';
      }

      _debugLogGoogleIdToken(idToken);
      final normalizedAccessToken = _normalizedAccessToken(accessToken);

      debugPrint('Attempting Firebase sign in with credential...');
      UserCredential userCredential;
      try {
        final credential = GoogleAuthProvider.credential(
          accessToken: normalizedAccessToken,
          idToken: idToken,
        );
        userCredential = await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'invalid-credential' && _useDesktopGoogle) {
          debugPrint('Retrying Firebase sign-in with ID token only (desktop)...');
          final retryCredential = GoogleAuthProvider.credential(idToken: idToken);
          userCredential = await _auth.signInWithCredential(retryCredential);
        } else {
          rethrow;
        }
      }

      if (userCredential.additionalUserInfo?.isNewUser == true) {
        _pendingDisplayName = displayName;
      } else {
        await _syncLinkedAuthState(
          user: userCredential.user,
          lastSignInProvider: _providerGoogle,
        );
      }

      return 'ok';
    } catch (e) {
      debugPrint('Google sign in error: $e');
      if (e is FirebaseAuthException) {
        debugPrint('Firebase Auth Error Code: ${e.code}');
        debugPrint('Firebase Auth Error Message: ${e.message}');
      }
      return 'error';
    }
  }

  // ── 신규 유저 등록 ──────────────────────────────────────────────────────────
  Future<bool> registerUser({
    required String name,
    required String locale,
    required String timezone,
    required bool termsAgreed,
    required bool privacyAgreed,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    final providerIds = _providerIds(user);
    final googleData = user.providerData
        .where((p) => p.providerId == _providerGoogle)
        .firstOrNull;
    final appleData = user.providerData
        .where((p) => p.providerId == _providerApple)
        .firstOrNull;
    final phoneE164 = _normalizePhoneE164(user.phoneNumber ?? '');
    final preferred = _detectPreferredProvider(providerIds);
    final now = FieldValue.serverTimestamp();
    try {
      final userRef = _db.collection('users').doc(user.uid);
      final existingDoc = await userRef.get();
      final existingData = existingDoc.data();
      final wasDeleted =
          (existingData?['account_status'] as String? ?? 'active') == 'deleted';

      if (phoneE164.isNotEmpty) {
        await _claimPhoneIndex(phoneE164: phoneE164, uid: user.uid);
      }

      await userRef.set({
        'phone_number': phoneE164,
        'name': name,
        'locale': locale,
        'timezone': timezone,
        'total_unread': 0,
        'created_at': existingData?['created_at'] ?? now,
        'last_login': now,
        'account_status': 'active',
        'deleted_at': null,
        'deleted_by': null,
        'search_hidden': false,
        'profile_image': user.photoURL ?? '',
        'fcm_token': '',
        'linked_google': providerIds.contains(_providerGoogle),
        'linked_apple': providerIds.contains(_providerApple),
        'linked_phone': providerIds.contains(_providerPhone),
        'last_sign_in_provider': preferred,
        'preferred_login_provider':
            existingData?['preferred_login_provider'] ?? preferred,
        'google_email': googleData?.email ?? '',
        'apple_email': appleData?.email ?? '',
        'email': user.email ?? '',
        'reactivated_at': wasDeleted ? now : null,
        'agreements': {
          'terms': {
            'agreed': termsAgreed,
            'agreed_at': termsAgreed ? now : null,
            'version': '1.0',
          },
          'privacy': {
            'agreed': privacyAgreed,
            'agreed_at': privacyAgreed ? now : null,
            'version': '1.0',
          },
        },
      }, SetOptions(merge: true));

      _isRegisteredUser = true;
      _pendingDisplayName = null;
      notifyListeners();

      await _syncLinkedAuthState(user: user);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsRegistered, true);
      await prefs.setString(_keyRegisteredUid, user.uid);

      return true;
    } catch (e) {
      debugPrint('Error registering user: $e');
      return false;
    }
  }

  Future<bool> canUnlinkProvider(String providerId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final ids = _providerIds(user);
    if (!ids.contains(providerId)) return false;
    return ids.length > 1;
  }

  Future<String?> unlinkProvider(String providerId) async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user.';
    final phoneBeforeUnlink = _normalizePhoneE164(user.phoneNumber ?? '');

    final canUnlink = await canUnlinkProvider(providerId);
    if (!canUnlink) {
      return 'At least one login provider must remain linked.';
    }

    try {
      await user.unlink(providerId);
      if (providerId == _providerPhone && phoneBeforeUnlink.isNotEmpty) {
        await _markPhoneIndexDeleted(
          phoneE164: phoneBeforeUnlink,
          uid: user.uid,
        );
      }
      await _syncLinkedAuthState(user: _auth.currentUser);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> linkGoogleProvider() async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user.';

    if (_providerIds(user).contains(_providerGoogle)) {
      return 'Google provider is already linked.';
    }

    try {
      String? idToken;
      String? accessToken;

      if (_useDesktopGoogle) {
        final d = _lazyDesktopSignIn();
        await d.signOut();
        final res = await d.signInOnline();
        if (res == null) return 'cancel';
        idToken = res.idToken;
        accessToken = res.accessToken;
      } else {
        final mobile = _googleSignIn;
        if (mobile == null) {
          return 'Google sign-in is not available on this platform.';
        }
        final googleUser = await mobile.signIn();
        if (googleUser == null) return 'cancel';
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
        accessToken = googleAuth.accessToken;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: _normalizedAccessToken(accessToken),
        idToken: idToken,
      );

      try {
        await user.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'invalid-credential' && _useDesktopGoogle && idToken != null) {
          final retryCredential = GoogleAuthProvider.credential(idToken: idToken);
          await user.linkWithCredential(retryCredential);
        } else {
          rethrow;
        }
      }
      await _syncLinkedAuthState(user: _auth.currentUser);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> setPreferredLoginProvider(String providerId) async {
    final user = _auth.currentUser;
    if (user == null) return 'No signed-in user.';

    if (!_providerIds(user).contains(providerId)) {
      return 'Provider is not linked to this account.';
    }

    try {
      await _db.collection('users').doc(user.uid).set({
        'preferred_login_provider': providerId,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> markCurrentUserPhoneIndexDeleted() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final phoneE164 = _normalizePhoneE164(user.phoneNumber ?? '');
    await _markPhoneIndexDeleted(phoneE164: phoneE164, uid: user.uid);
  }

  // ── 로그아웃 ────────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsRegistered);
    await prefs.remove(_keyRegisteredUid);

    await _googleSignIn?.signOut();
    await _desktopSignIn?.signOut();
    await _auth.signOut();

    _isRegisteredUser = null;
    _pendingDisplayName = null;
    notifyListeners();
  }
}