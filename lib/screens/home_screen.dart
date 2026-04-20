import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // 추가
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
import 'group_detail_screen.dart';
import 'app_settings_screen.dart';
import 'friends_screen.dart';
import 'memo_screen.dart';
import 'my_schedules_screen.dart';
import 'profile_screen.dart';
import 'incoming_share_screen.dart';
import '../widgets/memo/memo_detail_sheet.dart';
import '../widgets/memo/memo_form_sheet.dart';

import 'notification_screen.dart';
import '../services/user_notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  int _currentIndex = 0;
  bool _showingIncomingShare = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  IncomingShareService? _incomingShareService;
  String? _activeMemoId;
  Map<String, dynamic>? _activeMemoData;
  bool _isEditingMemo = false;
  String? _editingMemoId;
  Map<String, dynamic>? _editingMemoData;
  String? _activeGroupId;
  String? _activeGroupName;
  String? _activeScheduleId;
  Map<String, dynamic>? _activeScheduleData;
  final Map<String, Map<String, dynamic>> _desktopVisitedGroups = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _incomingShareService ??= context.read<IncomingShareService>();
  }

  Future<void> _bootstrapAfterFirstFrame() async {
    if (!mounted) return;
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    // 데스크톱(Windows 등)에서 동일 사용자 문서에 대한 Firestore get/update가
    // 한꺼번에 겹치면 네이티브 SDK가 불안정해지는 증상이 있어 순차 실행한다.
    final sequentialUserFetch = !kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
    try {
      if (sequentialUserFetch) {
        await context.read<UserProvider>().loadUser();
        if (!mounted) return;
        await context.read<LocaleProvider>().loadFromFirestore();
        if (!mounted) return;
        await context.read<ThemeProvider>().loadFromFirestore();
      } else {
        await Future.wait<void>([
          context.read<UserProvider>().loadUser(),
          context.read<LocaleProvider>().loadFromFirestore(),
          context.read<ThemeProvider>().loadFromFirestore(),
        ]);
      }
    } catch (e, st) {
      debugPrint('HomeScreen bootstrap error: $e\n$st');
    }
    if (!mounted) return;
    if (isMobile) {
      _incomingShareService?.addListener(_handleIncomingShare);
      _handleIncomingShare();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapAfterFirstFrame();
    });
  }

  @override
  void dispose() {
    _incomingShareService?.removeListener(_handleIncomingShare);
    _searchController.dispose();
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
    
    if (!userProvider.isLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
      FriendsScreen(filterQuery: _currentIndex == 0 ? _searchQuery : ''),
      ChatListScreen(filterQuery: _currentIndex == 1 ? _searchQuery : ''),
      MemoScreen(filterQuery: _currentIndex == 2 ? _searchQuery : ''),
      const MySchedulesScreen(),
      GroupListScreen(),
    ];

    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isMobile) {
          const MethodChannel('com.answer.messenger/background')
              .invokeMethod('moveToBackground');
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context, l, userProvider, photoUrl),
        body: pages[_currentIndex],
        bottomNavigationBar: _buildBottomNav(l),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, AppLocalizations l,
      UserProvider userProvider, String photoUrl) {
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    // Windows: 채팅 탭이 아닐 때는 ChatProvider를 watch하지 않는다.
    // 하단 네비의 Selector까지 겹치면 앱 기동 직후 Firestore 전역 구독이 붙어 프로세스가 끊기는 환경이 있었다.
    if (_isWindows && _currentIndex != 1) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (isMobile) {
            const MethodChannel('com.answer.messenger/background')
                .invokeMethod('moveToBackground');
          }
        },
        child: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 320,
                child: Scaffold(
                  appBar: _buildAppBar(context, l, userProvider, photoUrl),
                  body: _buildDesktopSidebar(context, l, null),
                  bottomNavigationBar: _buildBottomNav(l),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: _currentIndex == 2
                    ? _buildDesktopMemoArea(context, l)
                    : _currentIndex == 3
                        ? _buildDesktopScheduleArea(context, l)
                        : _currentIndex == 4
                            ? _buildDesktopGroupArea(context, l)
                            : _buildDesktopOtherTab(context, l),
              ),
            ],
          ),
        ),
      );
    }

    final chatProvider = context.watch<ChatProvider>();
    final visitedRooms = chatProvider.visitedRooms;
    final activeRoomId = chatProvider.activeRoomId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isMobile) {
          const MethodChannel('com.answer.messenger/background')
              .invokeMethod('moveToBackground');
        }
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

            // ── 오른쪽 컨텐츠 영역 ──────────────────────────────────────────
            Expanded(
              child: _currentIndex == 1
                  ? _buildDesktopChatArea(
                      context, visitedRooms, activeRoomId, l)
                  : _currentIndex == 2
                      ? _buildDesktopMemoArea(context, l)
                  : _currentIndex == 3
                      ? _buildDesktopScheduleArea(context, l)
                  : _currentIndex == 4
                      ? _buildDesktopGroupArea(context, l)
                      : _buildDesktopOtherTab(context, l),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(
      BuildContext context, AppLocalizations l, ChatProvider? chatProvider) {
    switch (_currentIndex) {
      case 0:
        return FriendsScreen(filterQuery: _currentIndex == 0 ? _searchQuery : '');
      case 1:
        final cp = chatProvider ?? context.read<ChatProvider>();
        return ChatListScreen(
          onRoomSelected: (roomId) {
            cp.selectRoom(roomId);
          },
          filterQuery: _currentIndex == 1 ? _searchQuery : '',
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
        return const MySchedulesScreen(isDesktopMode: true);
      case 4:
        return GroupListScreen(
          isDesktopMode: true,
          selectedGroupId: _activeGroupId,
          onGroupSelected: (group) {
            final groupId = group['id'] as String? ?? '';
            final groupName = group['name'] as String? ?? '';
            if (groupId.isEmpty || groupName.isEmpty) return;
            if (!mounted) return;
            if (_activeGroupId == groupId) return;
            setState(() {
              _activeGroupId = groupId;
              _activeGroupName = groupName;
              _desktopVisitedGroups[groupId] = Map<String, dynamic>.from(group);
            });
          },
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildDesktopScheduleArea(BuildContext context, AppLocalizations l) {
    // 스케줄은 현재 MySchedulesScreen 하나로 통합되어 있으므로 사이드바와 메인 영역을 어떻게 나눌지 고민 필요
    // 일단 메인 영역에도 동일하게 보여주거나, 메인에 더 큰 달력을 보여줄 수 있음.
    // 여기서는 메인 영역에 상세 내용을 보여주는 쪽으로 확장 가능.
    return const MySchedulesScreen(isDesktopMode: true);
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

  Widget _buildDesktopGroupArea(
    BuildContext context,
    AppLocalizations l,
  ) {
    final groupId = _activeGroupId;
    final groupName = _activeGroupName;
    if (groupId == null || groupName == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              l.selectGroupHint,
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

    final visitedIds = _desktopVisitedGroups.keys.toList();
    final activeIndex = visitedIds.indexOf(groupId);

    return IndexedStack(
      index: activeIndex < 0 ? 0 : activeIndex,
      children: visitedIds
          .map(
            (id) => GroupDetailScreen(
              key: ValueKey(id),
              groupId: id,
              groupName: (_desktopVisitedGroups[id]?['name'] as String?) ?? '',
              initialGroupData: _desktopVisitedGroups[id],
            ),
          )
          .toList(),
    );
  }

  AppBar _buildAppBar(BuildContext context, AppLocalizations l,
      UserProvider userProvider, String photoUrl) {
    final useRemoteAvatar = !_isWindows && photoUrl.isNotEmpty;    
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: useRemoteAvatar
                ? ResizeImage(
                    NetworkImage(photoUrl),
                    width: 64,
                    height: 64,
                    allowUpscaling: false,
                  )
                : null,
            child: !useRemoteAvatar
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
      title: _isSearching
        ? TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            decoration: InputDecoration(
              // hintText: l.searchPlaceholder,
              hintText: switch (_currentIndex) {
                0 => l.searchPlaceholder,
                1 => l.searchChatPlaceholder,
                2 => l.searchMemoPlaceholder,
                4 => l.searchGroupsHint,
                _ => l.searchPlaceholder,
              },
              border: InputBorder.none,
            ),
          )
        : Text(_getAppBarTitle(l, _currentIndex)),
      centerTitle: true,
      actions: [
        if (_currentIndex != 3 && _currentIndex != 4)
          IconButton(
            icon: Icon(_isSearching ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        // ── 알림 종 아이콘 ──
        StreamBuilder<bool>(
          stream: context.read<UserNotificationService>().hasUnreadNotifications(),
          builder: (context, snapshot) {
            final hasUnread = snapshot.data ?? false;
            return IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.notifications_none_outlined),
                  if (hasUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE0C1B3), // 로즈골드 색상
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              ),
            );
          },
        ),
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
      onTap: (index) => setState(() {
        _currentIndex = index;
        _isSearching = false;
        _searchController.clear();
        _searchQuery = '';
      }),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.person),
          label: l.navFriends,
        ),
        BottomNavigationBarItem(
          icon: _isWindows
              ? const Icon(Icons.chat_bubble)
              : Selector<ChatProvider, int>(
                  selector: (_, provider) => provider.totalUnreadCount,
                  builder: (context, totalUnreadCount, child) {
                    return _ChatTabIcon(unreadCount: totalUnreadCount);
                  },
                ),
          label: l.navChats,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.note_outlined),
          label: l.navMemo,
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.calendar_month_outlined),
          label: l.navSchedule,
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
    if (index == 3) return l.navSchedule;
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
