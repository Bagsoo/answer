import 'hive_service.dart';
import '../models/group_cache.dart';

class GroupCacheService {
  static const String _joinedGroupsBoxName = 'joined_groups';
  static const String _groupNamesBoxName = 'group_names';

  static Future<void> saveJoinedGroups(List<GroupCache> groups) async {
    final box = await HiveService.openBox<GroupCache>(_joinedGroupsBoxName);
    await box.clear();
    await box.addAll(groups);
  }

  static Future<List<GroupCache>> getJoinedGroups() async {
    final box = await HiveService.openBox<GroupCache>(_joinedGroupsBoxName);
    return box.values.toList();
  }

  static Future<void> saveGroupName(String groupId, String name) async {
    final box = await HiveService.openBox<String>(_groupNamesBoxName);
    await box.put(groupId, name);
  }

  static Future<String?> getGroupName(String groupId) async {
    final box = await HiveService.openBox<String>(_groupNamesBoxName);
    return box.get(groupId);
  }

  static Future<void> saveGroupNames(Map<String, String> names) async {
    final box = await HiveService.openBox<String>(_groupNamesBoxName);
    await box.putAll(names);
  }

  static Future<Map<String, String>> getAllGroupNames() async {
    final box = await HiveService.openBox<String>(_groupNamesBoxName);
    return Map<String, String>.from(box.toMap());
  }

  static Future<void> clearAll() async {
    final joinedBox = await HiveService.openBox<GroupCache>(_joinedGroupsBoxName);
    await joinedBox.clear();
    final namesBox = await HiveService.openBox<String>(_groupNamesBoxName);
    await namesBox.clear();
  }
}
