import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/group_cache.dart';
import '../models/user_profile_cache.dart';
import '../models/auth_meta.dart';
import '../models/notification_settings_cache.dart';

class HiveService {
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // 어댑터 등록
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(UserProfileCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(GroupCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(AuthMetaAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(NotificationSettingsCacheAdapter());
    }

    // 기본 박스 열기
    await Hive.openBox<UserProfileCache>('user_profile');
    await Hive.openBox<AuthMeta>('auth_meta');
    await Hive.openBox<NotificationSettingsCache>('notification_settings');

    // 구형 SharedPreferences 데이터 정리 (마이그레이션 불필요시)
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('joined_groups_cache')) {
      await prefs.remove('joined_groups_cache');
    }
    if (prefs.containsKey('group_names_cache')) {
      await prefs.remove('group_names_cache');
    }
  }

  static Future<Box<T>> openBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }
    return await Hive.openBox<T>(name);
  }

  static Future<void> closeAll() async {
    await Hive.close();
  }
}
