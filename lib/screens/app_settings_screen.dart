import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/block_service.dart';
import '../l10n/app_localizations.dart';
import 'profile_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;

  bool _notifChat = true;
  bool _notifJoin = true;
  bool _notifSchedule = true;
  bool _notifMarketing = false;

  static const _languages = [
    {'code': 'en', 'label': '🇺🇸 English'},
    {'code': 'ko', 'label': '🇰🇷 한국어'},
    {'code': 'ja', 'label': '🇯🇵 日本語'},
  ];

  static const _timezones = [
    'Asia/Seoul', 'Asia/Tokyo', 'Asia/Shanghai', 'Asia/Singapore',
    'America/New_York', 'America/Los_Angeles', 'America/Chicago',
    'Europe/London', 'Europe/Paris', 'Europe/Berlin',
    'Australia/Sydney', 'UTC',
  ];

  bool _settingsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSettings(context);
    }
  }

  Future<void> _loadSettings(BuildContext context) async {
    final notifSettings =
        await context.read<NotificationService>().loadNotificationSettings();
    if (mounted) {
      setState(() {
        _notifChat = notifSettings['chat_message'] ?? true;
        _notifJoin = notifSettings['join_request'] ?? true;
        _notifSchedule = notifSettings['new_schedule'] ?? true;
        _notifMarketing = notifSettings['marketing'] ?? false;
        _loading = false;
      });
    }
  }

  Future<void> _saveTimezone(String timezone) async {
    await context.read<UserProvider>().updateTimezone(timezone);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).settingsSaved)),
      );
    }
  }

  Future<void> _saveNotifSettings(BuildContext context) async {
    await context.read<NotificationService>().saveNotificationSettings({
      'chat_message': _notifChat,
      'join_request': _notifJoin,
      'new_schedule': _notifSchedule,
      'marketing': _notifMarketing,
    });
  }

  void _showLogoutDialog(BuildContext context, AppLocalizations l) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.logout),
        content: Text(l.logoutConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // 다이얼로그 닫기
              await _logout(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<NotificationService>().deleteFcmToken();
    if (!context.mounted) return;

    context.read<LocaleProvider>().reset();
    context.read<ThemeProvider>().reset();
    await context.read<UserProvider>().clear();
    await context.read<AuthService>().signOut();

    if (!context.mounted) return;

    // 스택 전체를 비우고 LoginScreen이 있는 AuthWrapper로 이동
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
  }

  void _showDeleteAccountDialog(BuildContext context, AppLocalizations l) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAccount),
        content: Text(l.deleteAccountConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel)),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteAccount(context, l);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, AppLocalizations l) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final db = FirebaseFirestore.instance;
      final joinedGroupsSnap = await db
          .collection('users')
          .doc(uid)
          .collection('joined_groups')
          .get();
      final batch = db.batch();
      for (final doc in joinedGroupsSnap.docs) {
        final groupId = doc.id;
        batch.delete(db
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(uid));
        batch.update(db.collection('groups').doc(groupId),
            {'member_count': FieldValue.increment(-1)});
        batch.delete(doc.reference);
      }
      batch.delete(db.collection('users').doc(uid));
      await batch.commit();

      if (context.mounted) {
        context.read<LocaleProvider>().reset();
        context.read<ThemeProvider>().reset();
      }
      await FirebaseAuth.instance.currentUser?.delete();

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.deleteAccountFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final localeProvider = context.watch<LocaleProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final selectedTimezone = context.watch<UserProvider>().timezone;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── 프로필 ────────────────────────────────────────────────
                _SectionHeader(title: l.settingsProfile),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(Icons.person_outline,
                        color: colorScheme.onPrimaryContainer),
                  ),
                  title: Text(l.editProfile),
                  subtitle: Text(l.editProfileSubtitle),
                  trailing: Icon(Icons.chevron_right,
                      color: colorScheme.onSurface.withOpacity(0.4)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ProfileScreen()),
                  ),
                ),

                const Divider(),

                // ── 알림 설정 ──────────────────────────────────────────────
                _SectionHeader(title: l.settingsNotifications),
                _NotifSwitch(
                  icon: Icons.chat_bubble_outline,
                  label: l.notifChat,
                  subtitle: l.notifChatDesc,
                  value: _notifChat,
                  onChanged: (v) {
                    setState(() => _notifChat = v);
                    _saveNotifSettings(context);
                  },
                ),
                _NotifSwitch(
                  icon: Icons.person_add_outlined,
                  label: l.notifJoinRequest,
                  subtitle: l.notifJoinRequestDesc,
                  value: _notifJoin,
                  onChanged: (v) {
                    setState(() => _notifJoin = v);
                    _saveNotifSettings(context);
                  },
                ),
                _NotifSwitch(
                  icon: Icons.event_outlined,
                  label: l.notifSchedule,
                  subtitle: l.notifScheduleDesc,
                  value: _notifSchedule,
                  onChanged: (v) {
                    setState(() => _notifSchedule = v);
                    _saveNotifSettings(context);
                  },
                ),
                _NotifSwitch(
                  icon: Icons.campaign_outlined,
                  label: l.notifMarketing,
                  subtitle: l.notifMarketingDesc,
                  value: _notifMarketing,
                  onChanged: (v) {
                    setState(() => _notifMarketing = v);
                    _saveNotifSettings(context);
                  },
                ),

                const Divider(),

                // ── 언어 ──────────────────────────────────────────────────
                _SectionHeader(title: l.settingsLanguage),
                ..._languages.map((lang) {
                  final isSelected =
                      lang['code'] == localeProvider.locale.languageCode;
                  return ListTile(
                    title: Text(lang['label']!),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colorScheme.primary)
                        : null,
                    selected: isSelected,
                    selectedTileColor:
                        colorScheme.primary.withOpacity(0.08),
                    onTap: () => context
                        .read<LocaleProvider>()
                        .setLocale(Locale(lang['code']!)),
                  );
                }),

                const Divider(),

                // ── 테마 ──────────────────────────────────────────────────
                _SectionHeader(title: l.settingsTheme),
                _themeOption(context,
                    code: 'light',
                    label: l.themeLight,
                    icon: Icons.wb_sunny_outlined,
                    current: themeProvider.themeModeCode,
                    onTap: () =>
                        themeProvider.setThemeMode(ThemeMode.light)),
                _themeOption(context,
                    code: 'dark',
                    label: l.themeDark,
                    icon: Icons.nightlight_outlined,
                    current: themeProvider.themeModeCode,
                    onTap: () =>
                        themeProvider.setThemeMode(ThemeMode.dark)),
                _themeOption(context,
                    code: 'system',
                    label: l.themeSystem,
                    icon: Icons.phone_android_outlined,
                    current: themeProvider.themeModeCode,
                    onTap: () =>
                        themeProvider.setThemeMode(ThemeMode.system)),

                const Divider(),

                // ── 시간대 ────────────────────────────────────────────────
                _SectionHeader(title: l.settingsTimezone),
                ..._timezones.map((tz) {
                  final isSelected = tz == selectedTimezone;
                  return ListTile(
                    title: Text(tz),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colorScheme.primary)
                        : null,
                    selected: isSelected,
                    selectedTileColor:
                        colorScheme.primary.withOpacity(0.08),
                    onTap: () => _saveTimezone(tz),
                  );
                }),

                const Divider(),

                // ── 차단 관리 ─────────────────────────────────────────────
                _SectionHeader(title: l.blockedUsers),
                ListTile(
                  leading: Icon(Icons.block,
                      color: colorScheme.error.withOpacity(0.7)),
                  title: Text(l.blockedUsers),
                  subtitle: Text(l.noBlockedUsers),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen()),
                  ),
                ),

                const Divider(),

                // ── 계정 ──────────────────────────────────────────────────
                _SectionHeader(title: l.sectionAccount),
                ListTile(
                  leading: Icon(Icons.logout, color: colorScheme.primary),
                  title: Text(l.logout),
                  onTap: () => _showLogoutDialog(context, l),
                ),

                const Divider(),

                // ── 위험 구역 ──────────────────────────────────────────────
                _SectionHeader(
                    title: l.sectionDangerZone,
                    color: colorScheme.error),
                ListTile(
                  leading: Icon(Icons.person_remove,
                      color: colorScheme.error),
                  title: Text(l.deleteAccount,
                      style: TextStyle(
                          color: colorScheme.error,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(l.deleteAccountWarning),
                  onTap: () => _showDeleteAccountDialog(context, l),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _themeOption(
    BuildContext context, {
    required String code,
    required String label,
    required IconData icon,
    required String current,
    required VoidCallback onTap,
  }) {
    final isSelected = code == current;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing:
          isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
      selected: isSelected,
      selectedTileColor: colorScheme.primary.withOpacity(0.08),
      onTap: onTap,
    );
  }
}

// ── 알림 스위치 공통 위젯 ──────────────────────────────────────────────────────
class _NotifSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifSwitch({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: Icon(icon,
          color: value
              ? colorScheme.primary
              : colorScheme.onSurface.withOpacity(0.4)),
      title: Text(label),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.5))),
      value: value,
      onChanged: onChanged,
      activeColor: colorScheme.primary,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: color ?? colorScheme.onSurface.withOpacity(0.5),
          )),
    );
  }
}

// ── 차단 목록 화면 ─────────────────────────────────────────────────────────────
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final blockService = context.read<BlockService>();

    return Scaffold(
      appBar: AppBar(title: Text(l.blockedUsers)),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: blockService.getBlockedUsers(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final blocked = snap.data ?? [];

          if (blocked.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(l.noBlockedUsers,
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: blocked.length,
            itemBuilder: (context, i) {
              final user = blocked[i];
              final uid = user['uid'] as String;
              final name =
                  user['display_name'] as String? ?? l.unknown;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.errorContainer,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(name),
                trailing: TextButton(
                  onPressed: () async {
                    await blockService.unblockUser(uid);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.unblockUserDone)),
                      );
                    }
                  },
                  child: Text(l.unblockUser),
                ),
              );
            },
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
          );
        },
      ),
    );
  }
}