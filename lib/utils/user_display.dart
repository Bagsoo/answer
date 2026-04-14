import 'package:characters/characters.dart';

import '../l10n/app_localizations.dart';
import 'user_cache.dart';

class UserDisplayData {
  final String uid;
  final String name;
  final String photoUrl;
  final bool isDeleted;

  const UserDisplayData({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.isDeleted,
  });

  String displayName(AppLocalizations l, {String fallback = ''}) {
    if (isDeleted) return l.deletedUser;
    if (name.isNotEmpty) return name;
    return fallback;
  }

  String initial(AppLocalizations l, {String fallback = '?'}) {
    final resolved = displayName(l, fallback: fallback).trim();
    if (resolved.isEmpty) return fallback;
    return resolved.characters.first.toUpperCase();
  }
}

class UserDisplay {
  static const UserDisplayData empty = UserDisplayData(
    uid: '',
    name: '',
    photoUrl: '',
    isDeleted: false,
  );

  static UserDisplayData fromStored({
    required String uid,
    String? name,
    String? photoUrl,
    bool isDeleted = false,
  }) {
    return UserDisplayData(
      uid: uid,
      name: isDeleted ? '' : (name ?? ''),
      photoUrl: isDeleted ? '' : (photoUrl ?? ''),
      isDeleted: isDeleted,
    );
  }

  static Future<UserDisplayData> resolve(
    String uid, {
    String? fallbackName,
    String? fallbackPhotoUrl,
  }) async {
    if (uid.isEmpty) {
      return fromStored(
        uid: uid,
        name: fallbackName,
        photoUrl: fallbackPhotoUrl,
      );
    }

    final cached = UserCache.getCached(uid);
    if (cached != null) {
      return _merge(uid, cached, fallbackName, fallbackPhotoUrl);
    }

    final fetched = await UserCache.get(uid);
    return _merge(uid, fetched, fallbackName, fallbackPhotoUrl);
  }

  static UserDisplayData? resolveCached(
    String uid, {
    String? fallbackName,
    String? fallbackPhotoUrl,
  }) {
    if (uid.isEmpty) {
      return fromStored(
        uid: uid,
        name: fallbackName,
        photoUrl: fallbackPhotoUrl,
      );
    }

    final cached = UserCache.getCached(uid);
    if (cached == null) return null;
    return _merge(uid, cached, fallbackName, fallbackPhotoUrl);
  }

  static UserDisplayData _merge(
    String uid,
    Map<String, dynamic> raw,
    String? fallbackName,
    String? fallbackPhotoUrl,
  ) {
    final isDeleted = raw['is_deleted'] == true;
    return fromStored(
      uid: uid,
      name: (raw['name'] as String? ?? '').isNotEmpty
          ? raw['name'] as String?
          : fallbackName,
      photoUrl: (raw['photo'] as String? ?? '').isNotEmpty
          ? raw['photo'] as String?
          : fallbackPhotoUrl,
      isDeleted: isDeleted,
    );
  }
}
