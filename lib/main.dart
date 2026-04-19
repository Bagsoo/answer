import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
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
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('.env load error: $e');
  }

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

    // Windows 등 데스크톱에서 Firestore 디스크 persistence(LevelDB)가
    // 네이티브 크래시를 유발하는 사례가 있어(FlutterFire #12987, #13145),
    // 모바일에서만 디스크 persistence를 켠다.
    final useDiskPersistence = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      // 메모리 캐시 무제한이 일부 Windows 빌드에서 불안정해질 수 있어 상한을 둔다.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
    } else {
      FirebaseFirestore.instance.settings = Settings(
        persistenceEnabled: useDiskPersistence,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    // 모바일 전용 서비스
    final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      NotificationService().init();
      // MobileAds.instance.initialize();
      await initializeAds();
    }
  }
  
  final prefs = await SharedPreferences.getInstance();
  debugPrint('prefs initialized');

  runApp(
    MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        ChangeNotifierProvider<AuthService>(create: (_) { debugPrint('Init AuthService'); return AuthService(); }),
        ChangeNotifierProvider<LocaleProvider>(create: (_) { debugPrint('Init LocaleProvider'); return LocaleProvider(); }),
        ChangeNotifierProvider<ThemeProvider>(create: (_) { debugPrint('Init ThemeProvider'); return ThemeProvider(); }),
        ChangeNotifierProvider<UserProvider>(create: (_) { debugPrint('Init UserProvider'); return UserProvider(); }),
        ChangeNotifierProvider<ChatProvider>(create: (_) { debugPrint('Init ChatProvider'); return ChatProvider()..initialize(); }),
        Provider<ChatService>(create: (_) { debugPrint('Init ChatService'); return ChatService(); }),
        Provider<GroupService>(create: (_) { debugPrint('Init GroupService'); return GroupService(); }),
        Provider<FriendService>(create: (_) { debugPrint('Init FriendService'); return FriendService(); }),
        Provider<BlockService>(create: (_) { debugPrint('Init BlockService'); return BlockService(); }),
        Provider<MemoService>(create: (_) { debugPrint('Init MemoService'); return MemoService(); }),
        Provider<NotificationService>(create: (_) { debugPrint('Init NotificationService'); return NotificationService(); }),
        Provider<PollService>(create: (_) { debugPrint('Init PollService'); return PollService(); }),
        Provider<ReportService>(create: (_) { debugPrint('Init ReportService'); return ReportService(); }),
        Provider<MyScheduleService>(create: (_) { debugPrint('Init MyScheduleService'); return MyScheduleService(); }),
        ChangeNotifierProvider<IncomingShareService>(
          create: (_) { debugPrint('Init IncomingShareService'); return IncomingShareService()..initialize(); },
        ),
      ],
      child: Builder(
        builder: (context) {
          debugPrint('Providers loaded, building MessengerApp');
          return const MessengerApp();
        }
      ),
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
      title: 'Group Messenger',
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
