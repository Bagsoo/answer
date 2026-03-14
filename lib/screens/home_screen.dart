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
      context.read<UserProvider>().loadUser();       // 유저 정보 1번만 로드
      context.read<LocaleProvider>().loadFromFirestore();
      context.read<ThemeProvider>().loadFromFirestore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final pages = [
      FriendsScreen(),
      ChatListScreen(),
      const MemoScreen(),
      GroupListScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
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
    );
  }

  String _getAppBarTitle(AppLocalizations l, int index) {
    if (index == 0) return l.navFriends;
    if (index == 1) return l.navChats;
    if (index == 2) return l.navMemo;
    return l.navGroups;
  }
}