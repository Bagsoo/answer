import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile_cache.dart';
import '../services/hive_service.dart';

class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<UserProfileCache?> getCachedProfile(String uid) async {
    final box = await HiveService.openBox<UserProfileCache>('user_profile');
    final cache = box.get(uid);
    if (cache != null && cache.uid == uid) {
      return cache;
    }
    return null;
  }

  Future<UserProfileCache?> fetchAndCacheProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return null;

      final gp = data['activity_location'] as GeoPoint?;
      final cache = UserProfileCache(
        uid: uid,
        name: data['name'] as String? ?? '',
        photoUrl: data['profile_image'] as String?,
        phone: data['phone_number'] as String? ?? '',
        locationName: data['activity_location_name'] as String? ?? '',
        locationLat: gp?.latitude,
        locationLng: gp?.longitude,
        interests: List<String>.from(data['interests'] as List? ?? []),
      );
      await saveProfileLocal(cache);
      return cache;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfileLocal(UserProfileCache cache) async {
    if (cache.uid == null || cache.uid!.isEmpty) return;
    final box = await HiveService.openBox<UserProfileCache>('user_profile');
    await box.put(cache.uid!, cache);
  }

  Future<void> clearProfileCache(String uid) async {
    final box = await HiveService.openBox<UserProfileCache>('user_profile');
    await box.delete(uid);
  }
}
