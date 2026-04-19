import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'registration_screen.dart';
import '../services/notification_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('AuthWrapper build started');
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
                                  defaultTargetPlatform == TargetPlatform.iOS);

    final authService = context.watch<AuthService>();
    debugPrint('AuthWrapper got authService');
    final user = authService.currentUser;
    debugPrint('AuthWrapper user: $user');
    final isRegistered = authService.isRegisteredUser;
    debugPrint('AuthWrapper isRegistered: $isRegistered');

    if (user == null) {
      debugPrint('AuthWrapper returning LoginScreen');
      return const LoginScreen();
    } else if (isRegistered == null) {
      debugPrint('AuthWrapper returning Scaffold with CircularProgressIndicator');
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    } else if (isRegistered == false) {
      debugPrint('AuthWrapper returning RegistrationScreen');
      return const RegistrationScreen();
    } else {
      // 로그인 완료 시 FCM 토큰 저장 (모바일만)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isMobile) {
          NotificationService().saveFcmTokenOnLogin();
        }
      });
      debugPrint('AuthWrapper returning HomeScreen');
      return const HomeScreen();
    }
  }
}