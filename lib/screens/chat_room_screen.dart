import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/block_service.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../services/image_service.dart';
import '../services/video_service.dart';
import '../services/file_service.dart';
import '../services/audio_service.dart';
import '../services/local_preferences_service.dart';
import '../utils/user_cache.dart';
import '../utils/user_display.dart';
import 'chat_room_more/chat_room_participants_screen.dart';
import 'chat_room_more/chat_room_invite_screen.dart';
import 'chat_room_more/notices_screen.dart';
import 'chat_room_more/create_poll_screen.dart';
import 'chat_room_more/poll_bubble.dart';
import 'chat_room_more/chat_room_shared_assets_screen.dart';
import 'chat_room_more/location_share_sheet.dart';
import '../widgets/chat/contact_share_sheet.dart';
import 'user_profile_detail_screen.dart';
import '../widgets/chat/date_divider.dart';
import '../widgets/chat/system_message.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/notice_banner.dart';
import '../widgets/chat/attach_button.dart';
import '../widgets/chat/chat_memo_sheet.dart';
import '../widgets/chat/chat_scheduled_message_sheet.dart';
import '../widgets/chat/chat_message_options_sheet.dart';
import '../widgets/chat/voice_message_recorder_sheet.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String? initialScrollToMessageId;
  final bool isDesktopMode;
  final VoidCallback? onClosePanel;
  const ChatRoomScreen({
    super.key,
    required this.roomId,
    this.initialScrollToMessageId,
    this.isDesktopMode = false,
    this.onClosePanel,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  late Stream<QuerySnapshot> _messagesStream;
  late Stream<QuerySnapshot> _membersStream;

  // ── 검색 상태 ──────────────────────────────────────────────────────────────
  bool _isSearching = false;
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _searchResults = [];
  bool _searchLoading = false;
  int _searchIndex = 0;

  // ── 룸 메타 (ChatProvider에서 관리) ───────────────────────────────────────
  RoomMeta? _roomMeta;
  bool _metaLoading = true;
  bool _isMuted = false;

  // ── UI 상태 ────────────────────────────────────────────────────────────────
  String? _highlightMessageId;
  bool _showAttachPanel = false;
  Map<String, dynamic>? _replyToData;
  String? _replyToId;
  bool _noticeBannerDismissed = false;
  bool _showScrollToBottom = false;

  // ── 새 메시지 배너 ─────────────────────────────────────────────────────────
  String? _newMessagePreviewText;
  String? _newMessagePreviewSender;
  Timer? _previewTimer;

  // ── 페이지네이션 ───────────────────────────────────────────────────────────
  final List<QueryDocumentSnapshot> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 30;
  QueryDocumentSnapshot? _lastStreamDoc;

  // ── 메시지 키 & 업로딩 ──────────────────────────────────────────────────────
  final Map<String, GlobalKey> _messageKeys = {};
  bool _uploadingMedia = false;
  final Map<String, _UploadingMessage> _uploadingMessages = {};
  late final String _prefsUserId;

  // ── 잔상 방지용 현재 표시 중인 roomId ──────────────────────────────────────
  String _displayingRoomId = '';

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _myName => context.read<UserProvider>().name;

  String get _chatDraftKey =>
      LocalPreferencesService.chatDraftKey(_prefsUserId, widget.roomId);

  // ──────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _prefsUserId = context.read<UserProvider>().uid;
    _displayingRoomId = widget.roomId;
    _msgController.addListener(_persistMessageDraft);

    final chatService = context.read<ChatService>();
    final chatProvider = context.read<ChatProvider>();

    chatService.currentRoomId = widget.roomId;
    chatProvider.selectRoom(widget.roomId);
    _messagesStream = chatProvider.getMessageStream(widget.roomId);
    _membersStream = chatProvider.getMemberStream(widget.roomId);
    chatService.updateLastReadTime(widget.roomId);

    _loadRoomMeta();
    _loadMuteState();
    _loadMessageDraft();
    _scrollController.addListener(_onScroll);
    _checkAndSendScheduledMessages();

    if (widget.initialScrollToMessageId != null) {
      _highlightMessageId = widget.initialScrollToMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _persistMessageDraft();
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    context.read<ChatService>().updateLastReadTime(widget.roomId);
    context.read<ChatService>().currentRoomId = null;
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 데이터 로드
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _loadRoomMeta() async {
    if (!mounted) return;

    final chatProvider = context.read<ChatProvider>();
    final cached = chatProvider.getCachedMeta(widget.roomId);
    if (cached != null && mounted) {
      setState(() {
        _roomMeta = cached;
        _metaLoading = false;
      });
    } else {
      setState(() => _metaLoading = true);
    }

    final meta = await chatProvider.loadRoomMeta(widget.roomId);
    if (mounted && widget.roomId == _displayingRoomId) {
      setState(() {
        _roomMeta = meta;
        _metaLoading = false;
      });
    }
  }

  Future<void> _loadMuteState() async {
    final muted = await context.read<NotificationService>().getChatRoomMuted(
      widget.roomId,
    );
    if (mounted) setState(() => _isMuted = muted);
  }

  Future<void> _loadMessageDraft() async {
    final draft = await LocalPreferencesService.getString(_chatDraftKey);
    if (!mounted || draft == null || draft.isEmpty) return;
    _msgController.text = draft;
    _msgController.selection = TextSelection.collapsed(offset: draft.length);
  }

  void _persistMessageDraft() {
    LocalPreferencesService.setString(_chatDraftKey, _msgController.text);
  }

  void _clearMessageDraft() {
    LocalPreferencesService.remove(_chatDraftKey);
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMore || _lastStreamDoc == null) return;
    setState(() => _loadingMore = true);
    final chatService = context.read<ChatService>();
    final baseDoc = _olderMessages.isNotEmpty
        ? _olderMessages.last
        : _lastStreamDoc!;
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
            'sender_id': data['sender_id'] as String? ?? _currentUserId,
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

  // ──────────────────────────────────────────────────────────────────────────
  // 스크롤
  // ──────────────────────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMessages();
    }

    // reverse: true 이므로 offset이 작을수록 바닥
    bool isBottom = _scrollController.offset <= 200;
    if (_showScrollToBottom == isBottom) {
      setState(() {
        _showScrollToBottom = !isBottom;
      });
    }

    // 바닥에 도달하면 배너 자동 닫기
    if (isBottom && _newMessagePreviewText != null) {
      _dismissPreviewBanner();
    }
  }

  void _jumpToBottom() {
    _dismissPreviewBanner();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _scrollToTarget() async {
    final target = widget.initialScrollToMessageId;
    if (target == null || !mounted) return;
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      final key = _messageKeys[target];
      if (key?.currentContext != null) {
        _doScrollToMessage(target, key!);
        return;
      }
    }
    _loadUntilMessageVisible(target);
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      _doScrollToMessage(messageId, key!);
    } else {
      _loadUntilMessageVisible(messageId);
    }
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

  // ──────────────────────────────────────────────────────────────────────────
  // 새 메시지 배너
  // ──────────────────────────────────────────────────────────────────────────

  /// 메시지 타입에 맞는 미리보기 텍스트 반환
  String _getPreviewText(Map<String, dynamic> data, AppLocalizations l) {
    final type = data['type'] as String? ?? 'text';
    switch (type) {
      case 'image':
        return '📷 ${l.attachPhoto}';
      case 'video':
        return '🎥 ${l.attachVideo}';
      case 'audio':
        return '🎙️ ${l.attachAudio}';
      case 'file':
        return '📄 ${data['file_name'] as String? ?? l.attachFile}';
      case 'location':
        return '📍 ${l.attachLocation}';
      case 'contact':
        return '👤 ${l.attachContact}';
      case 'shared_post':
        return '📝 ${data['post_title'] as String? ?? ''}';
      case 'shared_schedule':
        return '📅 ${data['schedule_title'] as String? ?? ''}';
      case 'shared_memo':
        final title = data['memo_title'] as String? ?? '';
        final content = data['memo_content'] as String? ?? '';
        return '🗒 ${title.isNotEmpty ? title : content}';
      default:
        return data['text'] as String? ?? '';
    }
  }

  /// 새 메시지 배너를 표시하거나 갱신
  void _showPreviewBanner(Map<String, dynamic> data, AppLocalizations l) {
    final sender = data['sender_name'] as String? ?? '';
    final text = _getPreviewText(data, l);

    // 같은 발신자면 텍스트만 갱신, 다른 발신자면 발신자도 갱신
    final sameSender = _newMessagePreviewSender == sender;

    setState(() {
      if (!sameSender) _newMessagePreviewSender = sender;
      _newMessagePreviewText = text;
    });

    // 기존 타이머 취소 후 새로 시작 (중첩 방지)
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _dismissPreviewBanner();
    });
  }

  void _dismissPreviewBanner() {
    _previewTimer?.cancel();
    if (mounted) {
      setState(() {
        _newMessagePreviewText = null;
        _newMessagePreviewSender = null;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 액션
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _toggleMute() async {
    final l = AppLocalizations.of(context);
    final newVal = !_isMuted;
    setState(() => _isMuted = newVal);
    await context.read<NotificationService>().setChatRoomMuted(
      widget.roomId,
      newVal,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newVal ? l.chatMuted : l.chatUnmuted)),
      );
    }
  }

  Future<void> _pinMessage(Map<String, dynamic> data, String messageId) async {
    final l = AppLocalizations.of(context);
    final pinData = {
      'text': data['text'] as String? ?? '',
      'sender_name': data['sender_name'] as String? ?? '',
      'message_id': messageId,
      'pinned_at': Timestamp.now(),
    };
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final roomRef = db.collection('chat_rooms').doc(widget.roomId);
    batch.update(roomRef, {'pinned_message': pinData});
    batch.set(roomRef.collection('notices').doc(messageId), {
      ...pinData,
      'pinned_by': _currentUserId,
    });
    await batch.commit();

    if (mounted) {
      context.read<ChatProvider>().updatePinnedMessage(widget.roomId, pinData);
      setState(() {
        _roomMeta = _roomMeta == null
            ? null
            : RoomMeta(
                roomId: _roomMeta!.roomId,
                refGroupId: _roomMeta!.refGroupId,
                roomType: _roomMeta!.roomType,
                myRole: _roomMeta!.myRole,
                roomName: _roomMeta!.roomName,
                groupName: _roomMeta!.groupName,
                pinnedMessage: pinData,
                otherUserUid: _roomMeta!.otherUserUid,
                otherUserName: _roomMeta!.otherUserName,
                otherUserPhoto: _roomMeta!.otherUserPhoto,
                otherUserDeleted: _roomMeta!.otherUserDeleted,
              );
        _noticeBannerDismissed = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.noticePinned)));
    }
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    _clearMessageDraft();
    final replyId = _replyToId;
    final replyData = _replyToData;
    if (mounted)
      setState(() {
        _replyToId = null;
        _replyToData = null;
      });

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

  Future<void> _sendImages() async {
    setState(() => _showAttachPanel = false);
    final files = await ImageService().pickAndCompressMultipleImages();
    if (files.isEmpty || !mounted) return;

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final messageId = chatService.generateMessageId(widget.roomId);

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
      final imageUrls = await StorageService().uploadChatImages(
        roomId: widget.roomId,
        messageId: messageId,
        files: files,
      );
      if (!mounted) return;
      await chatService.sendImageMessage(
        widget.roomId,
        messageId: messageId,
        imageUrls: imageUrls,
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl,
      );
      chatService.updateLastReadTime(widget.roomId);
    } catch (e) {
      if (mounted) setState(() => _uploadingMessages[messageId]?.failed = true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _uploadingMessages.remove(messageId));
      }
    }
  }

  Future<void> _sendVideo() async {
    setState(() => _showAttachPanel = false);
    final file = await VideoService().pickVideo();
    if (file == null || !mounted) return;

    if (VideoService().isVideoSizeExceeded(file)) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.videoSizeExceeded)));
      }
      return;
    }

    setState(() => _uploadingMedia = true);
    final result = await VideoService().compressAndGetThumbnail(file);
    if (!mounted) return;
    setState(() => _uploadingMedia = false);

    if (result == null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.videoProcessingFailed)));
      return;
    }

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final messageId = chatService.generateMessageId(widget.roomId);

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
      final urls = await StorageService().uploadChatVideo(
        roomId: widget.roomId,
        messageId: messageId,
        videoFile: result['video']!,
        thumbnailFile: result['thumbnail']!,
      );
      VideoService().clearCache();
      if (!mounted) return;
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
      if (mounted) setState(() => _uploadingMessages[messageId]?.failed = true);
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _uploadingMessages.remove(messageId));
      }
    }
  }

  Future<void> _leaveRoom(AppLocalizations l) async {
    final meta = _roomMeta;
    if (meta?.myRole == 'owner') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.ownerCannotLeave)));
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
            child: Text(l.cancel),
          ),
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
    final roomRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId);
    batch.update(roomRef, {
      'member_ids': FieldValue.arrayRemove([_currentUserId]),
    });
    batch.delete(roomRef.collection('room_members').doc(_currentUserId));
    batch.set(roomRef.collection('messages').doc(), {
      'is_system': true,
      'text': '$_myName님이 나갔습니다.',
      'created_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    context.read<ChatProvider>().invalidateRoom(widget.roomId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _sendFiles() async {
    setState(() => _showAttachPanel = false);
    final l = AppLocalizations.of(context);
    final pickedFiles = await FileService().pickFiles();
    if (pickedFiles.isEmpty || !mounted) return;

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final validFiles = pickedFiles
        .where((item) => !FileService().isSizeExceeded(item.size))
        .toList();

    final hasOversized = validFiles.length != pickedFiles.length;
    if (hasOversized && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.fileSizeExceeded)));
    }
    if (validFiles.isEmpty) return;

    for (final picked in validFiles) {
      final messageId = chatService.generateMessageId(widget.roomId);
      if (mounted) {
        setState(() {
          _uploadingMessages[messageId] = _UploadingMessage(
            messageId: messageId,
            type: 'file',
            senderName: _myName,
            senderPhotoUrl: userProvider.photoUrl ?? '',
            createdAt: DateTime.now(),
            fileName: picked.name,
            fileSize: picked.size,
            mimeType: picked.mimeType,
          );
        });
      }
      try {
        final uploaded = await StorageService().uploadChatFile(
          roomId: widget.roomId,
          messageId: messageId,
          file: picked.file,
          fileName: picked.name,
          mimeType: picked.mimeType,
        );
        if (!mounted) return;
        await chatService.sendFileMessage(
          widget.roomId,
          messageId: messageId,
          fileUrl: uploaded['url']!,
          fileName: picked.name,
          fileSize: picked.size,
          mimeType: picked.mimeType,
          senderName: _myName,
          senderPhotoUrl: userProvider.photoUrl,
        );
        chatService.updateLastReadTime(widget.roomId);
      } catch (e) {
        if (mounted) {
          setState(() => _uploadingMessages[messageId]?.failed = true);
        }
      } finally {
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          setState(() => _uploadingMessages.remove(messageId));
        }
      }
    }
  }

  Future<void> _sendVoiceMessage() async {
    setState(() => _showAttachPanel = false);
    final result = await showModalBottomSheet<VoiceMessageRecordResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const VoiceMessageRecorderSheet(),
    );

    if (result == null || !mounted) return;

    final audioService = AudioService();
    if (audioService.isSizeExceeded(result.file)) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.audioFileSizeExceeded)));
      return;
    }

    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    final messageId = chatService.generateMessageId(widget.roomId);

    setState(() {
      _uploadingMessages[messageId] = _UploadingMessage(
        messageId: messageId,
        type: 'audio',
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl ?? '',
        createdAt: DateTime.now(),
        fileName: result.fileName,
        fileSize: result.file.lengthSync(),
        mimeType: result.mimeType,
        audioDurationMs: result.durationMs,
      );
    });

    try {
      final uploaded = await StorageService().uploadChatAudio(
        roomId: widget.roomId,
        messageId: messageId,
        file: result.file,
        fileName: result.fileName,
        mimeType: result.mimeType,
      );
      if (!mounted) return;
      await chatService.sendAudioMessage(
        widget.roomId,
        messageId: messageId,
        audioUrl: uploaded['url'] ?? '',
        durationMs: result.durationMs,
        fileName: result.fileName,
        mimeType: result.mimeType,
        senderName: _myName,
        senderPhotoUrl: userProvider.photoUrl,
      );
      chatService.updateLastReadTime(widget.roomId);
    } catch (_) {
      if (mounted) {
        setState(() => _uploadingMessages[messageId]?.failed = true);
      }
    } finally {
      if (await result.file.exists()) await result.file.delete();
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _uploadingMessages.remove(messageId));
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 검색
  // ──────────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────────
  // 바텀시트
  // ──────────────────────────────────────────────────────────────────────────

  void _showMessageOptions(
    BuildContext context,
    Map<String, dynamic> data,
    String messageId,
  ) async {
    final isDesktopLayout = MediaQuery.sizeOf(context).width > 700;
    final canHideMessage = await _resolveCanHideMessage();

    if (!mounted) return;

    if (isDesktopLayout || _getMessageRect(messageId) != null) {
      _showAnchoredMessageOptions(
        context,
        data,
        messageId,
        canHideMessage: canHideMessage,
      );
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChatMessageOptionsSheet(
        data: data,
        messageId: messageId,
        isMe: data['sender_id'] == _currentUserId,
        roomId: widget.roomId,
        canHideMessage: canHideMessage,
        onHide: () => _hideMessage(messageId),
        onEdit: () => _editMessage(messageId, data['text'] as String? ?? ''),
        onDelete: () => _deleteMessage(messageId),
        onReply: () => setState(() {
          _replyToId = messageId;
          _replyToData = data;
          _showAttachPanel = false;
        }),
        onPin: () => _pinMessage(data, messageId),
        onMemo: () => _showChatMemoSheet(context, data, messageId),
      ),
    );
  }

  Future<bool> _resolveCanHideMessage() async {
    bool canHideMessage = false;
    final rType = _roomMeta?.roomType;
    if ((rType == 'group_all' || rType == 'group_sub') &&
        _roomMeta?.refGroupId != null) {
      if (_roomMeta?.myRole == 'owner') {
        canHideMessage = true;
      } else {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('groups')
              .doc(_roomMeta!.refGroupId)
              .collection('members')
              .doc(_currentUserId)
              .get();
          final perms = doc.data()?['permissions'] as Map<String, dynamic>?;
          if (perms?['can_create_sub_chat'] == true) {
            canHideMessage = true;
          }
        } catch (_) {}
      }
    }
    return canHideMessage;
  }

  Rect? _getMessageRect(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.attached) return null;
    final origin = render.localToGlobal(Offset.zero);
    return origin & render.size;
  }

  double _estimateMessageMenuHeight(
    Map<String, dynamic> data, {
    required bool isMe,
    required bool canHideMessage,
  }) {
    var itemCount = 5;
    if (isMe && data['is_deleted'] != true && data['is_hidden'] != true) {
      if (data['type'] == 'text') itemCount += 1;
      itemCount += 1;
    }
    if (!isMe) itemCount += 1;
    if (canHideMessage) itemCount += 1;

    final hasPreview = (data['text'] as String? ?? '').trim().isNotEmpty;
    return (itemCount * 56) + (hasPreview ? 84 : 20);
  }

  void _showAnchoredMessageOptions(
    BuildContext context,
    Map<String, dynamic> data,
    String messageId, {
    required bool canHideMessage,
  }) {
    final rect = _getMessageRect(messageId);
    if (rect == null) return;

    final size = MediaQuery.sizeOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = data['sender_id'] == _currentUserId;
    final menuWidth = (size.width - 24).clamp(240.0, 320.0).toDouble();
    final estimatedHeight = _estimateMessageMenuHeight(
      data,
      isMe: isMe,
      canHideMessage: canHideMessage,
    );
    final maxTop = (size.height - estimatedHeight - 12).clamp(
      12.0,
      size.height,
    );
    final showBelow = rect.center.dy < size.height * 0.58;
    final left = (isMe ? rect.right - menuWidth : rect.left)
        .clamp(12.0, size.width - menuWidth - 12.0)
        .toDouble();
    final top = (showBelow ? rect.bottom + 8 : rect.top - estimatedHeight - 8)
        .clamp(12.0, maxTop)
        .toDouble();

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'message-options',
      barrierColor: Colors.black.withOpacity(0.22),
      pageBuilder: (dialogContext, _, __) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxHeight: size.height * 0.72),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ChatMessageOptionsSheet(
                    data: data,
                    messageId: messageId,
                    isMe: isMe,
                    roomId: widget.roomId,
                    canHideMessage: canHideMessage,
                    showDragHandle: false,
                    onHide: () => _hideMessage(messageId),
                    onEdit: () =>
                        _editMessage(messageId, data['text'] as String? ?? ''),
                    onDelete: () => _deleteMessage(messageId),
                    onReply: () => setState(() {
                      _replyToId = messageId;
                      _replyToData = data;
                      _showAttachPanel = false;
                    }),
                    onPin: () => _pinMessage(data, messageId),
                    onMemo: () => _showChatMemoSheet(context, data, messageId),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _hideMessage(String messageId) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.hideMessage),
        content: Text(l.hideMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.hideMessage),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<ChatService>().hideMessage(
        widget.roomId,
        messageId,
        hiddenBy: _currentUserId,
        replacementLastMessage: l.messageHidden,
      );
    } catch (e) {
      debugPrint('Failed to hide message: $e');
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteMessage),
        content: Text(l.deleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l.deleteMessage),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<ChatService>().softDeleteMessage(
        widget.roomId,
        messageId,
        replacementLastMessage: l.messageDeleted,
      );
    } catch (e) {
      debugPrint('Failed to delete message: $e');
    }
  }

  Future<void> _editMessage(String messageId, String oldText) async {
    final l = AppLocalizations.of(context);
    final textController = TextEditingController(text: oldText);

    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editMessageTitle),
        content: TextField(
          controller: textController,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textController.text.trim()),
            child: Text(l.edit),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || newText == oldText) return;

    try {
      await context.read<ChatService>().editTextMessage(
        widget.roomId,
        messageId,
        newText: newText,
      );
    } catch (e) {
      debugPrint('Failed to edit message: $e');
    }
  }

  void _showChatMemoSheet(
    BuildContext context,
    Map<String, dynamic> data,
    String messageId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChatMemoSheet(
        data: data,
        messageId: messageId,
        groupId: _roomMeta?.refGroupId ?? '',
        groupName: _roomMeta?.groupName ?? '',
        roomId: widget.roomId,
        roomName: _roomMeta?.roomName ?? '',
      ),
    );
  }

  Future<void> _showScheduledMessageSheet({
    String initialText = '',
    bool clearComposerOnSuccess = false,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final scheduled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChatScheduledMessageSheet(
        roomId: widget.roomId,
        currentUserId: _currentUserId,
        senderName: _myName,
        initialText: initialText,
      ),
    );
    if (scheduled == true && clearComposerOnSuccess && mounted) {
      _msgController.clear();
      _clearMessageDraft();
      setState(() {
        _replyToId = null;
        _replyToData = null;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 드롭다운 메뉴
  // ──────────────────────────────────────────────────────────────────────────

  void _showDropdownMenu(BuildContext context, AppLocalizations l) async {
    final colorScheme = Theme.of(context).colorScheme;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
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
          child: Row(
            children: [
              Icon(Icons.people_outline, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Text(l.participants),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'invite',
          child: Row(
            children: [
              Icon(
                Icons.person_add_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(l.inviteMembers),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'notices',
          child: Row(
            children: [
              Icon(
                Icons.campaign_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(l.noticeHistory),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'shared_assets',
          child: Row(
            children: [
              Icon(
                Icons.collections_bookmark_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(l.sharedVault),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(
                _isMuted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
                color: colorScheme.onSurface.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(_isMuted ? l.chatUnmuteAction : l.chatMuteAction),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.exit_to_app, color: colorScheme.error, size: 20),
              const SizedBox(width: 12),
              Text(l.leaveRoom, style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    final meta = _roomMeta;
    switch (result) {
      case 'participants':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomParticipantsScreen(
              roomId: widget.roomId,
              roomType: meta?.roomType ?? '',
              currentUserId: _currentUserId,
              myRole: meta?.myRole ?? 'member',
            ),
          ),
        );
        return;
      case 'invite':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomInviteScreen(
              roomId: widget.roomId,
              currentUserId: _currentUserId,
              refGroupId: meta?.refGroupId,
            ),
          ),
        );
        return;
      case 'notices':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoticesScreen(roomId: widget.roomId),
          ),
        );
        return;
      case 'shared_assets':
        final selectedMessageId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ChatRoomSharedAssetsScreen(
              roomId: widget.roomId,
              refGroupId: meta?.refGroupId,
            ),
          ),
        );
        if (!mounted) return;
        if (selectedMessageId != null && selectedMessageId.isNotEmpty) {
          _scrollToMessage(selectedMessageId);
        }
        return;
      case 'mute':
        await _toggleMute();
        return;
      case 'leave':
        _leaveRoom(l);
        return;
      case null:
        return;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 헬퍼
  // ──────────────────────────────────────────────────────────────────────────

  int _calculateUnread(
    Timestamp? createdAt,
    List<QueryDocumentSnapshot> members,
  ) {
    if (createdAt == null) return 0;
    int unread = 0;
    for (final member in members) {
      if (member.id == _currentUserId) continue;
      final data = member.data() as Map<String, dynamic>;
      final Timestamp? lastRead = data['last_read_time'];
      if (lastRead == null || lastRead.compareTo(createdAt) < 0) unread++;
    }
    return unread;
  }

  bool _needsDateDivider(List<QueryDocumentSnapshot> messages, int index) {
    final current =
        (messages[index].data() as Map<String, dynamic>)['created_at']
            as Timestamp?;
    if (current == null) return false;
    if (index == messages.length - 1) return true;
    final prev =
        (messages[index + 1].data() as Map<String, dynamic>)['created_at']
            as Timestamp?;
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

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final meta = _roomMeta;
    final isDm = meta?.roomType == 'direct';
    final dmDisplayName = (meta?.otherUserDeleted ?? false)
        ? l.deletedUser
        : meta?.otherUserName ?? '';
    final appBarTitle = isDm && dmDisplayName.isNotEmpty
        ? dmDisplayName
        : (meta?.roomName ?? '');
    final otherUserPhoto = meta?.otherUserPhoto ?? '';
    final hasOtherPhoto =
        otherUserPhoto.isNotEmpty && !(meta?.otherUserDeleted ?? false);
    final isDesktopPanel = widget.isDesktopMode && widget.onClosePanel != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: !isDesktopPanel,
        leading: isDm
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: GestureDetector(
                  onTap: (meta?.otherUserUid.isNotEmpty ?? false)
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => UserProfileDetailScreen(
                              uid: meta!.otherUserUid,
                              displayName: dmDisplayName,
                              photoUrl: meta.otherUserPhoto,
                            ),
                          ),
                        )
                      : null,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.tertiaryContainer,
                    backgroundImage: hasOtherPhoto
                        ? CachedNetworkImageProvider(otherUserPhoto)
                        : null,
                    onBackgroundImageError: hasOtherPhoto ? (_, __) {} : null,
                    child: hasOtherPhoto
                        ? null
                        : (meta?.otherUserDeleted ?? false)
                        ? Icon(
                            Icons.person_off_outlined,
                            size: 16,
                            color: colorScheme.onTertiaryContainer,
                          )
                        : (dmDisplayName.isNotEmpty
                              ? Text(
                                  dmDisplayName[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                )
                              : Icon(
                                  Icons.person,
                                  size: 16,
                                  color: colorScheme.onTertiaryContainer,
                                )),
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
                    fontSize: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
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
                  if (_metaLoading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary.withOpacity(0.5),
                      ),
                    )
                  else
                    Text(appBarTitle.isNotEmpty ? appBarTitle : 'Chat Room'),
                  if (_isMuted) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ],
                ],
              ),
        titleSpacing: _isSearching ? 0 : null,
        actions: [
          ..._buildAppBarActions(l, colorScheme),
          if (isDesktopPanel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClosePanel,
                tooltip: l.close,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildNoticeBanner(colorScheme),
          if (_isSearching && _searchLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: colorScheme.surface,
              color: colorScheme.primary,
            ),
          if (_uploadingMedia)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: colorScheme.surface,
              color: colorScheme.primary,
            ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildMessageList(l, colorScheme),

                // 맨 아래로 가기 버튼
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      onPressed: _jumpToBottom,
                      backgroundColor: colorScheme.surface.withOpacity(0.9),
                      elevation: 2,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),

                // 새 메시지 미리보기 배너
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: 16,
                  // 스크롤 버튼과 겹치지 않도록 right에 여유
                  right: _showScrollToBottom ? 60 : 16,
                  bottom: _newMessagePreviewText != null ? 16 : -80,
                  child: AnimatedOpacity(
                    opacity: _newMessagePreviewText != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: _newMessagePreviewText != null
                        ? _buildNewMessageBanner(colorScheme)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          if (!_isSearching) _buildMessageInput(colorScheme, l),
          if (_showAttachPanel && !_isSearching)
            _buildAttachPanel(colorScheme, l),
        ],
      ),
    );
  }

  /// 새 메시지 미리보기 배너 위젯
  Widget _buildNewMessageBanner(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _jumpToBottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface.withOpacity(0.88),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.keyboard_arrow_down,
              color: colorScheme.onInverseSurface,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_newMessagePreviewSender?.isNotEmpty ?? false)
                    Text(
                      _newMessagePreviewSender!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onInverseSurface.withOpacity(0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _newMessagePreviewText ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onInverseSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(
    AppLocalizations l,
    ColorScheme colorScheme,
  ) {
    if (_isSearching) {
      return [
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_searchResults.isNotEmpty) ...[
          Center(
            child: Text(
              '${_searchIndex + 1}/${_searchResults.length}',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
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
              child: Text(
                l.noSearchResults,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
          ),
        IconButton(icon: const Icon(Icons.close), onPressed: _toggleSearch),
      ];
    }
    return [
      IconButton(icon: const Icon(Icons.search), onPressed: _toggleSearch),
      Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showDropdownMenu(ctx, l),
        ),
      ),
    ];
  }

  Widget _buildNoticeBanner(ColorScheme colorScheme) {
    final pinned = _roomMeta?.pinnedMessage;
    if (pinned == null) return const SizedBox.shrink();
    if (!_noticeBannerDismissed) {
      return NoticeBanner(
        text: pinned['text'] as String? ?? '',
        onDismiss: () => setState(() => _noticeBannerDismissed = true),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoticesScreen(roomId: widget.roomId),
          ),
        ),
        colorScheme: colorScheme,
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 2),
        child: GestureDetector(
          onTap: () => setState(() => _noticeBannerDismissed = false),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.campaign_outlined,
              size: 18,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(AppLocalizations l, ColorScheme colorScheme) {
    if (_displayingRoomId != widget.roomId) {
      return const Center(child: CircularProgressIndicator());
    }

    final chatProvider = context.read<ChatProvider>();
    final cachedMembers = chatProvider.getCachedMembers(widget.roomId);
    final cachedMessages = chatProvider.getCachedMessages(widget.roomId);

    return StreamBuilder<Set<String>>(
      stream: context.read<BlockService>().getBlockedUidSet(),
      builder: (context, blockedSnap) {
        final blockedUids = blockedSnap.data ?? {};
        return StreamBuilder<QuerySnapshot>(
          stream: _membersStream,
          builder: (context, membersSnap) {
            final members = membersSnap.data?.docs ?? cachedMembers;
            return StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, messagesSnap) {
                if (messagesSnap.connectionState == ConnectionState.waiting &&
                    messagesSnap.data == null &&
                    cachedMessages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = messagesSnap.data?.docs ?? cachedMessages;

                // ── _lastStreamDoc 업데이트 & 새 메시지 배너 감지 ──────────────
                if (messages.isNotEmpty) {
                  final isNewMessage =
                      _lastStreamDoc != null &&
                      _lastStreamDoc!.id != messages.last.id;

                  // _lastStreamDoc 갱신
                  if (_lastStreamDoc?.id != messages.last.id) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _lastStreamDoc = messages.last);
                      }
                    });
                  }

                  // 새 메시지 배너: 위에서 보고 있을 때 + 타인 메시지일 때만
                  if (isNewMessage && _showScrollToBottom) {
                    final latestData =
                        messages.first.data() as Map<String, dynamic>;
                    final isSystem = latestData['is_system'] as bool? ?? false;
                    final senderId = latestData['sender_id'] as String? ?? '';

                    if (!isSystem && senderId != _currentUserId) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _showPreviewBanner(latestData, l);
                      });
                    }
                  }
                }
                // ─────────────────────────────────────────────────────────────

                final streamIds = messages.map((d) => d.id).toSet();
                final uniqueOlder = _olderMessages
                    .where((d) => !streamIds.contains(d.id))
                    .toList();
                final allMessages = [...messages, ...uniqueOlder].where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final senderId = data['sender_id'] as String? ?? '';
                  final isSystem = data['is_system'] as bool? ?? false;
                  return isSystem || !blockedUids.contains(senderId);
                }).toList();

                final senderIds = allMessages
                    .expand((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return [
                        data['sender_id'] as String? ?? '',
                        data['shared_user_id'] as String? ?? '',
                      ];
                    })
                    .where((uid) => uid.isNotEmpty)
                    .toSet();
                if (senderIds.isNotEmpty) {
                  UserCache.prefetch(senderIds);
                }

                if (allMessages.isEmpty && _uploadingMessages.isEmpty) {
                  return Center(
                    child: Text(
                      l.noMessages,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  );
                }

                final uploadingList = _uploadingMessages.values.toList();
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  cacheExtent: 3000,
                  itemCount:
                      uploadingList.length +
                      allMessages.length +
                      (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < uploadingList.length) {
                      final msg =
                          uploadingList[uploadingList.length - 1 - index];
                      return _buildUploadingBubble(msg, colorScheme, l);
                    }
                    final adjustedIndex = index - uploadingList.length;
                    if (adjustedIndex == allMessages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary.withOpacity(0.5),
                            ),
                          ),
                        ),
                      );
                    }
                    return _buildMessageItem(
                      context,
                      allMessages,
                      adjustedIndex,
                      members,
                      colorScheme,
                      l,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    List<QueryDocumentSnapshot> allMessages,
    int index,
    List<QueryDocumentSnapshot> members,
    ColorScheme colorScheme,
    AppLocalizations l,
  ) {
    final data = allMessages[index].data() as Map<String, dynamic>;
    final msgId = allMessages[index].id;
    final isSystem = data['is_system'] as bool? ?? false;
    final needsDate = _needsDateDivider(allMessages, index);
    final isContinuous = _isContinuous(allMessages, index);
    final senderId = data['sender_id'] as String? ?? '';
    final storedPhoto = data['sender_photo_url'] as String? ?? '';
    final senderProfile = UserDisplay.resolveCached(
      senderId,
      fallbackName: data['sender_name'] as String? ?? '',
      fallbackPhotoUrl: storedPhoto,
    );
    final resolvedPhoto = senderProfile?.isDeleted == true
        ? ''
        : (senderProfile?.photoUrl ?? storedPhoto);
    final resolvedSenderName =
        (senderProfile ??
                UserDisplay.fromStored(
                  uid: senderId,
                  name: data['sender_name'] as String? ?? '',
                  photoUrl: storedPhoto,
                ))
            .displayName(l, fallback: data['sender_name'] as String? ?? '');
    final resolvedData = {
      ...data,
      'sender_name': resolvedSenderName,
      'sender_photo_url': resolvedPhoto,
      'sender_is_deleted': senderProfile?.isDeleted == true,
    };

    _messageKeys.putIfAbsent(msgId, () => GlobalKey());

    return Column(
      key: _messageKeys[msgId],
      children: [
        if (needsDate)
          DateDivider(
            date: (data['created_at'] as Timestamp).toDate(),
            colorScheme: colorScheme,
          ),
        if (isSystem && data['type'] != 'poll')
          SystemMessage(
            text: data['is_hidden'] == true
                ? AppLocalizations.of(context).messageHidden
                : data['text'] ?? '',
            colorScheme: colorScheme,
          )
        else if (data['type'] == 'poll')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: PollBubble(
              roomId: widget.roomId,
              pollId: data['poll_id'] as String,
              colorScheme: colorScheme,
              refGroupId: _roomMeta?.refGroupId,
            ),
          )
        else if (storedPhoto.isNotEmpty)
          _buildBubble(
            context: context,
            data: data['is_deleted'] == true
                ? {...resolvedData, 'text': l.messageDeleted, 'type': 'text'}
                : resolvedData,
            msgId: msgId,
            photoUrl: resolvedPhoto,
            isContinuous: isContinuous,
            members: members,
            colorScheme: colorScheme,
            l: l,
          )
        else
          _buildBubble(
            context: context,
            data: data['is_deleted'] == true
                ? {...resolvedData, 'text': l.messageDeleted, 'type': 'text'}
                : resolvedData,
            msgId: msgId,
            photoUrl: resolvedPhoto,
            isContinuous: isContinuous,
            members: members,
            colorScheme: colorScheme,
            l: l,
          ),
      ],
    );
  }

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
    final isDesktopLayout = MediaQuery.sizeOf(context).width > 700;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: isDesktopLayout
          ? () => _showMessageOptions(context, data, msgId)
          : null,
      onLongPress: isDesktopLayout
          ? null
          : () => _showMessageOptions(context, data, msgId),
      child: MessageBubble(
        data: {...data, 'sender_photo_url': photoUrl},
        isMe: data['sender_id'] == _currentUserId,
        isContinuous: isContinuous,
        unreadCount: _calculateUnread(
          data['created_at'] as Timestamp?,
          members,
        ),
        colorScheme: colorScheme,
        isHighlighted: msgId == _highlightMessageId,
        searchQuery: _isSearching ? _searchQuery : '',
        onAvatarTap:
            data['sender_id'] != null && data['sender_id'] != _currentUserId
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileDetailScreen(
                    uid: data['sender_id'] as String,
                    photoUrl: photoUrl,
                    displayName: data['sender_name'] as String? ?? '',
                  ),
                ),
              )
            : null,
        onReplyTap: data['reply_to_id'] != null
            ? () => _scrollToMessage(data['reply_to_id'] as String)
            : null,
      ),
    );
  }

  Widget _buildUploadingBubble(
    _UploadingMessage msg,
    ColorScheme colorScheme,
    AppLocalizations l,
  ) {
    Widget content;
    if (msg.type == 'image') {
      content = msg.imageFiles.length == 1
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                msg.imageFiles[0],
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            )
          : SizedBox(
              width: 200,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            Image.file(
              msg.thumbnailFile!,
              width: 200,
              height: 150,
              fit: BoxFit.cover,
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ],
        ),
      );
    } else if (msg.type == 'file') {
      content = Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              color: colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.fileName ?? l.attachFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((msg.fileSize ?? 0) > 0)
                    Text(
                      _formatFileSize(msg.fileSize!),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (msg.type == 'audio') {
      content = Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mic_none_rounded, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.attachVoice,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatAudioDuration(msg.audioDurationMs ?? 0),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
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
              msg.failed ? l.uploadFailed : l.uploadingMessage,
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
                          ? const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 32,
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
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
                    color: colorScheme.onSurface.withOpacity(0.08),
                  ),
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
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyToData!['text'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.onSurface.withOpacity(0.08)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: AnimatedRotation(
                    turns: _showAttachPanel ? 0.125 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.add,
                      color: _showAttachPanel
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: _toggleAttachPanel,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (_msgController.text.trim().isNotEmpty) {
                          _sendMessage();
                        }
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): () {
                        final text = _msgController.text;
                        final selection = _msgController.selection;
                        final newText = text.replaceRange(
                          selection.start,
                          selection.end,
                          '\n',
                        );
                        _msgController.value = _msgController.value.copyWith(
                          text: newText,
                          selection: TextSelection.collapsed(
                            offset: selection.start + 1,
                          ),
                        );
                      },
                    },
                    child: TextField(
                      controller: _msgController,
                      focusNode: _focusNode,
                      onTap: () {
                        if (_showAttachPanel) {
                          setState(() => _showAttachPanel = false);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: l.typeMessage,
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4),
                          fontSize: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: colorScheme.primary),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: _sendMessage,
                  onLongPress: () => _showScheduledMessageSheet(
                    initialText: _msgController.text.trim(),
                    clearComposerOnSuccess: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAttachPanel() {
    setState(() => _showAttachPanel = !_showAttachPanel);
    if (_showAttachPanel) FocusScope.of(context).unfocus();
  }

  Widget _buildAttachPanel(ColorScheme colorScheme, AppLocalizations l) {
    final items = [
      AttachItem(
        icon: Icons.photo_outlined,
        label: l.attachPhotos,
        color: Colors.green,
        onTap: _sendImages,
      ),
      AttachItem(
        icon: Icons.videocam_outlined,
        label: l.attachVideos,
        color: Colors.red,
        onTap: _sendVideo,
      ),
      AttachItem(
        icon: Icons.mic_outlined,
        label: l.attachVoice,
        color: Colors.orange,
        onTap: _sendVoiceMessage,
      ),
      AttachItem(
        icon: Icons.call_outlined,
        label: l.attachCall,
        color: Colors.blue,
        onTap: () {},
      ),
      AttachItem(
        icon: Icons.videocam,
        label: l.attachVideoCall,
        color: Colors.purple,
        onTap: () {},
      ),
      AttachItem(
        icon: Icons.auto_awesome_outlined,
        label: l.attachAiMinutes,
        color: Colors.teal,
        onTap: () {},
      ),
      AttachItem(
        icon: Icons.share_location_outlined,
        label: l.attachLocation,
        color: Colors.cyan,
        onTap: () async {
          setState(() => _showAttachPanel = false);
          final result = await showModalBottomSheet<LocationShareResult>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => LocationShareSheet(),
          );
          if (result != null && mounted) {
            await _sendLocationMessage(result, l);
          }
        },
      ),
      AttachItem(
        icon: Icons.insert_drive_file_outlined,
        label: l.attachFile,
        color: Colors.brown,
        onTap: _sendFiles,
      ),
      AttachItem(
        icon: Icons.contacts_outlined,
        label: l.attachContact,
        color: Colors.indigo,
        onTap: () async {
          setState(() => _showAttachPanel = false);
          final result = await showModalBottomSheet<ContactShareResult>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => ContactShareSheet(
              shareButtonColor: Colors.white,
              shareButtonForegroundColor: Colors.black,
            ),
          );
          if (result != null && mounted) {
            await _sendContactMessage(result);
          }
        },
      ),
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreatePollScreen(roomId: widget.roomId),
            ),
          );
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
              .map((item) => AttachButton(item: item, colorScheme: colorScheme))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _sendLocationMessage(
    LocationShareResult result,
    AppLocalizations l,
  ) async {
    await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .collection('messages')
        .add({
          'type': 'location',
          'location_lat': result.lat,
          'location_lng': result.lng,
          'location_type': result.type,
          'location_name': result.name,
          'location_address': result.address,
          'sender_id': _currentUserId,
          'sender_name': _myName,
          'created_at': FieldValue.serverTimestamp(),
        });
    await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.roomId)
        .update({
          'last_message': result.type,
          'last_time': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _sendContactMessage(ContactShareResult result) async {
    final chatService = context.read<ChatService>();
    final userProvider = context.read<UserProvider>();
    await chatService.sendContactMessage(
      widget.roomId,
      sharedUserId: result.uid,
      sharedUserName: result.displayName,
      sharedUserPhotoUrl: result.photoUrl,
      senderName: _myName,
      senderPhotoUrl: userProvider.photoUrl,
    );
    chatService.updateLastReadTime(widget.roomId);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatAudioDuration(int durationMs) {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ── 업로딩 메시지 모델 ─────────────────────────────────────────────────────────
class _UploadingMessage {
  final String messageId;
  final String type;
  final List<File> imageFiles;
  final File? thumbnailFile;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? audioDurationMs;
  final String senderName;
  final String senderPhotoUrl;
  final DateTime createdAt;
  bool failed;

  _UploadingMessage({
    required this.messageId,
    required this.type,
    this.imageFiles = const [],
    this.thumbnailFile,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.audioDurationMs,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.createdAt,
    this.failed = false,
  });
}
