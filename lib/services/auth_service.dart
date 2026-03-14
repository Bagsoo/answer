import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String? _verificationId;

  // Track if user exists in Firestore
  bool? _isRegisteredUser;
  bool? get isRegisteredUser => _isRegisteredUser;

  AuthService() {
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        await _checkAndSetRegisteredUser(user.uid);
      } else {
        _isRegisteredUser = null;
      }
      notifyListeners();
    });
  }

  Future<void> _checkAndSetRegisteredUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        _isRegisteredUser = true;
        // Update last_login
        await _db.collection('users').doc(uid).update({
          'last_login': FieldValue.serverTimestamp(),
        });
      } else {
        _isRegisteredUser = false;
      }
    } catch (e) {
      debugPrint('Error checking user doc: \$e');
      _isRegisteredUser = false;
    }
  }

  // 1. Send SMS
  Future<void> verifyPhoneNumber(
      String phoneNumber,
      Function(String error) onError,
      Function() onCodeSent) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution on Android
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

  // 2. Verify OTP and Sign In
  Future<bool> verifyOTP(String smsCode) async {
    if (_verificationId == null) return false;

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user != null;
    } catch (e) {
      debugPrint('Error verifying OTP: \$e');
      return false;
    }
  }

  // 3. Register New User to Firestore
  Future<bool> registerUser({
    required String name,
    required String locale,
    required String timezone,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    try {
      await _db.collection('users').doc(user.uid).set({
        'phone_number': user.phoneNumber,
        'name': name,
        'locale': locale,
        'timezone': timezone,
        'total_unread': 0,
        'created_at': FieldValue.serverTimestamp(),
        'last_login': FieldValue.serverTimestamp(),
        'profile_image': null,
        'fcm_token': "",
      });
      _isRegisteredUser = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error registering user: \$e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _isRegisteredUser = null;
    notifyListeners();
  }
}
