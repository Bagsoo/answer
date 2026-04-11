import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/chat_service.dart';
import '../services/incoming_share_service.dart';
import '../services/memo_service.dart';
import '../l10n/app_localizations.dart';
import 'chat_list_screen.dart' hide GroupListScreen;
import 'chat_room_screen.dart';
import 'group_list_screen.dart';
import 'app_settings_screen.dart';
import 'friends_screen.dart';
import 'memo_screen.dart';
import 'profile_screen.dart';
import 'incoming_share_screen.dart';
import '../widgets/memo/memo_detail_sheet.dart';
import '../widgets/memo/memo_form_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefKeyUnread = 'chat_total_unread';

  int _currentIndex = 0;
  int _unreadCount = 0;
  StreamSubscription<int>? _unreadSub;
  bool _showingIncomingShare = false;
  IncomingShareService? _incomingShareService;
  String? _activeMemoId;
  Map<String, dynamic>? _activeMemoData;
  bool _isEditingMemo = false;
  String? _editingMemoId;
  Map<String, dynamic>? _editingMemoData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _incomingShareService ??= context.read<IncomingShareService>();
  }

  @override
  void initState() {
    super.initState();
    _loadCachedUnread();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait<void>([
        context.read<UserProvider>().loadUser(),
        context.read<LocaleProvider>().loadFromFirestore(),
        context.read<ThemeProvider>().loadFromFirestore(),
      ]);
      _subscribeUnread();
      _incomingShareService?.addListener(_handleIncomingShare);
      _handleIncomingShare();
    });
  }

  Future<void> _loadCachedUnread() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_prefKeyUnread) ?? 0;
    if (mounted) setState(() => _unreadCount = cached);
  }

  void _subscribeUnread() {
    _unreadSub = context.read<ChatService>().totalUnreadStream().listen(
      (count) async {
        if (mounted) setState(() => _unreadCount = count);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefKeyUnread, count);
      },
    );
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    _incomingShareService?.removeListener(_handleIncomingShare);
    super.dispose();
  }

  void _handleIncomingShare() {
    if (!mounted || _showingIncomingShare) return;
    final service = _incomingShareService;
    if (service == null) return;
    final payload = service.pendingShare;
    if (payload == null) return;

    _showingIncomingShare = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final handled = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => IncomingShareScreen(payload: payload),
          fullscreenDialog: true,
        ),
      );

      if (handled == true || handled == null || handled == false) {
        await service.clearPendingShare();
      }
      _showingIncomingShare = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final userProvider = context.watch<UserProvider>();
    final photoUrl = userProvider.photoUrl ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 700;

        if (isDesktop) {
          return _buildDesktopLayout(context, l, userProvider, photoUrl);
        } else {
          return _buildMobileLayout(context, l, userProvider, photoUrl);
        }
      },
    );
  }

  // ── 모바일 레이아웃 (기존과 동일) ────────────────────────────────────────────
  Widget _buildMobileLayout(BuildContext context, AppLocalizations l,
      UserProvider userProvider, String photoUrl) {
    final pages = [
      FriendsScreen(),
      const ChatListScreen(),
      const MemoScreen(),
      GroupListScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        const MethodChannel('com.answer.messenger/background')
            .invokeMethod('moveToBackground');
      },
      child: Scaffold(
        appBar: _buildAppBar(context, l, userProvider, photoUrl),
        body: pages[_currentIndex],
        bottomNavigationBar: _buildBottomNav(l),
      ),
    );
  }

  // ── 데스크톱 레이아웃 ─────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(BuildContext context, AppLocalizations l,
      UserProvider userProvider, String photoUrl) {
    final chatProvider = context.watch<ChatProvider>();
    final visitedRooms = chatProvider.visitedRooms;
    final activeRoomId = chatProvider.activeRoomId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        const MethodChannel('com.answer.messenger/background')
            .invokeMethod('moveToBackground');
      },
      child: Scaffold(
        body: Row(
          children: [
            // ── 왼쪽 사이드바 ─────────────────────────────────────────────
            SizedBox(
              width: 320,
              child: Scaffold(
                appBar: _buildAppBar(context, l, userProvider, photoUrl),
                body: _buildDesktopSidebar(context, l, chatProvider),
                bottomNavigationBar: _buildBottomNav(l),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),

            // ── 오른쪽 채팅 영역 ──────────────────────────────────────────
            Expanded(
              child: _currentIndex == 1
                  ? _buildDesktopChatArea(
                      context, visitedRooms, activeRoomId, l)
                  : _currentIndex == 2
                      ? _buildDesktopMemoArea(context, l)
                  : _buildDesktopOtherTab(context, l),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(
      BuildContext context, AppLocalizations l, ChatProvider chatProvider) {
    switch (_currentIndex) {
      case 0:
        return FriendsScreen();
      case 1:
        return ChatListScreen(
          onRoomSelected: (roomId) {
            chatProvider.selectRoom(roomId);
          },
        );
      case 2:
        return MemoScreen(
          isDesktopMode: true,
          selectedMemoId: _activeMemoId,
          onCreateRequested: () {
            setState(() {
              _isEditingMemo = true;
              _editingMemoId = null;
              _editingMemoData = null;
            });
          },
          onMemoSelected: (memoId, data) {
            if (!mounted) return;
            if (_isEditingMemo) {
              setState(() {
                _isEditingMemo = false;
                _editingMemoId = null;
                _editingMemoData = null;
              });
            }
            if (_activeMemoId == memoId) return;
            setState(() {
              _activeMemoId = memoId;
              _activeMemoData = data;
            });
          },
        );
      case 3:
        return GroupListScreen();
      default:
        return const SizedBox();
    }
  }

  Widget _buildDesktopChatArea(
    BuildContext context,
    List<String> visitedRooms,
    String? activeRoomId,
    AppLocalizations l,
  ) {
    if (visitedRooms.isEmpty || activeRoomId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              l.selectChatHint,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // IndexedStack으로 방문한 모든 방을 유지
    // 방이 바뀌어도 위젯이 살아있어서 스트림 재연결 없음
    final activeIndex = visitedRooms.indexOf(activeRoomId);

    return IndexedStack(
      index: activeIndex < 0 ? 0 : activeIndex,
      children: visitedRooms
          .map(
            (roomId) => ChatRoomScreen(
              key: ValueKey(roomId), // 방마다 고정 key → 위젯 재사용
              roomId: roomId,
              isDesktopMode: true, // 데스크톱 모드 플래그
            ),
          )
          .toList(),
    );
  }

  Widget _buildDesktopOtherTab(BuildContext context, AppLocalizations l) {
    // 채팅 탭이 아닐 때 오른쪽 영역
    return Center(
      child: Text(
        _currentIndex == 0
            ? l.selectFriendHint
            : _currentIndex == 2
                ? l.selectMemoHint
                : l.selectGroupHint,
        style: TextStyle(
          color:
              Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildDesktopMemoArea(
    BuildContext context,
    AppLocalizations l,
  ) {
    if (_isEditingMemo) {
      final data = _editingMemoData;
      return MemoFormSheet(
        memoId: _editingMemoId,
        initialTitle: data?['title'] as String? ?? '',
        initialContent: data?['content'] as String? ?? '',
        initialBlocks: List<Map<String, dynamic>>.from(
          ((data?['blocks'] as List?) ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ),
        initialAttachments: List<Map<String, dynamic>>.from(
          ((data?['attachments'] as List?) ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ),
        service: context.read<MemoService>(),
        embedded: true,
        onCancel: () {
          setState(() {
            _isEditingMemo = false;
            _editingMemoId = null;
            _editingMemoData = null;
          });
        },
        onSaved: (savedId) {
          setState(() {
            _isEditingMemo = false;
            _activeMemoId = savedId;
            _activeMemoData =
                _editingMemoId == savedId ? _editingMemoData : null;
            _editingMemoId = null;
            _editingMemoData = null;
          });
        },
      );
    }

    final memoId = _activeMemoId;
    if (memoId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              l.selectMemoHint,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return MemoDetailPane(
      memoId: memoId,
      initialData: _activeMemoData,
      service: context.read<MemoService>(),
      onEditRequested: () {
        setState(() {
          _isEditingMemo = true;
          _editingMemoId = memoId;
          _editingMemoData = _activeMemoData;
        });
      },
    );
  }

  AppBar _buildAppBar(BuildContext context, AppLocalizations l,
      UserProvider userProvider, String photoUrl) {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: CircleAvatar(
            radius: 12,
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: photoUrl.isNotEmpty
                ? CachedNetworkImageProvider(photoUrl)
                : null,
            child: photoUrl.isEmpty
                ? Text(
                    userProvider.name.isNotEmpty
                        ? userProvider.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer,
                    ),
                  )
                : null,
          ),
        ),
      ),
      title: Text(_getAppBarTitle(l, _currentIndex)),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AppSettingsScreen()),
          ),
        ),
      ],
    );
  }

  BottomNavigationBar _buildBottomNav(AppLocalizations l) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.person),
          label: l.navFriends,
        ),
        BottomNavigationBarItem(
          icon: _ChatTabIcon(unreadCount: _unreadCount),
          label: l.navChats,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.note_outlined),
          label: l.navMemo,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.groups),
          label: l.navGroups,
        ),
      ],
    );
  }

  String _getAppBarTitle(AppLocalizations l, int index) {
    if (index == 0) return l.navFriends;
    if (index == 1) return l.navChats;
    if (index == 2) return l.navMemo;
    return l.navGroups;
  }
}

// ── 채팅 탭 아이콘 ────────────────────────────────────────────────────────────
class _ChatTabIcon extends StatelessWidget {
  final int unreadCount;
  const _ChatTabIcon({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    if (unreadCount == 0) return const Icon(Icons.chat_bubble);
    final cs = Theme.of(context).colorScheme;
    final label = unreadCount > 99 ? '99+' : '$unreadCount';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: label.length > 2 ? 4 : 5,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: cs.error,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints:
                const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              label,
              style: TextStyle(
                color: cs.onError,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
