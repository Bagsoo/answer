import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'registration_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // We listen to the AuthService to determine what to show
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final isRegistered = authService.isRegisteredUser;

    if (user == null) {
      // 1. Not logged in -> Show Login
      return const LoginScreen();
    } else if (isRegistered == null) {
      // 2. Checking Firestore... Show loading
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    } else if (isRegistered == false) {
      // 3. Logged in, but document doesn't exist -> Show Registration
      return const RegistrationScreen();
    } else {
      // 4. Logged in and registered -> Show Home
      return const HomeScreen();
    }
  }
}
