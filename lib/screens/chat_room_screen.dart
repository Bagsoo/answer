import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../services/memo_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/block_service.dart';
import '../services/report_service.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'chat_room_more/chat_room_participants_screen.dart';
import 'chat_room_more/chat_room_invite_screen.dart';
import 'chat_room_more/notices_screen.dart';
import 'user_profile_detail_screen.dart';
import 'report_dialog.dart';
import 'chat_room_more/create_poll_screen.dart';
import 'chat_room_more/poll_bubble.dart';

import '../widgets/chat/date_divider.dart';
import '../widgets/chat/system_message.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/notice_banner.dart';
import '../widgets/chat/attach_button.dart';
import 'package:messenger/services/storage_service.dart';
import 'package:messenger/services/image_service.dart';
import 'package:messenger/services/video_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String? initialScrollToMessageId;
  const ChatRoomScreen(
      {super.key, required this.roomId, this.initialScrollToMessageId});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late Stream<QuerySnapshot> _messagesStream;
  late Stream<QuerySnapshot> _membersStream;

  bool _isSearching = false;
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _searchLoading = false;
  int _searchIndex = 0;

  String? _refGroupId;
  String? _roomType;
  String _myRole = 'member';
  String _roomName = '';
  String _groupName = '';
  String _myName = '';
  bool _isMuted = false;

  String _otherUserName = '';
  String _otherUserPhoto = '';
  String _otherUserUid = '';

  final Map<String, Map<String, dynamic>> _userProfileCache = {};

  String? _highlightMessageId;
  bool _showAttachPanel = false;
  Map<String, dynamic>? _replyToData;
  String? _replyToId;
  Map<String, dynamic>? _pinnedMessage;
  bool _noticeBannerDismissed = false;

  final List<QueryDocumentSnapshot> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 30;
  QueryDocumentSnapshot? _lastStreamDoc;

  final Map<String, GlobalKey> _messageKeys = {};
  bool _uploadingMedia = false;

  // 낙관적 UI용 업로딩 메시지 맵
  final Map<String, _UploadingMessage> _uploadingMessages = {};

  String get currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final chatService = context.read<ChatService>();
    _messagesStream = chatService.getMessages(widget.roomId);
    _membersStream = chatService.getRoomMembers(widget.roomId);
    chatService.updateLastReadTime(widget.roomId);
    _loadRoomMeta();
    _loadMuteState();
    _scrollController.addListener(_onScroll);
    _checkAndSendScheduledMessages();
    if (widget.initialScrollToMessageId != null) {
      _highlightMessageId = widget.initialScrollToMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() {});
        });
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMore) return;
    if (_lastStreamDoc == null) return;
    setState(() => _loadingMore = true);
    final chatService = context.read<ChatService>();
    final baseDoc =
        _olderMessages.isNotEmpty ? _olderMessages.last : _lastStreamDoc!;
    final newDocs = await chatService.loadMoreMessages(
      widget.roomId,
      baseDoc,
      pageSize: _pageSize,
    );
    if (mounted) {
      setState(() {
        _olderMessages.addAll(newDocs);
        _hasMore = newDocs.length >= _pageSize;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMuteState() async {
    final muted = await context
        .read<NotificationService>()
        .getChatRoomMuted(widget.roomId);
    if (mounted) setState(() => _isMuted = muted);
  }

  Future<void> _toggleMute() async {
    final newVal = !_isMuted;
    setState(() => _isMuted = newVal);
    await context
        .read<NotificationService>()
        .setChatRoomMuted(widget.roomId, newVal);
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newVal ? l.chatMuted : l.chatUnmuted)),
      );
    }
  }

  Future<void> _loadRoomMeta() async {
    final db = FirebaseFirestore.instance;
    _myName = context.read<UserProvider>().name;

    final results = await Future.wait([
      db.collection('chat_rooms').doc(widget.roomId).get(),
      db
          .collection('chat_rooms')
          .doc(widget.roomId)
          .collection('room_members')
          .doc(currentUserId)
          .get(),
    ]);

    final roomDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final memberDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;

    if (!mounted) return;

    final roomType = roomDoc.data()?['type'] as String?;
    final memberIds =
        List<String>.from(roomDoc.data()?['member_ids'] as List? ?? []);

    setState(() {
      _refGroupId = roomDoc.data()?['ref_group_id'] as String?;
      _roomType = roomType;
      _myRole = memberDoc.data()?['role'] as String? ?? 'member';
      _roomName = roomDoc.data()?['name'] as String? ?? '';
      _groupName = roomDoc.data()?['group_name'] as String? ?? '';
      _pinnedMessage =
          roomDoc.data()?['pinned_message'] as Map<String, dynamic>?;
    });

    if (roomType == 'direct') {
      final otherUid = memberIds.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      if (otherUid.isNotEmpty) {
        final userDoc = await db.collection('users').doc(otherUid).get();
        if (mounted) {
          setState(() {
            _otherUserUid = otherUid;
            _otherUserName = userDoc.data()?['name'] as String? ?? '';
            _otherUserPhoto =
                userDoc.data()?['profile_image'] as String? ?? '';
          });
          _userProfileCache[otherUid] = {
            'name': _otherUserName,
            'photo': _otherUserPhoto,
          };
        }
      }
    }
  }

  Future<Map<String, dynamic>> _getUserProfile(String uid) async {
    if (_userProfileCache.containsKey(uid)) return _userProfileCache[uid]!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = {
      'name': doc.data()?['name'] as String? ?? '',
      'photo': doc.data()?['profile_image'] as String? ?? '',
    };
    _userProfileCache[uid] = data;
    return data;
  }

  Future<void> _pinMessage(
      Map<String, dynamic> data, String messageId) async {
    final l = AppLocalizations.of(context);
    final senderName = data['sender_name'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final now = Timestamp.now();
    final pinData = {
      'text': text,
      'sender_name': senderName,
      'message_id': messageId,
      'pinned_at': now,
    };
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final roomRef = db.collection('chat_rooms').doc(widget.roomId);
    batch.update(roomRef, {'pinned_message': pinData});
    batch.set(roomRef.collection('notices').doc(messageId), {
      ...pinData,
      'pinned_by': currentUserId,
    });
    await batch.commit();
    if (mounted) {
      setState(() {
        _pinnedMessage = pinData;
        _noticeBannerDismissed = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.noticePinned)));
    }
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext == null) {
      _loadUntilMessageVisible(messageId);
      return;
    }
    _doScrollToMessage(messageId, key!);
  }

  void _doScrollToMessage(String messageId, GlobalKey key) {
    if (key.currentContext == null) return;
    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );
    setState(() => _highlightMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
  }

  Future<void> _loadUntilMessageVisible(String messageId) async {
    const maxAttempts = 20;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final key = _messageKeys[messageId];
      if (key?.currentContext != null) {
        _doScrollToMessage(messageId, key!);
        return;
      }
      if (_messageKeys.containsKey(messageId)) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        final k = _messageKeys[messageId];
        if (k?.currentContext != null) {
          _doScrollToMessage(messageId, k!);
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final k2 = _messageKeys[messageId];
          if (k2?.currentContext != null) _doScrollToMessage(messageId, k2!);
        });
        return;
      }
      if (!_hasMore) break;
      while (_loadingMore) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      await _loadMoreMessages();
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
  }

  void _showMessageOptions(
    BuildContext context,
    Map<String, dynamic> data,
    String messageId,
    AppLocalizations l,
    ColorScheme colorScheme,
  ) {
    final text = data['text'] as String? ?? '';
    final isMe = data['sender_id'] == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
              ListTile(
                leading: Icon(Icons.reply_outlined, color: colorScheme.primary),
                title: Text(l.replyMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _replyToId = messageId;
                    _replyToData = data;
                    _showAttachPanel = false;
                  });
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.campaign_outlined, color: colorScheme.primary),
                title: Text(l.pinAsNotice),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinMessage(data, messageId);
                },
              ),
              ListTile(
                leading: Icon(Icons.copy_outlined,
                    color: colorScheme.onSurface.withOpacity(0.7)),
                title: Text(l.copyMessage),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.messageCopied)));
                },
              ),
              ListTile(
                leading: Icon(Icons.note_outlined,
                    color: colorScheme.onSurface.withOpacity(0.7)),
                title: Text(l.memoMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChatMemoSheet(context, data, messageId, l, colorScheme);
                },
              ),
              ListTile(
                leading: Icon(Icons.share_outlined,
                    color: colorScheme.onSurface.withOpacity(0.7)),
                title: Text(l.shareMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(text);
                },
              ),
              if (!isMe)
                ListTile(
                  leading: Icon(Icons.flag_outlined, color: colorScheme.error),
                  title: Text(l.reportMessage,
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    showReportDialog(
                      context: context,
                      onSubmit: (reason, otherText) =>
                          context.read<ReportService>().reportMessage(
                        messageId: messageId,
                        targetOwnerId: data['sender_id'] as String? ?? '',
                        roomId: widget.roomId,
                        reason: reason,
                        otherText: otherText,
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatMemoSheet(
    BuildContext context,
    Map<String, dynamic> data,
    String messageId,
    AppLocalizations l,
    ColorScheme colorScheme,
  ) {
    final text = data['text'] as String? ?? '';
    final senderName = data['sender_name'] as String? ?? '';
    final sentAt = data['created_at'] as Timestamp?;
    final controller = TextEditingController(text: text);

    final type = data['type'] as String? ?? 'text';
    final List<Map<String, dynamic>> attachments = [];
    if (type == 'image') {
      final imageUrls =
          List<String>.from(data['image_urls'] as List? ?? []);
      for (final url in imageUrls) {
        attachments.add({
          'type': 'image',
          'url': url,
          'name': '이미지',
          'size': 0,
          'mime_type': 'image/jpeg',
        });
      }
    } else if (type == 'video') {
      final videoUrl = data['video_url'] as String? ?? '';
      final thumbnailUrl = data['thumbnail_url'] as String? ?? '';
      if (videoUrl.isNotEmpty) {
        attachments.add({
          'type': 'video',
          'url': videoUrl,
          'thumbnail_url': thumbnailUrl,
          'name': '동영상',
          'size': 0,
          'mime_type': 'video/mp4',
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(l.memoMessage,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '$_groupName › $_roomName · $senderName',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
              const SizedBox(height: 12),
              if (type == 'text' || text.isNotEmpty)
                TextField(
                  controller: controller,
                  maxLines: 6,
                  minLines: 3,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.3)),
                    ),
                    filled: true,
                    fillColor:
                        colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  ),
                ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: attachments.map((att) {
                    final attType = att['type'] as String;
                    if (attType == 'image') {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(att['url'] as String,
                            width: 80, height: 80, fit: BoxFit.cover),
                      );
                    } else if (attType == 'video') {
                      final thumb = att['thumbnail_url'] as String? ?? '';
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: thumb.isNotEmpty
                                ? Image.network(thumb,
                                    width: 80, height: 80, fit: BoxFit.cover)
                                : Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.black54,
                                    child: const Icon(Icons.videocam,
                                        color: Colors.white)),
                          ),
                          const Icon(Icons.play_arrow,
                              color: Colors.white, size: 28),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final content = controller.text.trim();
                  if (content.isEmpty && attachments.isEmpty) return;
                  await context.read<MemoService>().memoFromChat(
                    content: content,
                    groupId: _refGroupId ?? '',
                    groupName: _groupName,
                    roomId: widget.roomId,
                    roomName: _roomName,
                    messageId: messageId,
                    senderName: senderName,
                    originalSentAt: sentAt ?? Timestamp.now(),
                    attachments: attachments,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(l.memoSaved)));
                  }
                },
                child: Text(l.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    context.read<ChatService>().updateLastReadTime(widget.roomId);
    super.dispose();
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (_refGroupId != null) {
      final isBanned =
          await context.read<BlockService>().isGroupBanned(_refGroupId!);
      if (isBanned) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 그룹에서 차단되어 메시지를 보낼 수 없습니다')),
          );
        }
        return;
      }
    }

    _msgController.clear();
    final replyId = _replyToId;
    final replyData = _replyToData;
    if (mounted) setState(() { _replyToId = null; _replyToData = null; });

    final userProvider = context.read<UserProvider>();
    final chatService = context.read<ChatService>();

    await chatService.sendMessage(
      widget.roomId,
      text,
      senderName: _myName,
      senderPhotoUrl: userProvider.photoUrl,
      replyToId: replyId,
      replyToText: replyData != null
          ? (replyData['text'] as String? ?? '').length > 80
              ? '${(replyData['text'] as String).substring(0, 80)}…'
              : replyData['text'] as String? ?? ''
          : null,
      replyToSender: replyData?['sender_name'] as String?,
    );
    chatService.updateLastReadTime(widget.roomId);
  }

  // ── 이미지 전송 (낙관적 UI) ──────────────────────────────────────────────────
  Future<void> _sendImages() async {
    setState(() => _showAttachPanel = false);

    final files = await ImageService().pickAndCompressMultipleImages();
    if (files.isEmpty || !mounted) return;

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final messageId = chatService.generateMessageId(widget.roomId);

    // ① 로컬 파일로 즉시 UI에 표시
    setState(() {
      _uploadingMessages[messageId] = _UploadingMessage(
        messageId: messageId,
        type: 'image',
        imageFiles: files,
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl ?? '',
        createdAt: DateTime.now(),
      );
    });

    try {
      // ② 백그라운드 업로드
      final imageUrls = await StorageService().uploadChatImages(
        roomId: widget.roomId,
        messageId: messageId,
        files: files,
      );
      if (!mounted) return;

      // ③ Firestore 저장
      await chatService.sendImageMessage(
        widget.roomId,
        messageId: messageId,
        imageUrls: imageUrls,
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl,
      );
      chatService.updateLastReadTime(widget.roomId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingMessages[messageId]?.failed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 전송에 실패했습니다')),
        );
      }
    } finally {
      // ④ 스트림이 실제 메시지 받으면 로컬 제거
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _uploadingMessages.remove(messageId));
      }
    }
  }

  // ── 동영상 전송 (낙관적 UI) ──────────────────────────────────────────────────
  Future<void> _sendVideo() async {
    setState(() => _showAttachPanel = false);

    final file = await VideoService().pickVideo();
    if (file == null || !mounted) return;

    if (VideoService().isVideoSizeExceeded(file)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동영상 크기가 20MB를 초과합니다')),
        );
      }
      return;
    }

    // 압축 + 썸네일은 기다려야 함
    setState(() => _uploadingMedia = true);
    final result = await VideoService().compressAndGetThumbnail(file);
    if (!mounted) return;
    setState(() => _uploadingMedia = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동영상 처리에 실패했습니다')),
      );
      return;
    }

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final messageId = chatService.generateMessageId(widget.roomId);

    // ① 썸네일로 즉시 UI 표시
    setState(() {
      _uploadingMessages[messageId] = _UploadingMessage(
        messageId: messageId,
        type: 'video',
        thumbnailFile: result['thumbnail'],
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl ?? '',
        createdAt: DateTime.now(),
      );
    });

    try {
      // ② 백그라운드 업로드
      final urls = await StorageService().uploadChatVideo(
        roomId: widget.roomId,
        messageId: messageId,
        videoFile: result['video']!,
        thumbnailFile: result['thumbnail']!,
      );
      VideoService().clearCache(); // fire-and-forget
      if (!mounted) return;

      // ③ Firestore 저장
      await chatService.sendVideoMessage(
        widget.roomId,
        messageId: messageId,
        videoUrl: urls['videoUrl']!,
        thumbnailUrl: urls['thumbnailUrl']!,
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl,
      );
      chatService.updateLastReadTime(widget.roomId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingMessages[messageId]?.failed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동영상 전송에 실패했습니다')),
        );
      }
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _uploadingMessages.remove(messageId));
      }
    }
  }

  Future<void> _checkAndSendScheduledMessages() async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();
    final snap = await db
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('scheduled_messages')
        .where('scheduled_at', isLessThanOrEqualTo: now)
        .where('sent', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      final data = doc.data();
      await db
          .collection('chat_rooms')
          .doc(widget.roomId)
          .collection('messages')
          .add({
        'text': data['text'] as String? ?? '',
        'sender_id': data['sender_id'] as String? ?? currentUserId,
        'sender_name': data['sender_name'] as String? ?? _myName,
        'type': 'text',
        'is_system': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      await doc.reference.update({'sent': true});
    }
    if (snap.docs.isNotEmpty) {
      final lastText = snap.docs.last.data()['text'] as String? ?? '';
      await db.collection('chat_rooms').doc(widget.roomId).update({
        'last_message': lastText,
        'last_time': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showScheduledMessageSheet() {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    DateTime? selectedDateTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  Icon(Icons.schedule_send_outlined,
                      color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('예약 메시지',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  decoration: InputDecoration(
                    hintText: '메시지를 입력하세요',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final serverNow = await _fetchServerTime();
                    final today = DateTime(
                        serverNow.year, serverNow.month, serverNow.day);
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: today,
                      firstDate: today.subtract(const Duration(days: 1)),
                      lastDate: today.add(const Duration(days: 30)),
                      selectableDayPredicate: (day) => !day.isBefore(today),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                        context: ctx, initialTime: TimeOfDay.now());
                    if (time == null) return;
                    final picked = DateTime(date.year, date.month, date.day,
                        time.hour, time.minute);
                    final serverNowCheck = await _fetchServerTime();
                    if (picked.isBefore(
                        serverNowCheck.add(const Duration(minutes: 1)))) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('현재 시간보다 최소 1분 이후로 설정해주세요')));
                      }
                      return;
                    }
                    setSheet(() => selectedDateTime = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(selectedDateTime != null
                      ? '${selectedDateTime!.year}.${selectedDateTime!.month.toString().padLeft(2, '0')}.${selectedDateTime!.day.toString().padLeft(2, '0')} ${selectedDateTime!.hour.toString().padLeft(2, '0')}:${selectedDateTime!.minute.toString().padLeft(2, '0')}'
                      : '전송 시간 선택'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: selectedDateTime != null
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('메시지를 입력해주세요')));
                      return;
                    }
                    if (selectedDateTime == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('전송 시간을 선택해주세요')));
                      return;
                    }
                    await FirebaseFirestore.instance
                        .collection('chat_rooms')
                        .doc(widget.roomId)
                        .collection('scheduled_messages')
                        .add({
                      'text': text,
                      'sender_id': currentUserId,
                      'sender_name': _myName,
                      'scheduled_at': Timestamp.fromDate(selectedDateTime!),
                      'sent': false,
                      'created_at': FieldValue.serverTimestamp(),
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${selectedDateTime!.month}/${selectedDateTime!.day} ${selectedDateTime!.hour.toString().padLeft(2, '0')}:${selectedDateTime!.minute.toString().padLeft(2, '0')} 에 전송 예약됨'),
                      ));
                    }
                  },
                  child: const Text('예약 등록'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<DateTime> _fetchServerTime() async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('_server_time').doc('ping');
    await ref.set({'t': FieldValue.serverTimestamp()});
    final snap = await ref.get();
    final ts = snap.data()?['t'] as Timestamp?;
    return ts?.toDate() ?? DateTime.now();
  }

  void _toggleAttachPanel() {
    setState(() => _showAttachPanel = !_showAttachPanel);
    if (_showAttachPanel) FocusScope.of(context).unfocus();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
        _searchResults = [];
        _searchIndex = 0;
        _highlightMessageId = null;
      }
    });
  }

  Future<void> _searchMessages(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchLoading = false;
        _searchIndex = 0;
        _highlightMessageId = null;
      });
      return;
    }
    setState(() => _searchLoading = true);
    final snap = await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .get();
    final results = snap.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final text = data['text'] as String? ?? '';
      final isSystem = data['is_system'] as bool? ?? false;
      return !isSystem && text.toLowerCase().contains(query.toLowerCase());
    }).toList();
    setState(() {
      _searchResults = results;
      _searchLoading = false;
      _searchIndex = 0;
    });
    if (results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMessage(results[0].id);
      });
    }
  }

  void _searchNavigate(int delta) {
    if (_searchResults.isEmpty) return;
    final next = (_searchIndex + delta).clamp(0, _searchResults.length - 1);
    if (next == _searchIndex) return;
    setState(() => _searchIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessage(_searchResults[next].id);
    });
  }

  Future<void> _leaveRoom(AppLocalizations l) async {
    if (_myRole == 'owner') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.ownerCannotLeave)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.leaveRoom),
        content: Text(l.leaveRoomConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.leave),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final batch = FirebaseFirestore.instance.batch();
    final roomRef =
        FirebaseFirestore.instance.collection('chat_rooms').doc(widget.roomId);
    batch.update(
        roomRef, {'member_ids': FieldValue.arrayRemove([currentUserId])});
    batch.delete(roomRef.collection('room_members').doc(currentUserId));
    batch.set(roomRef.collection('messages').doc(), {
      'is_system': true,
      'text': '$_myName님이 나갔습니다.',
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    if (mounted) Navigator.pop(context);
  }

  void _showDropdownMenu(BuildContext context, AppLocalizations l) async {
    final colorScheme = Theme.of(context).colorScheme;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final result = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'participants',
          child: Row(children: [
            Icon(Icons.people_outline, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(l.participants),
          ]),
        ),
        PopupMenuItem(
          value: 'invite',
          child: Row(children: [
            Icon(Icons.person_add_outlined,
                color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(l.inviteMembers),
          ]),
        ),
        PopupMenuItem(
          value: 'notices',
          child: Row(children: [
            Icon(Icons.campaign_outlined, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Text(l.noticeHistory),
          ]),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Row(children: [
            Icon(
              _isMuted
                  ? Icons.notifications_outlined
                  : Icons.notifications_off_outlined,
              color: colorScheme.onSurface.withOpacity(0.7),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(_isMuted ? l.chatUnmuteAction : l.chatMuteAction),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: Row(children: [
            Icon(Icons.exit_to_app, color: colorScheme.error, size: 20),
            const SizedBox(width: 12),
            Text(l.leaveRoom, style: TextStyle(color: colorScheme.error)),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    switch (result) {
      case 'participants':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatRoomParticipantsScreen(
            roomId: widget.roomId,
            roomType: _roomType ?? '',
            currentUserId: currentUserId,
            myRole: _myRole,
          ),
        ));
        break;
      case 'invite':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatRoomInviteScreen(
              roomId: widget.roomId,
              currentUserId: currentUserId,
              refGroupId: _refGroupId),
        ));
        break;
      case 'notices':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NoticesScreen(roomId: widget.roomId),
        ));
        break;
      case 'mute':
        await _toggleMute();
        break;
      case 'leave':
        _leaveRoom(l);
        break;
    }
  }

  int _calculateUnread(
      Timestamp? createdAt, List<QueryDocumentSnapshot> members) {
    if (createdAt == null) return 0;
    int unread = 0;
    for (final member in members) {
      if (member.id == currentUserId) continue;
      final data = member.data() as Map<String, dynamic>;
      final Timestamp? lastRead = data['last_read_time'];
      if (lastRead == null || lastRead.compareTo(createdAt) < 0) unread++;
    }
    return unread;
  }

  bool _needsDateDivider(List<QueryDocumentSnapshot> messages, int index) {
    final current = (messages[index].data()
        as Map<String, dynamic>)['created_at'] as Timestamp?;
    if (current == null) return false;
    if (index == messages.length - 1) return true;
    final prev = (messages[index + 1].data()
        as Map<String, dynamic>)['created_at'] as Timestamp?;
    if (prev == null) return false;
    final curDate = current.toDate();
    final prevDate = prev.toDate();
    return curDate.year != prevDate.year ||
        curDate.month != prevDate.month ||
        curDate.day != prevDate.day;
  }

  bool _isContinuous(List<QueryDocumentSnapshot> messages, int index) {
    if (index == messages.length - 1) return false;
    final cur = messages[index].data() as Map<String, dynamic>;
    final prev = messages[index + 1].data() as Map<String, dynamic>;
    if (cur['is_system'] == true || prev['is_system'] == true) return false;
    return cur['sender_id'] == prev['sender_id'];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final isDm = _roomType == 'direct';
    final appBarTitle =
        isDm && _otherUserName.isNotEmpty ? _otherUserName : _roomName;
    final hasOtherPhoto = _otherUserPhoto.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: isDm
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: GestureDetector(
                  onTap: _otherUserUid.isNotEmpty
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => UserProfileDetailScreen(
                              uid: _otherUserUid,
                              displayName: _otherUserName,
                              photoUrl: _otherUserPhoto,
                            ),
                          ))
                      : null,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.tertiaryContainer,
                    backgroundImage: hasOtherPhoto
                        ? CachedNetworkImageProvider(_otherUserPhoto)
                        : null,
                    onBackgroundImageError: hasOtherPhoto ? (_, __) {} : null,
                    child: hasOtherPhoto
                        ? null
                        : (_otherUserName.isNotEmpty
                            ? Text(
                                _otherUserName[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              )
                            : Icon(Icons.person,
                                size: 16,
                                color: colorScheme.onTertiaryContainer)),
                  ),
                ),
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.searchMessages,
                  hintStyle: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.4),
                      fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  isDense: true,
                  prefixIcon: Icon(Icons.search,
                      size: 18,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                ),
                style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                  _searchMessages(val);
                },
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appBarTitle.isNotEmpty ? appBarTitle : 'Chat Room'),
                  if (_isMuted) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.notifications_off_outlined,
                        size: 16,
                        color: colorScheme.onSurface.withOpacity(0.4)),
                  ],
                ],
              ),
        titleSpacing: _isSearching ? 0 : null,
        actions: [
          if (_isSearching) ...[
            if (_searchLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_searchResults.isNotEmpty) ...[
              Center(
                child: Text('${_searchIndex + 1}/${_searchResults.length}',
                    style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.7))),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _searchIndex < _searchResults.length - 1
                    ? () => _searchNavigate(1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _searchIndex > 0 ? () => _searchNavigate(-1) : null,
              ),
            ] else if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(l.noSearchResults,
                      style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ),
              ),
            IconButton(icon: const Icon(Icons.close), onPressed: _toggleSearch),
          ] else ...[
            IconButton(
                icon: const Icon(Icons.search), onPressed: _toggleSearch),
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showDropdownMenu(ctx, l),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_pinnedMessage != null)
            if (!_noticeBannerDismissed)
              NoticeBanner(
                text: _pinnedMessage!['text'] as String? ?? '',
                onDismiss: () => setState(() => _noticeBannerDismissed = true),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NoticesScreen(roomId: widget.roomId))),
                colorScheme: colorScheme,
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding:
                      const EdgeInsets.only(right: 8, top: 4, bottom: 2),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _noticeBannerDismissed = false),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.campaign_outlined,
                          size: 18, color: colorScheme.primary),
                    ),
                  ),
                ),
              ),

          if (_isSearching && _searchLoading)
            LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: colorScheme.surface,
                color: colorScheme.primary),

          if (_uploadingMedia)
            LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: colorScheme.surface,
                color: colorScheme.primary),

          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: context.read<BlockService>().getBlockedUidSet(),
              builder: (context, blockedSnap) {
                final blockedUids = blockedSnap.data ?? {};
                return StreamBuilder<QuerySnapshot>(
                  stream: _membersStream,
                  builder: (context, membersSnap) {
                    final members = membersSnap.data?.docs ?? [];
                    return StreamBuilder<QuerySnapshot>(
                      stream: _messagesStream,
                      builder: (context, messagesSnap) {
                        if (messagesSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final messages = messagesSnap.data?.docs ?? [];

                        if (messages.isNotEmpty &&
                            _lastStreamDoc?.id != messages.last.id) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _lastStreamDoc = messages.last);
                            }
                          });
                        }

                        final streamIds = messages.map((d) => d.id).toSet();
                        final uniqueOlder = _olderMessages
                            .where((d) => !streamIds.contains(d.id))
                            .toList();
                        final allMessages = [
                          ...messages,
                          ...uniqueOlder
                        ].where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final senderId =
                              data['sender_id'] as String? ?? '';
                          final isSystem =
                              data['is_system'] as bool? ?? false;
                          return isSystem || !blockedUids.contains(senderId);
                        }).toList();

                        if (allMessages.isEmpty &&
                            _uploadingMessages.isEmpty) {
                          return Center(
                            child: Text(l.noMessages,
                                style: TextStyle(
                                    color: colorScheme.onSurface
                                        .withOpacity(0.4))),
                          );
                        }

                        // 업로딩 메시지 리스트 (순서 보장용)
                        final uploadingList =
                            _uploadingMessages.values.toList();

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding:
                              const EdgeInsets.only(top: 8, bottom: 8),
                          cacheExtent: 3000,
                          itemCount: uploadingList.length +
                              allMessages.length +
                              (_loadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // ── 업로딩 메시지 (하단 = index 0 근처) ──────────
                            if (index < uploadingList.length) {
                              // reverse: true이므로 마지막 추가된 것이 index 0
                              final msg = uploadingList[
                                  uploadingList.length - 1 - index];
                              return _buildUploadingBubble(
                                  msg, colorScheme);
                            }

                            final adjustedIndex =
                                index - uploadingList.length;

                            // ── 로딩 인디케이터 ────────────────────────────
                            if (adjustedIndex == allMessages.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                ),
                              );
                            }

                            // ── 일반 메시지 ────────────────────────────────
                            final data = allMessages[adjustedIndex]
                                .data() as Map<String, dynamic>;
                            final msgId = allMessages[adjustedIndex].id;
                            final isSystem =
                                data['is_system'] as bool? ?? false;
                            final needsDate = _needsDateDivider(
                                allMessages, adjustedIndex);
                            final isContinuous =
                                _isContinuous(allMessages, adjustedIndex);
                            final senderId =
                                data['sender_id'] as String? ?? '';

                            _messageKeys.putIfAbsent(
                                msgId, () => GlobalKey());

                            final storedPhoto =
                                data['sender_photo_url'] as String? ?? '';

                            return Column(
                              key: _messageKeys[msgId],
                              children: [
                                if (needsDate)
                                  DateDivider(
                                    date: (data['created_at'] as Timestamp)
                                        .toDate(),
                                    colorScheme: colorScheme,
                                  ),
                                if (isSystem && data['type'] != 'poll')
                                  SystemMessage(
                                    text: data['text'] ?? '',
                                    colorScheme: colorScheme,
                                  )
                                else if (data['type'] == 'poll')
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    child: PollBubble(
                                      roomId: widget.roomId,
                                      pollId: data['poll_id'] as String,
                                      colorScheme: colorScheme,
                                      refGroupId: _refGroupId,
                                    ),
                                  )
                                else
                                  storedPhoto.isNotEmpty
                                      ? _buildBubble(
                                          context: context,
                                          data: data,
                                          msgId: msgId,
                                          photoUrl: storedPhoto,
                                          isContinuous: isContinuous,
                                          members: members,
                                          colorScheme: colorScheme,
                                          l: l,
                                        )
                                      : FutureBuilder<Map<String, dynamic>>(
                                          future: senderId.isNotEmpty
                                              ? _getUserProfile(senderId)
                                              : Future.value(
                                                  {'photo': '', 'name': ''}),
                                          builder: (ctx, snap) {
                                            final photo = snap.data?['photo']
                                                    as String? ??
                                                '';
                                            return _buildBubble(
                                              context: context,
                                              data: data,
                                              msgId: msgId,
                                              photoUrl: photo,
                                              isContinuous: isContinuous,
                                              members: members,
                                              colorScheme: colorScheme,
                                              l: l,
                                            );
                                          },
                                        ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (!_isSearching) _buildMessageInput(colorScheme, l),
          if (_showAttachPanel && !_isSearching)
            _buildAttachPanel(colorScheme, l),
        ],
      ),
    );
  }

  // ── 일반 메시지 버블 ──────────────────────────────────────────────────────────
  Widget _buildBubble({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String msgId,
    required String photoUrl,
    required bool isContinuous,
    required List<QueryDocumentSnapshot> members,
    required ColorScheme colorScheme,
    required AppLocalizations l,
  }) {
    final enrichedData = {...data, 'sender_photo_url': photoUrl};

    return GestureDetector(
      onLongPress: () =>
          _showMessageOptions(context, data, msgId, l, colorScheme),
      child: MessageBubble(
        data: enrichedData,
        isMe: data['sender_id'] == currentUserId,
        isContinuous: isContinuous,
        unreadCount:
            _calculateUnread(data['created_at'] as Timestamp?, members),
        colorScheme: colorScheme,
        isHighlighted: msgId == _highlightMessageId,
        searchQuery: _isSearching ? _searchQuery : '',
        onAvatarTap: data['sender_id'] != null &&
                data['sender_id'] != currentUserId
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UserProfileDetailScreen(
                    uid: data['sender_id'] as String,
                    photoUrl: photoUrl,
                    displayName: data['sender_name'] as String? ?? '',
                  ),
                ))
            : null,
        onReplyTap: data['reply_to_id'] != null
            ? () => _scrollToMessage(data['reply_to_id'] as String)
            : null,
      ),
    );
  }

  // ── 업로딩 중 버블 (낙관적 UI) ───────────────────────────────────────────────
  Widget _buildUploadingBubble(
      _UploadingMessage msg, ColorScheme colorScheme) {
    Widget content;

    if (msg.type == 'image') {
      content = msg.imageFiles.length == 1
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(msg.imageFiles[0],
                  width: 200, height: 200, fit: BoxFit.cover),
            )
          : SizedBox(
              width: 200,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: msg.imageFiles.length,
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(msg.imageFiles[i], fit: BoxFit.cover),
                ),
              ),
            );
    } else if (msg.type == 'video' && msg.thumbnailFile != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(msg.thumbnailFile!,
                width: 200, height: 150, fit: BoxFit.cover),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 32),
            ),
          ],
        ),
      );
    } else {
      content = const SizedBox(width: 80, height: 80);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 4),
            child: Text(
              msg.failed ? '실패' : '전송 중...',
              style: TextStyle(
                fontSize: 10,
                color: msg.failed
                    ? colorScheme.error
                    : colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.62,
            ),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Stack(
              children: [
                content,
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: msg.failed ? Colors.black45 : Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: msg.failed
                          ? const Icon(Icons.error_outline,
                              color: Colors.white, size: 32)
                          : const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(ColorScheme colorScheme, AppLocalizations l) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyToData != null)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                      color: colorScheme.onSurface.withOpacity(0.08)),
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _replyToData!['sender_name'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyToData!['text'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  colorScheme.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 18,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _replyToId = null;
                      _replyToData = null;
                    }),
                  ),
                ],
              ),
            ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                  top: BorderSide(
                      color: colorScheme.onSurface.withOpacity(0.08))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: AnimatedRotation(
                    turns: _showAttachPanel ? 0.125 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.add,
                        color: _showAttachPanel
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: _toggleAttachPanel,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    onTap: () {
                      if (_showAttachPanel) {
                        setState(() => _showAttachPanel = false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: l.typeMessage,
                      hintStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 2000,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon:
                      Icon(Icons.send_rounded, color: colorScheme.primary),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachPanel(ColorScheme colorScheme, AppLocalizations l) {
    final items = [
      AttachItem(
          icon: Icons.photo_outlined,
          label: l.attachPhotos,
          color: Colors.green,
          onTap: _sendImages),
      AttachItem(
          icon: Icons.videocam_outlined,
          label: l.attachVideos,
          color: Colors.red,
          onTap: _sendVideo),
      AttachItem(
          icon: Icons.mic_outlined,
          label: l.attachVoice,
          color: Colors.orange,
          onTap: () {}),
      AttachItem(
          icon: Icons.call_outlined,
          label: l.attachCall,
          color: Colors.blue,
          onTap: () {}),
      AttachItem(
          icon: Icons.videocam,
          label: l.attachVideoCall,
          color: Colors.purple,
          onTap: () {}),
      AttachItem(
          icon: Icons.auto_awesome_outlined,
          label: l.attachAiMinutes,
          color: Colors.teal,
          onTap: () {}),
      AttachItem(
          icon: Icons.insert_drive_file_outlined,
          label: l.attachFile,
          color: Colors.brown,
          onTap: () {}),
      AttachItem(
          icon: Icons.contacts_outlined,
          label: l.attachContact,
          color: Colors.indigo,
          onTap: () {}),
      AttachItem(
        icon: Icons.schedule_send_outlined,
        label: l.attachSchedule,
        color: colorScheme.primary,
        onTap: () {
          setState(() => _showAttachPanel = false);
          _showScheduledMessageSheet();
        },
      ),
      AttachItem(
        icon: Icons.poll_outlined,
        label: l.attachPoll,
        color: Colors.deepPurple,
        onTap: () {
          setState(() => _showAttachPanel = false);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CreatePollScreen(roomId: widget.roomId),
          ));
        },
      ),
    ];

    return SafeArea(
      top: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        color: colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          children: items
              .map((item) =>
                  AttachButton(item: item, colorScheme: colorScheme))
              .toList(),
        ),
      ),
    );
  }
}

// ── 업로딩 메시지 모델 ─────────────────────────────────────────────────────────
class _UploadingMessage {
  final String messageId;
  final String type;
  final List<File> imageFiles;
  final File? thumbnailFile;
  final String senderName;
  final String senderPhotoUrl;
  final DateTime createdAt;
  bool failed;

  _UploadingMessage({
    required this.messageId,
    required this.type,
    this.imageFiles = const [],
    this.thumbnailFile,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.createdAt,
    this.failed = false,
  });
}