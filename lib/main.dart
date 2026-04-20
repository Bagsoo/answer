import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/ads_helper.dart';

import 'services/chat_service.dart';
import 'services/auth_service.dart';
import 'services/group_service.dart';
import 'services/friend_service.dart';
import 'services/notification_service.dart';
import 'services/block_service.dart';
import 'services/memo_service.dart';
import 'services/poll_service.dart';
import 'services/report_service.dart';
import 'services/incoming_share_service.dart';
import 'services/my_schedule_service.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';
import 'providers/chat_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/auth_wrapper.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 가능 플랫폼 (Android, iOS, Windows, Web)
  final isFirebaseSupported = !kIsWeb 
      ? (defaultTargetPlatform == TargetPlatform.android || 
         defaultTargetPlatform == TargetPlatform.iOS || 
         defaultTargetPlatform == TargetPlatform.windows)
      : true;

  if (isFirebaseSupported) {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .catchError((e) => debugPrint('Firebase init error: $e'));
    }

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } else {
      final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: isMobile,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      NotificationService().init();
      await initializeAds();
    }
  }
  
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
        ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()..initialize()),
        Provider<ChatService>(create: (_) => ChatService()),
        Provider<GroupService>(create: (_) => GroupService()),
        Provider<FriendService>(create: (_) => FriendService()),
        Provider<BlockService>(create: (_) => BlockService()),
        Provider<MemoService>(create: (_) => MemoService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<PollService>(create: (_) => PollService()),
        Provider<ReportService>(create: (_) => ReportService()),
        Provider<MyScheduleService>(create: (_) => MyScheduleService()),
        ChangeNotifierProvider<IncomingShareService>(
          create: (_) => IncomingShareService()..initialize(),
        ),
      ],
      child: const MessengerApp(),
    ),
  );
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp(
      title: 'Answer Messenger',
      navigatorKey: NotificationService.navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ko'),
        Locale('ja'),
      ],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}
