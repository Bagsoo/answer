import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'services/chat_service.dart';
import 'services/auth_service.dart';
import 'services/group_service.dart';
import 'services/friend_service.dart';
import 'services/notification_service.dart';
import 'services/block_service.dart';
import 'services/memo_service.dart';
import 'services/poll_service.dart';
import 'services/report_service.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/auth_wrapper.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase 먼저 초기화 (다른 서비스가 Firebase에 의존하므로 반드시 먼저) ──
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .catchError((e) {
      debugPrint('Firebase init error: $e');
    });
  } else {
    Firebase.app();
  }

  // ── Firestore 오프라인 캐시 설정 ────────────────────────────────────────────
  // - 오프라인에서도 마지막 캐시 데이터 표시
  // - 네트워크 재연결 시 자동 동기화
  // - 쿼리 결과가 캐시에서 먼저 오고 Firebase에서 최신화 (읽기 비용 절감)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // ── Firebase 완료 후 나머지 병렬 초기화 ────────────────────────────────────
  // dotenv는 await, NotificationService는 네트워크 의존이므로 fire-and-forget
  await dotenv.load(fileName: '.env');
  NotificationService().init(); // await 없이 — 네트워크 없어도 앱 시작 블로킹 안 함

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        // LocaleProvider, ThemeProvider는 생성자에서 SharedPreferences 즉시 로드
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
        Provider<ChatService>(create: (_) => ChatService()),
        Provider<GroupService>(create: (_) => GroupService()),
        Provider<FriendService>(create: (_) => FriendService()),
        Provider<BlockService>(create: (_) => BlockService()),
        Provider<MemoService>(create: (_) => MemoService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<PollService>(create: (_) => PollService()),
        Provider<ReportService>(create: (_) => ReportService()),
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
      title: 'Group Messenger',
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