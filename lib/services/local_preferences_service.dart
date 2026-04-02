import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalPreferencesService {
  static Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  static String chatDraftKey(String uid, String roomId) =>
      'draft.chat.$uid.$roomId';

  static String scheduledMessageDraftKey(String uid, String roomId) =>
      'draft.scheduled_message.$uid.$roomId';

  static String groupNoticeDraftKey(String uid, String groupId) =>
      'draft.group_notice.$uid.$groupId';

  static String groupNoticeLastReadKey(String uid, String groupId) =>
      'pref.group_notice_last_read.$uid.$groupId';

  static String privateChatUnreadKey(String uid) =>
      'pref.chat_unread.private.$uid';

  static String groupChatUnreadKey(String uid, String groupId) =>
      'pref.chat_unread.group.$uid.$groupId';

  static String boardPostDraftKey(
    String uid,
    String groupId,
    String boardId, {
    String? postId,
  }) =>
      'draft.board_post.$uid.$groupId.$boardId.${postId ?? 'new'}';

  static String boardFormDefaultsKey(String uid, String groupId) =>
      'pref.board_form.$uid.$groupId';

  static String groupListTabKey(String uid) => 'pref.group_list_tab.$uid';

  static String locationShareTypeKey(String uid) =>
      'pref.location_share_type.$uid';

  static String groupLocationSearchKey(String uid) =>
      'pref.group_location_search.$uid';

  static Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    if (value.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, value);
  }

  static Future<int?> getInt(String key) async {
    final prefs = await _prefs;
    return prefs.getInt(key);
  }

  static Future<void> setInt(String key, int value) async {
    final prefs = await _prefs;
    await prefs.setInt(key, value);
  }

  static Future<Map<String, dynamic>?> getJsonMap(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setJsonMap(
    String key,
    Map<String, dynamic> value,
  ) async {
    await setString(key, jsonEncode(value));
  }

  static Future<void> remove(String key) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }
}
