// lib/providers/chat_provider.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── 룸 메타 모델 ──────────────────────────────────────────────────────────────
class RoomMeta {
  final String roomId;
  final String? refGroupId;
  final String? roomType;
  final String myRole;
  final String roomName;
  final String groupName;
  final Map<String, dynamic>? pinnedMessage;
  final String otherUserUid;
  final String otherUserName;
  final String otherUserPhoto;

  const RoomMeta({
    required this.roomId,
    this.refGroupId,
    this.roomType,
    this.myRole = 'member',
    this.roomName = '',
    this.groupName = '',
    this.pinnedMessage,
    this.otherUserUid = '',
    this.otherUserName = '',
    this.otherUserPhoto = '',
  });
}

// ── LRU 캐시 ─────────────────────────────────────────────────────────────────
class _LruCache<K, V> {
  final int maxSize;
  final _map = <K, V>{};
  final _order = <K>[];

  _LruCache({this.maxSize = 50});

  V? get(K key) {
    if (!_map.containsKey(key)) return null;
    _order.remove(key);
    _order.add(key);
    return _map[key];
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _order.remove(key);
    } else if (_map.length >= maxSize) {
      final oldest = _order.removeAt(0);
      _map.remove(oldest);
    }
    _map[key] = value;
    _order.add(key);
  }

  bool containsKey(K key) => _map.containsKey(key);

  void remove(K key) {
    _map.remove(key);
    _order.remove(key);
  }

  void clear() {
    _map.clear();
    _order.clear();
  }
}

// ── ChatProvider ──────────────────────────────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 룸 메타 LRU 캐시 (최대 50개 방)
  final _metaCache = _LruCache<String, RoomMeta>(maxSize: 50);

  // 유저 프로필 LRU 캐시 (최대 200명)
  final _userCache = _LruCache<String, Map<String, dynamic>>(maxSize: 200);

  // 현재 로딩 중인 방 ID (중복 요청 방지)
  final _loadingMeta = <String>{};

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── 룸 메타 가져오기 ────────────────────────────────────────────────────────
  RoomMeta? getCachedMeta(String roomId) => _metaCache.get(roomId);

  Future<RoomMeta> loadRoomMeta(String roomId) async {
    // 캐시 히트
    final cached = _metaCache.get(roomId);
    if (cached != null) {
      // 백그라운드에서 최신 데이터 갱신
      _fetchAndCacheMeta(roomId);
      return cached;
    }
    // 캐시 미스: 직접 로드
    return await _fetchAndCacheMeta(roomId);
  }

  Future<RoomMeta> _fetchAndCacheMeta(String roomId) async {
    // 중복 요청 방지
    if (_loadingMeta.contains(roomId)) {
      // 이미 로딩 중이면 잠깐 대기 후 캐시 반환
      await Future.delayed(const Duration(milliseconds: 300));
      return _metaCache.get(roomId) ?? RoomMeta(roomId: roomId);
    }

    _loadingMeta.add(roomId);

    try {
      final results = await Future.wait([
        _db.collection('chat_rooms').doc(roomId).get(),
        _db.collection('chat_rooms').doc(roomId)
            .collection('room_members').doc(_currentUserId).get(),
      ]);

      final roomDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final memberDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      final roomType = roomDoc.data()?['type'] as String?;
      final memberIds =
          List<String>.from(roomDoc.data()?['member_ids'] as List? ?? []);

      String otherUserUid = '';
      String otherUserName = '';
      String otherUserPhoto = '';

      if (roomType == 'direct') {
        otherUserUid = memberIds.firstWhere(
          (id) => id != _currentUserId,
          orElse: () => '',
        );
        if (otherUserUid.isNotEmpty) {
          final profile = await getUserProfile(otherUserUid);
          otherUserName = profile['name'] as String? ?? '';
          otherUserPhoto = profile['photo'] as String? ?? '';
        }
      }

      final meta = RoomMeta(
        roomId: roomId,
        refGroupId: roomDoc.data()?['ref_group_id'] as String?,
        roomType: roomType,
        myRole: memberDoc.data()?['role'] as String? ?? 'member',
        roomName: roomDoc.data()?['name'] as String? ?? '',
        groupName: roomDoc.data()?['group_name'] as String? ?? '',
        pinnedMessage:
            roomDoc.data()?['pinned_message'] as Map<String, dynamic>?,
        otherUserUid: otherUserUid,
        otherUserName: otherUserName,
        otherUserPhoto: otherUserPhoto,
      );

      _metaCache.put(roomId, meta);
      notifyListeners();
      return meta;
    } catch (e) {
      debugPrint('ChatProvider: loadRoomMeta error: $e');
      return _metaCache.get(roomId) ?? RoomMeta(roomId: roomId);
    } finally {
      _loadingMeta.remove(roomId);
    }
  }

  // ── 룸 메타 캐시 업데이트 (핀 메시지 변경 등) ──────────────────────────────
  void updatePinnedMessage(String roomId, Map<String, dynamic>? pinData) {
    final cached = _metaCache.get(roomId);
    if (cached == null) return;
    _metaCache.put(
      roomId,
      RoomMeta(
        roomId: roomId,
        refGroupId: cached.refGroupId,
        roomType: cached.roomType,
        myRole: cached.myRole,
        roomName: cached.roomName,
        groupName: cached.groupName,
        pinnedMessage: pinData,
        otherUserUid: cached.otherUserUid,
        otherUserName: cached.otherUserName,
        otherUserPhoto: cached.otherUserPhoto,
      ),
    );
    notifyListeners();
  }

  // ── 유저 프로필 캐시 ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    final cached = _userCache.get(uid);
    if (cached != null) return cached;

    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = {
        'name': doc.data()?['name'] as String? ?? '',
        'photo': doc.data()?['profile_image'] as String? ?? '',
      };
      _userCache.put(uid, data);
      return data;
    } catch (e) {
      return {'name': '', 'photo': ''};
    }
  }

  Map<String, dynamic>? getCachedUserProfile(String uid) =>
      _userCache.get(uid);

  void invalidateUserProfile(String uid) => _userCache.remove(uid);

  // ── 캐시 무효화 ─────────────────────────────────────────────────────────────
  void invalidateRoom(String roomId) {
    _metaCache.remove(roomId);
    notifyListeners();
  }

  void clearAll() {
    _metaCache.clear();
    _userCache.clear();
    notifyListeners();
  }
}