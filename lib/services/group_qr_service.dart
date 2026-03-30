import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class GroupQrService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  String? extractToken(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    final tokenFromQuery = parsed?.queryParameters['token'];
    if (tokenFromQuery != null && tokenFromQuery.isNotEmpty) {
      return tokenFromQuery;
    }
    return trimmed;
  }

  String buildQrData(String token) => 'answer://group-join?token=$token';

  Future<Map<String, dynamic>> regenerate(String groupId) async {
    final callable = _functions.httpsCallable('regenerateGroupQr');
    final result = await callable.call({'groupId': groupId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> setEnabled(
    String groupId,
    bool enabled,
  ) async {
    final callable = _functions.httpsCallable('setGroupQrEnabled');
    final result = await callable.call({'groupId': groupId, 'enabled': enabled});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> joinByQr(String token) async {
    final callable = _functions.httpsCallable('joinGroupByQr');
    final result = await callable.call({'token': token});
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> fetchPreview(String rawValue) async {
    final token = extractToken(rawValue);
    if (token == null) return {'status': 'invalid'};

    final snap = await _db
        .collection('groups')
        .where('invite_token', isEqualTo: token)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return {'status': 'invalid'};

    final doc = snap.docs.first;
    final data = doc.data();
    final plan = data['plan'] as String? ?? 'free';
    final qrEnabled = data['qr_enabled'] as bool? ?? false;
    if ((plan != 'plus' && plan != 'pro') || !qrEnabled) {
      return {'status': 'disabled'};
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    bool isMember = false;
    if (currentUid.isNotEmpty) {
      final memberDoc = await _db
          .collection('groups')
          .doc(doc.id)
          .collection('members')
          .doc(currentUid)
          .get();
      isMember = memberDoc.exists;
    }

    return {
      'status': 'ok',
      'token': token,
      'group': {
        'id': doc.id,
        'name': data['name'] as String? ?? '',
        'profile_image': data['group_profile_image'] as String? ?? '',
        'member_count': data['member_count'] as int? ?? 0,
        'member_limit': data['member_limit'] as int? ?? 0,
        'require_approval': data['require_approval'] as bool? ?? false,
        'plan': plan,
        'is_member': isMember,
      },
    };
  }
}
