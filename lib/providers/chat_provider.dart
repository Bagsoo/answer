import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/user_cache.dart';

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
  void remove(K key) { _map.remove(key); _order.remove(key); }
  void clear() { _map.clear(); _order.clear(); }
  Iterable<K> get keys => _map.keys;
}

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

  RoomMeta copyWith({Map<String, dynamic>? pinnedMessage}) => RoomMeta(
        roomId: roomId,
        refGroupId: refGroupId,
        roomType: roomType,
        myRole: myRole,
        roomName: roomName,
        groupName: groupName,
        pinnedMessage: pinnedMessage ?? this.pinnedMessage,
        otherUserUid: otherUserUid,
        otherUserName: otherUserName,
        otherUserPhoto: otherUserPhoto,
      );
}

// ── 방별 메시지 상태 ───────────────────────────────────────────────────────────
class RoomMessageState {
  final Stream<QuerySnapshot> messageStream;
  final Stream<QuerySnapshot> memberStream;
  final List<QueryDocumentSnapshot> cachedMessages;
  final bool isLoaded;

  const RoomMessageState({
    required this.messageStream,
    required this.memberStream,
    this.cachedMessages = const [],
    this.isLoaded = false,
  });

  RoomMessageState copyWith({
    List<QueryDocumentSnapshot>? cachedMessages,
    bool? isLoaded,
  }) =>
      RoomMessageState(
        messageStream: messageStream,
        memberStream: memberStream,
        cachedMessages: cachedMessages ?? this.cachedMessages,
        isLoaded: isLoaded ?? this.isLoaded,
      );
}

// ── ChatProvider ──────────────────────────────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 룸 메타 LRU 캐시 (최대 100개)
  final _metaCache = _LruCache<String, RoomMeta>(maxSize: 100);

  // 방별 스트림 캐시 - 한 번 연결하면 유지 (최대 20개 방)
  // 메시지 로딩 상태 (hasMore) 기록 캐시
  final _roomStates = _LruCache<String, RoomMessageState>(maxSize: 20);

  // 전역 채팅방 리스트 스트림 구독
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _roomsSubscription;
  List<Map<String, dynamic>> _chatRooms = [];
  bool _isRoomsLoaded = false;

  // 현재 로딩 중인 방 메타 (중복 요청 방지)
  final _loadingMeta = <String>{};

  // PC 모드에서 방문한 방 순서 (IndexedStack용)
  final List<String> _visitedRooms = [];
  String? _activeRoomId;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  List<String> get visitedRooms => List.unmodifiable(_visitedRooms);
  String? get activeRoomId => _activeRoomId;
  List<Map<String, dynamic>> get chatRooms => _chatRooms;
  bool get isRoomsLoaded => _isRoomsLoaded;

  // ── 초기화 및 전역 스트림 캐싱 ──────────────────────────────────────────────
  void initialize() {
    _subscribeToRooms();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _subscribeToRooms();
      } else {
        clearAll();
      }
    });
  }

  void _subscribeToRooms() {
    if (_currentUserId.isEmpty) return;
    _roomsSubscription?.cancel();

    _roomsSubscription = _db
        .collection('chat_rooms')
        .where('member_ids', arrayContains: _currentUserId)
        .snapshots()
        .listen((snapshot) {
      
      final Set<String> allMemberUids = {};

      final rooms = snapshot.docs.map((doc) {
        final data = {...doc.data(), 'id': doc.id};
        final unreadCounts =
            data['unread_counts'] as Map<String, dynamic>? ?? {};
        data['unread_cnt'] = unreadCounts[_currentUserId] as int? ?? 0;
        
        final memberIds = List<String>.from(data['member_ids'] as List? ?? []);
        allMemberUids.addAll(memberIds);

        return data;
      }).toList();

      // 화면에 그리기 전 필요한 유저 프로필 일괄 prefetch
      UserCache.prefetch(allMemberUids);

      rooms.sort((a, b) {
        final aTime = a['last_time'] as Timestamp?;
        final bTime = b['last_time'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      _chatRooms = rooms;
      _isRoomsLoaded = true;
      notifyListeners();
    }, onError: (e) {
      debugPrint('ChatProvider _subscribeToRooms error: $e');
    });
  }

  // ── 방 선택 (PC 모드) ────────────────────────────────────────────────────────
  void selectRoom(String roomId) {
    if (_activeRoomId == roomId) return;
    _activeRoomId = roomId;

    if (!_visitedRooms.contains(roomId)) {
      _visitedRooms.add(roomId);
    }

    // 스트림 미리 연결
    ensureRoomStream(roomId);

    // 메타 미리 로드
    if (!_metaCache.containsKey(roomId)) {
      loadRoomMeta(roomId);
    }

    notifyListeners();
  }

  // ── 방 스트림 보장 (없으면 생성, 있으면 재사용) ──────────────────────────────
  RoomMessageState ensureRoomStream(String roomId) {
    final existing = _roomStates.get(roomId);
    if (existing != null) return existing;

    // 새 스트림 생성 (broadcast로 여러 곳에서 listen 가능)
    final messageStream = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots()
        .asBroadcastStream();

    final memberStream = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('room_members')
        .snapshots()
        .asBroadcastStream();

    final state = RoomMessageState(
      messageStream: messageStream,
      memberStream: memberStream,
    );

    _roomStates.put(roomId, state);
    return state;
  }

  Stream<QuerySnapshot> getMessageStream(String roomId) =>
      ensureRoomStream(roomId).messageStream;

  Stream<QuerySnapshot> getMemberStream(String roomId) =>
      ensureRoomStream(roomId).memberStream;

  // ── 룸 메타 ─────────────────────────────────────────────────────────────────
  RoomMeta? getCachedMeta(String roomId) => _metaCache.get(roomId);

  Future<RoomMeta> loadRoomMeta(String roomId) async {
    final cached = _metaCache.get(roomId);
    if (cached != null) {
      // 백그라운드 갱신
      _fetchAndCacheMeta(roomId);
      return cached;
    }
    return await _fetchAndCacheMeta(roomId);
  }

  Future<RoomMeta> _fetchAndCacheMeta(String roomId) async {
    if (_loadingMeta.contains(roomId)) {
      // 이미 로딩 중이면 완료될 때까지 대기
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        return _loadingMeta.contains(roomId);
      });
      return _metaCache.get(roomId) ?? RoomMeta(roomId: roomId);
    }

    _loadingMeta.add(roomId);
    try {
      final results = await Future.wait([
        _db.collection('chat_rooms').doc(roomId).get(),
        _db
            .collection('chat_rooms')
            .doc(roomId)
            .collection('room_members')
            .doc(_currentUserId)
            .get(),
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
      debugPrint('ChatProvider._fetchAndCacheMeta error: $e');
      return _metaCache.get(roomId) ?? RoomMeta(roomId: roomId);
    } finally {
      _loadingMeta.remove(roomId);
    }
  }

  void updatePinnedMessage(String roomId, Map<String, dynamic>? pinData) {
    final cached = _metaCache.get(roomId);
    if (cached == null) return;
    _metaCache.put(roomId, cached.copyWith(pinnedMessage: pinData));
    notifyListeners();
  }

  void invalidateRoom(String roomId) {
    _metaCache.remove(roomId);
    _roomStates.remove(roomId);
    _visitedRooms.remove(roomId);
    if (_activeRoomId == roomId) _activeRoomId = null;
    notifyListeners();
  }

  // ── 유저 프로필 ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getUserProfile(String uid) async {
    return UserCache.get(uid);
  }

  Map<String, dynamic>? getCachedUserProfile(String uid) =>
      UserCache.getCached(uid);

  // ── PC 모드 인접 방 미리 로드 (선택한 방 주변 방들 preload) ──────────────────
  void preloadAdjacentRooms(List<String> roomIds, String currentRoomId) {
    final index = roomIds.indexOf(currentRoomId);
    if (index == -1) return;

    // 앞뒤 2개 방씩 미리 로드
    final toPreload = <String>[];
    for (int i = index - 2; i <= index + 2; i++) {
      if (i >= 0 && i < roomIds.length && roomIds[i] != currentRoomId) {
        toPreload.add(roomIds[i]);
      }
    }

    for (final roomId in toPreload) {
      if (!_metaCache.containsKey(roomId)) {
        loadRoomMeta(roomId); // 백그라운드 로드
      }
      if (!_roomStates.containsKey(roomId)) {
        ensureRoomStream(roomId); // 스트림 미리 연결
      }
    }
  }

  void clearAll() {
    _roomsSubscription?.cancel();
    _metaCache.clear();
    _roomStates.clear();
    _visitedRooms.clear();
    _activeRoomId = null;
    _chatRooms = [];
    _isRoomsLoaded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _roomsSubscription?.cancel();
    super.dispose();
  }
}