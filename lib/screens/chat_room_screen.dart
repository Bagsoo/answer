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

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String? initialScrollToMessageId;
  const ChatRoomScreen({super.key, required this.roomId, this.initialScrollToMessageId});

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
  int _searchIndex = 0; // 현재 포커스된 검색 결과 인덱스

  String? _refGroupId;
  String? _roomType;
  String _myRole = 'member';
  String _roomName = '';
  String _groupName = '';
  String _myName = '';
  bool _isMuted = false;

  // 메모에서 이동 시 하이라이트할 메시지 ID
  String? _highlightMessageId;

  // 첨부 패널 표시 여부
  bool _showAttachPanel = false;

  // 답장 대상 메시지
  Map<String, dynamic>? _replyToData;
  String? _replyToId;

  // 공지
  Map<String, dynamic>? _pinnedMessage;
  bool _noticeBannerDismissed = false;

  // 페이지네이션
  final List<QueryDocumentSnapshot> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 30;
  QueryDocumentSnapshot? _lastStreamDoc; // Stream의 가장 오래된 doc

  // 메시지 스크롤 타깃용 GlobalKey 맵
  final Map<String, GlobalKey> _messageKeys = {};

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
      // 빌드 후 하이라이트 메시지 찾아서 스크롤 (스트림 로드 후)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() {}); // 하이라이트 표시를 위해 rebuild
        });
      });
    }
  }

  void _onScroll() {
    // reverse: true 이므로 maxScrollExtent 근처 = 스크롤 상단 (오래된 메시지 방향)
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMore) return;

    // stream의 현재 마지막 doc이 필요 — _lastStreamDoc에 저장
    if (_lastStreamDoc == null) return;

    setState(() => _loadingMore = true);

    final chatService = context.read<ChatService>();
    final baseDoc = _olderMessages.isNotEmpty ? _olderMessages.last : _lastStreamDoc!;

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
    final muted = await context.read<NotificationService>().getChatRoomMuted(widget.roomId);
    if (mounted) setState(() => _isMuted = muted);
  }

  Future<void> _toggleMute() async {
    final newVal = !_isMuted;
    setState(() => _isMuted = newVal);
    await context.read<NotificationService>().setChatRoomMuted(widget.roomId, newVal);
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newVal ? l.chatMuted : l.chatUnmuted)),
      );
    }
  }

  // ── 공지 등록 ──────────────────────────────────────────────────────────────
  Future<void> _pinMessage(Map<String, dynamic> data, String messageId) async {
    final l = AppLocalizations.of(context);
    // sender_name은 메시지에 이미 저장되어 있음 (Firestore 추가 조회 불필요)
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

    // 채팅방 pinned_message 업데이트
    batch.update(roomRef, {'pinned_message': pinData});

    // notices 히스토리에 추가
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.noticePinned)),
      );
    }
  }

  // ── 메시지 롱프레스 바텀시트 ───────────────────────────────────────────────
  // ── 답장 메시지로 스크롤 ──────────────────────────────────────────────────
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

  // 과거 메시지가 렌더링될 때까지 페이지 로드 반복 후 스크롤
  Future<void> _loadUntilMessageVisible(String messageId) async {
    const maxAttempts = 20;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final key = _messageKeys[messageId];

      // key도 있고 context도 살아있으면 바로 스크롤
      if (key?.currentContext != null) {
        _doScrollToMessage(messageId, key!);
        return;
      }

      // key는 등록됐지만 context가 null → 화면 밖(dispose)
      // scrollController로 해당 방향으로 점프해서 cacheExtent 안으로 끌어들임
      if (_messageKeys.containsKey(messageId)) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        // 다음 프레임 후 재시도
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;

        // 점프 후 context 살아났는지 확인
        final k = _messageKeys[messageId];
        if (k?.currentContext != null) {
          _doScrollToMessage(messageId, k!);
          return;
        }
        // 아직도 null이면 postFrameCallback으로 한 번 더
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final k2 = _messageKeys[messageId];
          if (k2?.currentContext != null) _doScrollToMessage(messageId, k2!);
        });
        return;
      }

      // key 자체가 없음 → 아직 로드 안 된 페이지
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
            // 핸들
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 메시지 미리보기
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
            // 답장하기
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
                FocusScope.of(context).requestFocus(FocusNode());
                Future.delayed(const Duration(milliseconds: 100), () {
                  FocusScope.of(context).unfocus();
                });
              },
            ),
            // 공지로 등록
            ListTile(
              leading: Icon(Icons.campaign_outlined, color: colorScheme.primary),
              title: Text(l.pinAsNotice),
              onTap: () {
                Navigator.pop(ctx);
                _pinMessage(data, messageId);
              },
            ),
            // 복사
            ListTile(
              leading: Icon(Icons.copy_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.copyMessage),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.messageCopied)),
                );
              },
            ),
            // 메모
            ListTile(
              leading: Icon(Icons.note_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.memoMessage),
              onTap: () {
                Navigator.pop(ctx);
                _showChatMemoSheet(context, data, messageId, l, colorScheme);
              },
            ),
            // 공유
            ListTile(
              leading: Icon(Icons.share_outlined,
                  color: colorScheme.onSurface.withOpacity(0.7)),
              title: Text(l.shareMessage),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(text);
              },
            ),
            // 신고 (내 메시지 제외)
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
        ), // SingleChildScrollView
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
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
              // 출처 표시
              Text(
                '$_groupName › $_roomName · $senderName',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.primary),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final content = controller.text.trim();
                  if (content.isEmpty) return;
                  await context.read<MemoService>().memoFromChat(
                    content: content,
                    groupId: _refGroupId ?? '',
                    groupName: _groupName,
                    roomId: widget.roomId,
                    roomName: _roomName,
                    messageId: messageId,
                    senderName: senderName,
                    originalSentAt: sentAt ?? Timestamp.now(),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.memoSaved)),
                    );
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

  // ── 채팅방 메타 로드 ────────────────────────────────────────────────────────
  Future<void> _loadRoomMeta() async {
    final db = FirebaseFirestore.instance;

    // UserProvider에서 이름 가져오기 (Firestore 조회 불필요)
    _myName = context.read<UserProvider>().name;

    final results = await Future.wait([
      db.collection('chat_rooms').doc(widget.roomId).get(),
      db.collection('chat_rooms').doc(widget.roomId)
          .collection('room_members').doc(currentUserId).get(),
    ]);

    final roomDoc = results[0];
    final memberDoc = results[1];

    if (mounted) {
      setState(() {
        _refGroupId = roomDoc.data()?['ref_group_id'] as String?;
        _roomType = roomDoc.data()?['type'] as String?;
        _myRole = memberDoc.data()?['role'] as String? ?? 'member';
        _roomName = roomDoc.data()?['name'] as String? ?? '';
        _groupName = roomDoc.data()?['group_name'] as String? ?? '';
        _pinnedMessage = roomDoc.data()?['pinned_message'] as Map<String, dynamic>?;
      });
    }
  }

  // ── 메시지 전송 ────────────────────────────────────────────────────────────
  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    // 그룹 채팅방이면 그룹 ban 체크
    if (_refGroupId != null) {
      final isBanned = await context.read<BlockService>().isGroupBanned(_refGroupId!);
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

    // 답장 정보 캡처 후 초기화
    final replyId = _replyToId;
    final replyData = _replyToData;
    if (mounted) setState(() { _replyToId = null; _replyToData = null; });

    final chatService = context.read<ChatService>();
    await chatService.sendMessage(
      widget.roomId,
      text,
      senderName: _myName,
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

  // ── 예약 메시지 전송 체크 (채팅방 진입 시) ────────────────────────────────
  Future<void> _checkAndSendScheduledMessages() async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();

    final snap = await db
        .collection('chat_rooms').doc(widget.roomId)
        .collection('scheduled_messages')
        .where('scheduled_at', isLessThanOrEqualTo: now)
        .where('sent', isEqualTo: false)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final text = data['text'] as String? ?? '';
      final senderName = data['sender_name'] as String? ?? _myName;
      final senderId = data['sender_id'] as String? ?? currentUserId;

      // 메시지 전송
      await db.collection('chat_rooms').doc(widget.roomId)
          .collection('messages').add({
        'text': text,
        'sender_id': senderId,
        'sender_name': senderName,
        'type': 'text',
        'is_system': false,
        'created_at': FieldValue.serverTimestamp(),
      });

      // sent 처리
      await doc.reference.update({'sent': true});
    }

    // last_message 업데이트 (마지막 것만)
    if (snap.docs.isNotEmpty) {
      final lastText = snap.docs.last.data()['text'] as String? ?? '';
      await db.collection('chat_rooms').doc(widget.roomId).update({
        'last_message': lastText,
        'last_time': FieldValue.serverTimestamp(),
      });
    }
  }

  // ── 예약 메시지 시트 ──────────────────────────────────────────────────────
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
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 핸들
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  Icon(Icons.schedule_send_outlined, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('예약 메시지',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                // 메시지 입력
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  decoration: InputDecoration(
                    hintText: '메시지를 입력하세요',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 12),
                // 날짜/시간 선택
                OutlinedButton.icon(
                  onPressed: () async {
                    // 기기 로컬 시간 기준으로 '지금'을 한 번만 캡처
                    // Firestore 서버 시간 조회 (기기 시간 무관)
                    final serverNow = await _fetchServerTime();
                    final today = DateTime(serverNow.year, serverNow.month, serverNow.day);
                    final safeFirst = today.subtract(const Duration(days: 1));

                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: today,
                      firstDate: safeFirst,
                      lastDate: today.add(const Duration(days: 30)),
                      currentDate: today,
                      selectableDayPredicate: (day) =>
                          !day.isBefore(today), // 오늘 이전 선택 불가
                    );
                    if (date == null || !ctx.mounted) return;

                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;

                    final picked = DateTime(
                      date.year, date.month, date.day, time.hour, time.minute,
                    );

                    // 과거 시간 체크도 서버 시간 기준
                    final serverNowCheck = await _fetchServerTime();
                    if (picked.isBefore(serverNowCheck.add(const Duration(minutes: 1)))) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('현재 시간보다 최소 1분 이후로 설정해주세요')),
                        );
                      }
                      return;
                    }

                    setSheet(() => selectedDateTime = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    selectedDateTime != null
                        ? '${selectedDateTime!.year}.${selectedDateTime!.month.toString().padLeft(2,'0')}.${selectedDateTime!.day.toString().padLeft(2,'0')} '
                          '${selectedDateTime!.hour.toString().padLeft(2,'0')}:${selectedDateTime!.minute.toString().padLeft(2,'0')}'
                        : '전송 시간 선택',
                  ),
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
                        const SnackBar(content: Text('메시지를 입력해주세요')),
                      );
                      return;
                    }
                    if (selectedDateTime == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('전송 시간을 선택해주세요')),
                      );
                      return;
                    }

                    // selectedDateTime은 기기 로컬 시간 기준
                    // Timestamp.fromDate()가 UTC로 변환해서 저장 → 나라마다 정확하게 동작
                    await FirebaseFirestore.instance
                        .collection('chat_rooms').doc(widget.roomId)
                        .collection('scheduled_messages').add({
                      'text': text,
                      'sender_id': currentUserId,
                      'sender_name': _myName,
                      'scheduled_at': Timestamp.fromDate(selectedDateTime!),
                      'sent': false,
                      'created_at': FieldValue.serverTimestamp(),
                    });

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${selectedDateTime!.month}/${selectedDateTime!.day} '
                            '${selectedDateTime!.hour.toString().padLeft(2,'0')}:'
                            '${selectedDateTime!.minute.toString().padLeft(2,'0')} 에 전송 예약됨',
                          ),
                        ),
                      );
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

  // ── Firestore 서버 시간 조회 ─────────────────────────────────────────────
  // 임시 doc에 serverTimestamp를 쓰고 바로 읽어서 서버 현재 시간을 로컬로 가져옴
  Future<DateTime> _fetchServerTime() async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('_server_time').doc('ping');
    await ref.set({'t': FieldValue.serverTimestamp()});
    final snap = await ref.get();
    final ts = snap.data()?['t'] as Timestamp?;
    // Timestamp.toDate()는 로컬 시간대로 변환해줌 (KST면 KST로)
    return ts?.toDate() ?? DateTime.now();
  }

  // ── 첨부 패널 토글 ────────────────────────────────────────────────────────
  void _toggleAttachPanel() {
    setState(() => _showAttachPanel = !_showAttachPanel);
    if (_showAttachPanel) FocusScope.of(context).unfocus();
  }

  // ── 메시지 검색 ────────────────────────────────────────────────────────────
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
      setState(() { _searchResults = []; _searchLoading = false; _searchIndex = 0; _highlightMessageId = null; });
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

    // 첫 번째 결과로 바로 이동
    if (results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMessage(results[0].id);
      });
    }
  }

  // 검색 결과 위아래 이동
  void _searchNavigate(int delta) {
    if (_searchResults.isEmpty) return;
    final next = (_searchIndex + delta).clamp(0, _searchResults.length - 1);
    if (next == _searchIndex) return;
    setState(() => _searchIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessage(_searchResults[next].id);
    });
  }

  // ── 채팅방 나가기 ──────────────────────────────────────────────────────────
  Future<void> _leaveRoom(AppLocalizations l) async {
    if (_myRole == 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.ownerCannotLeave)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.leaveRoom),
        content: Text(l.leaveRoomConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
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
        .collection('chat_rooms').doc(widget.roomId);

    batch.update(roomRef, {
      'member_ids': FieldValue.arrayRemove([currentUserId]),
    });
    batch.delete(roomRef.collection('room_members').doc(currentUserId));

    final myName = _myName.isNotEmpty ? _myName : currentUserId.substring(0, 6);
    batch.set(roomRef.collection('messages').doc(), {
      'is_system': true,
      'text': '$myName님이 나갔습니다.',
      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    if (mounted) Navigator.pop(context);
  }

  // ── 드롭다운 메뉴 ──────────────────────────────────────────────────────────
  void _showDropdownMenu(BuildContext context, AppLocalizations l) async {
    final colorScheme = Theme.of(context).colorScheme;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
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
            Text(l.viewParticipants),
          ]),
        ),
        PopupMenuItem(
          value: 'invite',
          child: Row(children: [
            Icon(Icons.person_add_outlined, color: colorScheme.primary, size: 20),
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
              _isMuted ? Icons.notifications_outlined : Icons.notifications_off_outlined,
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

  // ── unread 계산 ────────────────────────────────────────────────────────────
  // message.created_at > member.last_read_time 이면 unread
  int _calculateUnread(Timestamp? createdAt, List<QueryDocumentSnapshot> members) {
    if (createdAt == null) return 0;
    int unread = 0;
    for (final member in members) {
      if (member.id == currentUserId) continue;
      final data = member.data() as Map<String, dynamic>;
      final Timestamp? lastRead = data['last_read_time'];
      if (lastRead == null || lastRead.compareTo(createdAt) < 0) {
        unread++;
      }
    }
    return unread;
  }

  // ── 날짜 구분선 필요 여부 ────────────────────────────────────────────────────
  // reverse: true 이므로 index 0이 최신 → 이전 메시지(index+1)와 날짜 비교
  bool _needsDateDivider(List<QueryDocumentSnapshot> messages, int index) {
    final current = (messages[index].data() as Map<String, dynamic>)['created_at'] as Timestamp?;
    if (current == null) return false;
    if (index == messages.length - 1) return true; // 마지막 메시지(가장 오래된 것)

    final prev = (messages[index + 1].data() as Map<String, dynamic>)['created_at'] as Timestamp?;
    if (prev == null) return false;

    final curDate = current.toDate();
    final prevDate = prev.toDate();
    return curDate.year != prevDate.year ||
        curDate.month != prevDate.month ||
        curDate.day != prevDate.day;
  }

  // ── 연속 메시지 여부 ─────────────────────────────────────────────────────────
  // index+1 이 이전 메시지(reverse: true)
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
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
                      horizontal: 16, vertical: 8),
                  isDense: true,
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: colorScheme.onSurface.withOpacity(0.4)),
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
                  Text(_roomName.isNotEmpty ? _roomName : 'Chat Room'),
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
            // 로딩 중
            if (_searchLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            // 결과 n/m + 위아래 버튼
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
                tooltip: '이전',
                onPressed: _searchIndex < _searchResults.length - 1
                    ? () => _searchNavigate(1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: '다음',
                onPressed: _searchIndex > 0
                    ? () => _searchNavigate(-1)
                    : null,
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
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSearch,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _toggleSearch,
            ),
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
          // ── 공지 배너 / 확성기 아이콘 ─────────────────────────────────
          if (_pinnedMessage != null)
            if (!_noticeBannerDismissed)
              NoticeBanner(
                text: _pinnedMessage!['text'] as String? ?? '',
                onDismiss: () => setState(() => _noticeBannerDismissed = true),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NoticesScreen(roomId: widget.roomId),
                )),
                colorScheme: Theme.of(context).colorScheme,
              )
            else
              Align(
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
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.campaign_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),

          if (_isSearching && _searchLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: colorScheme.surface,
              color: colorScheme.primary,
            ),

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
                      if (messagesSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = messagesSnap.data?.docs ?? [];

                      // Stream의 가장 오래된 doc 기록 (페이지네이션 기준점)
                      if (messages.isNotEmpty && _lastStreamDoc?.id != messages.last.id) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _lastStreamDoc = messages.last);
                        });
                      }

                      final streamIds = messages.map((d) => d.id).toSet();
                      final uniqueOlder = _olderMessages
                          .where((d) => !streamIds.contains(d.id))
                          .toList();
                      // 차단 유저 메시지 필터링
                      final allMessages = [...messages, ...uniqueOlder]
                          .where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            final senderId = data['sender_id'] as String? ?? '';
                            final isSystem = data['is_system'] as bool? ?? false;
                            return isSystem || !blockedUids.contains(senderId);
                          }).toList();

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_olderMessages.isEmpty && messages.isNotEmpty) {}
                      });

                      if (allMessages.isEmpty) {
                        return Center(
                          child: Text(l.noMessages,
                              style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.4))),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        cacheExtent: 3000, // 화면 밖 3000px까지 위젯 유지
                        itemCount: allMessages.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // 맨 위(오래된 방향) = 로딩 인디케이터
                          if (index == allMessages.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            );
                          }

                          final data = allMessages[index].data() as Map<String, dynamic>;
                          final msgId = allMessages[index].id;
                          final isSystem = data['is_system'] as bool? ?? false;
                          final needsDate = _needsDateDivider(allMessages, index);
                          final isContinuous = _isContinuous(allMessages, index);

                          // GlobalKey 등록 (스크롤 타깃용)
                          _messageKeys.putIfAbsent(msgId, () => GlobalKey());

                          return Column(
                            key: _messageKeys[msgId],
                            children: [
                              // 날짜 구분선 — 그날의 첫 메시지 위에 표시
                              // (reverse:true 이므로 Column에서 먼저 = 화면에서 위)
                              if (needsDate)
                                DateDivider(
                                  date: (data['created_at'] as Timestamp).toDate(),
                                  colorScheme: colorScheme,
                                ),

                              // 시스템 메시지
                              if (isSystem && data['type'] != 'poll')
                                SystemMessage(
                                  text: data['text'] ?? '',
                                  colorScheme: colorScheme,
                                )
                              // 투표 버블
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
                                GestureDetector(
                                  onLongPress: () => _showMessageOptions(
                                    context,
                                    data,
                                    allMessages[index].id,
                                    l,
                                    colorScheme,
                                  ),
                                  child: MessageBubble(
                                    data: data,
                                    isMe: data['sender_id'] == currentUserId,
                                    isContinuous: isContinuous,
                                    unreadCount: _calculateUnread(
                                        data['created_at'] as Timestamp?,
                                        members),
                                    colorScheme: colorScheme,
                                    isHighlighted: allMessages[index].id == _highlightMessageId,
                                    searchQuery: _isSearching ? _searchQuery : '',
                                    onAvatarTap: data['sender_id'] != null &&
                                            data['sender_id'] != currentUserId
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => UserProfileDetailScreen(
                                                uid: data['sender_id'] as String,
                                                displayName: data['sender_name'] as String? ?? '',
                                              ),
                                            ),
                                          )
                                        : null,
                                    onReplyTap: data['reply_to_id'] != null
                                        ? () => _scrollToMessage(data['reply_to_id'] as String)
                                        : null,
                                  ),
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

  // ── 검색 결과 ──────────────────────────────────────────────────────────────
  // ── 메시지 입력 ────────────────────────────────────────────────────────────
  Widget _buildMessageInput(ColorScheme colorScheme, AppLocalizations l) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 답장 미리보기 바 ───────────────────────────────────────────────
          if (_replyToData != null)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: colorScheme.onSurface.withOpacity(0.08)),
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
                    icon: Icon(Icons.close,
                        size: 18, color: colorScheme.onSurface.withOpacity(0.5)),
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

          // ── 실제 입력 영역 ─────────────────────────────────────────────────
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.onSurface.withOpacity(0.08))),
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
                  if (_showAttachPanel) setState(() => _showAttachPanel = false);
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
              icon: Icon(Icons.send_rounded, color: colorScheme.primary),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: _sendMessage,
            ),
          ],
        ),
        ), // Container
        ], // Column
      ),
    );
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ── 첨부 패널 ─────────────────────────────────────────────────────────────
  Widget _buildAttachPanel(ColorScheme colorScheme, AppLocalizations l) {
    final items = [
      AttachItem(icon: Icons.photo_outlined,         label: l.attachPhotos,     color: Colors.green,    onTap: () {}),
      AttachItem(icon: Icons.videocam_outlined,       label: l.attachVideos,   color: Colors.red,      onTap: () {}),
      AttachItem(icon: Icons.mic_outlined,            label: l.attachVoice, color: Colors.orange,  onTap: () {}),
      AttachItem(icon: Icons.call_outlined,           label: l.attachCall,     color: Colors.blue,     onTap: () {}),
      AttachItem(icon: Icons.videocam,                label: l.attachVideoCall,  color: Colors.purple,  onTap: () {}),
      AttachItem(icon: Icons.auto_awesome_outlined,   label: l.attachAiMinutes,  color: Colors.teal,    onTap: () {}),
      AttachItem(icon: Icons.insert_drive_file_outlined, label: l.attachFile,  color: Colors.brown,   onTap: () {}),
      AttachItem(icon: Icons.contacts_outlined,       label: l.attachContact,   color: Colors.indigo,   onTap: () {}),
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
          children: items.map((item) => AttachButton(item: item, colorScheme: colorScheme)).toList(),
        ),
      ),
    );
  }
}

