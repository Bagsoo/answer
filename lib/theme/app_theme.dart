import 'package:flutter/material.dart';

class AppTheme {
  static const _primaryColor = Colors.amber;
  static const _primaryDark = Color(0xFFFFB300); // amber[700]

  // ── Light Theme ───────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        brightness: Brightness.light,

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.5,
          centerTitle: true,
        ),

        // BottomNavigationBar
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: _primaryColor,
          unselectedItemColor: Colors.black38,
          backgroundColor: Colors.white,
          type: BottomNavigationBarType.fixed,
        ),

        // TabBar
        tabBarTheme: const TabBarThemeData(
          labelColor: _primaryColor,
          unselectedLabelColor: Colors.black38,
          indicatorColor: _primaryColor,
        ),

        // FloatingActionButton
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.black87,
        ),

        // ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.black87,
          ),
        ),

        // Card
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _primaryColor
                : Colors.grey[300],
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _primaryColor.withOpacity(0.4)
                : Colors.grey[200],
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEEEEEE),
          thickness: 1,
        ),

        // Input
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryColor, width: 1.5),
          ),
        ),
      );

  // ── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primaryDark,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0.5,
          centerTitle: true,
        ),

        // BottomNavigationBar
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: _primaryDark,
          unselectedItemColor: Colors.white38,
          backgroundColor: Color(0xFF1E1E1E),
          type: BottomNavigationBarType.fixed,
        ),

        // TabBar
        tabBarTheme: const TabBarThemeData(
          labelColor: _primaryDark,
          unselectedLabelColor: Colors.white38,
          indicatorColor: _primaryDark,
        ),

        // FloatingActionButton
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: _primaryDark,
          foregroundColor: Colors.black87,
        ),

        // ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryDark,
            foregroundColor: Colors.black87,
          ),
        ),

        // Card
        cardTheme: CardThemeData(
          color: const Color(0xFF2C2C2C),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _primaryDark
                : Colors.grey[600],
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _primaryDark.withOpacity(0.4)
                : Colors.grey[800],
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: Color(0xFF3A3A3A),
          thickness: 1,
        ),

        // Input
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primaryDark, width: 1.5),
          ),
        ),
      );
}