import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/chat_service.dart';
import '../l10n/app_localizations.dart';
import 'chat_list_screen.dart' hide GroupListScreen;
import 'chat_room_screen.dart';
import 'group_list_screen.dart';
import 'app_settings_screen.dart';
import 'friends_screen.dart';
import 'memo_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefKeyUnread = 'chat_total_unread';

  int _currentIndex = 0;
  int _unreadCount = 0;         // SP 캐시에서 즉시 로드
  String? _selectedRoomId;
  StreamSubscription<int>? _unreadSub;

  @override
  void initState() {
    super.initState();
    _loadCachedUnread();         // SP에서 즉시 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait<void>([
        context.read<UserProvider>().loadUser(),
        context.read<LocaleProvider>().loadFromFirestore(),
        context.read<ThemeProvider>().loadFromFirestore(),
      ]);
      _subscribeUnread();        // Firestore 스트림 구독
    });
  }

  // ── SP에서 즉시 로드 ──────────────────────────────────────────────────────
  Future<void> _loadCachedUnread() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_prefKeyUnread) ?? 0;
    if (mounted) setState(() => _unreadCount = cached);
  }

  // ── Firestore 스트림 구독 + SP 갱신 ──────────────────────────────────────
  void _subscribeUnread() {
    _unreadSub = context.read<ChatService>().totalUnreadStream().listen(
      (count) async {
        if (mounted) setState(() => _unreadCount = count);
        // SP 캐시 업데이트
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefKeyUnread, count);
      },
    );
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final userProvider = context.watch<UserProvider>();
    final photoUrl = userProvider.photoUrl ?? '';

    final pages = [
      FriendsScreen(),
      ChatListScreen(),
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
        appBar: AppBar(
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
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 700 && _currentIndex == 1) {
              return Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: ChatListScreen(  // FAB은 ChatListScreen 내부에 그대로
                      onRoomSelected: (roomId) {
                        setState(() => _selectedRoomId = roomId);
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selectedRoomId != null
                        ? ChatRoomScreen(roomId: _selectedRoomId!)
                        : Center(
                            child: Text(
                              'Select chatroom!',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            }
            // 모바일: 기존 방식
            final pages = [
              FriendsScreen(),
              const ChatListScreen(), // 모바일은 onRoomSelected 없이
              const MemoScreen(),
              GroupListScreen(),
            ];
            return pages[_currentIndex];
          },
        ),
        bottomNavigationBar: BottomNavigationBar(
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
        ),
      ),
    );
  }

  String _getAppBarTitle(AppLocalizations l, int index) {
    if (index == 0) return l.navFriends;
    if (index == 1) return l.navChats;
    if (index == 2) return l.navMemo;
    return l.navGroups;
  }
}

// ── 채팅 탭 아이콘 (읽지 않은 수 뱃지) ───────────────────────────────────────
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
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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