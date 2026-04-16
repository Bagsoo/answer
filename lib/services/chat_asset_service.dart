import 'package:cloud_firestore/cloud_firestore.dart';

class ChatAssetRecord {
  final String id;
  final String messageId;
  final String type;
  final Timestamp? createdAt;
  final bool isStarred;
  final String primaryUrl;
  final String thumbUrl;
  final String fileName;
  final String linkUrl;
  final String pollId;

  const ChatAssetRecord({
    required this.id,
    required this.messageId,
    required this.type,
    required this.createdAt,
    this.isStarred = false,
    this.primaryUrl = '',
    this.thumbUrl = '',
    this.fileName = '',
    this.linkUrl = '',
    this.pollId = '',
  });

  factory ChatAssetRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ChatAssetRecord(
      id: doc.id,
      messageId: data['message_id'] as String? ?? '',
      type: data['type'] as String? ?? '',
      createdAt: data['created_at'] as Timestamp?,
      isStarred: data['is_starred'] as bool? ?? false,
      primaryUrl: data['primary_url'] as String? ?? '',
      thumbUrl: data['thumb_url'] as String? ?? '',
      fileName: data['file_name'] as String? ?? '',
      linkUrl: data['link_url'] as String? ?? '',
      pollId: data['poll_id'] as String? ?? '',
    );
  }
}

class ChatAssetPage {
  final List<ChatAssetRecord> items;
  final QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const ChatAssetPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class _ChatAssetCacheEntry {
  final ChatAssetPage page;
  final DateTime cachedAt;

  const _ChatAssetCacheEntry({
    required this.page,
    required this.cachedAt,
  });
}

class ChatAssetService {
  static final ChatAssetService _instance = ChatAssetService._internal();
  factory ChatAssetService() => _instance;
  ChatAssetService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, _ChatAssetCacheEntry> _firstPageCache = {};

  String _cacheKey(String roomId, String type) => '$roomId::$type';

  Query<Map<String, dynamic>> _baseQuery(String roomId, String type) {
    Query<Map<String, dynamic>> query = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('message_assets');

    if (type == 'starred') {
      query = query.where('is_starred', isEqualTo: true);
    } else if (type == 'media' || type == 'file') {
      query = query.where('bucket', isEqualTo: type);
    } else if (type != 'recent') {
      query = query.where('type', isEqualTo: type);
    }

    query = query.orderBy('created_at', descending: true);

    return query;
  }

  Future<ChatAssetPage> fetchAssets({
    required String roomId,
    required String type,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 30,
    bool useCache = true,
  }) async {
    final cacheKey = _cacheKey(roomId, type);
    if (useCache && startAfter == null) {
      final cached = _firstPageCache[cacheKey];
      if (cached != null) return cached.page;
    }

    var query = _baseQuery(roomId, type).limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final page = ChatAssetPage(
      items: snap.docs.map(ChatAssetRecord.fromDoc).toList(growable: false),
      cursor: snap.docs.isEmpty ? null : snap.docs.last,
      hasMore: snap.docs.length >= limit,
    );

    if (startAfter == null) {
      _firstPageCache[cacheKey] = _ChatAssetCacheEntry(
        page: page,
        cachedAt: DateTime.now(),
      );
    }

    return page;
  }

  void invalidateRoom(String roomId) {
    final keys = _firstPageCache.keys
        .where((key) => key.startsWith('$roomId::'))
        .toList(growable: false);
    for (final key in keys) {
      _firstPageCache.remove(key);
    }
  }

  void clearCache() {
    _firstPageCache.clear();
  }

  Future<void> setStarred({
    required String roomId,
    required String assetId,
    required bool isStarred,
  }) async {
    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('message_assets')
        .doc(assetId)
        .update({'is_starred': isStarred});
    invalidateRoom(roomId);
  }
}
