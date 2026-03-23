import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../l10n/app_localizations.dart';
import 'chat_list_screen.dart' hide GroupListScreen;
import 'group_list_screen.dart';
import 'app_settings_screen.dart';
import 'friends_screen.dart';
import 'memo_screen.dart';
import 'profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 세 가지 로드를 병렬로 실행 — 순차 대기 없음
      Future.wait<void>([
        context.read<UserProvider>().loadUser(),
        context.read<LocaleProvider>().loadFromFirestore(),
        context.read<ThemeProvider>().loadFromFirestore(),
      ]);
    });
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
        const MethodChannel('com.answer.messenger/background').invokeMethod('moveToBackground');
      },
      child: Scaffold(
        appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
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
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
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
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AppSettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l.navFriends,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble),
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
    ));
  }

  String _getAppBarTitle(AppLocalizations l, int index) {
    if (index == 0) return l.navFriends;
    if (index == 1) return l.navChats;
    if (index == 2) return l.navMemo;
    return l.navGroups;
  }
}