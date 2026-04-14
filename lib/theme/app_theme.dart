import 'package:flutter/material.dart';

class AppTheme {
  static const Color _burgundy = Color(0xFF8B1A1A);
  static const Color _burgundyLight = Color(0xFFB22222);
  static const Color _burgundyDark = Color(0xFF5C0E0E);
  static const Color _roseGold = Color(0xFFC08081);
  static const Color _roseGoldSoft = Color(0xFFE1C0C1);
  static const Color _wine = Color(0xFF4A1F24);

  static const Color _lightBg = Color(0xFFF8F6F4);
  static const Color _lightBgSecondary = Color(0xFFEFEBE8);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceAlt = Color(0xFFF5EFEC);
  static const Color _lightText = Color(0xFF1A0A0A);
  static const Color _lightTextSecondary = Color(0xFF5C4040);
  static const Color _lightBorder = Color(0xFFE7D9D6);

  static const Color _darkBg = Color(0xFF0D0505);
  static const Color _darkBgSecondary = Color(0xFF180A0A);
  static const Color _darkSurface = Color(0xFF1E0C0C);
  static const Color _darkSurfaceAlt = Color(0xFF2A1212);
  static const Color _darkText = Color(0xFFF5EDED);
  static const Color _darkTextSecondary = Color(0xFFC4A0A0);
  static const Color _darkBorder = Color(0xFF3A2020);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _burgundy,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF3DEDA),
    onPrimaryContainer: Color(0xFF3A0909),
    secondary: _roseGold,
    onSecondary: Color(0xFF2A1718),
    secondaryContainer: Color(0xFFF0DEDA),
    onSecondaryContainer: Color(0xFF3A2223),
    tertiary: _wine,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFEAD8DA),
    onTertiaryContainer: Color(0xFF2F171A),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: _lightSurface,
    onSurface: _lightText,
    onSurfaceVariant: _lightTextSecondary,
    outline: Color(0xFFB59595),
    outlineVariant: _lightBorder,
    shadow: Color(0x29000000),
    scrim: Color(0x66000000),
    inverseSurface: Color(0xFF2F1717),
    onInverseSurface: Color(0xFFFDEEEE),
    inversePrimary: _roseGoldSoft,
    surfaceTint: _burgundy,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE8B6B3),
    onPrimary: Color(0xFF531112),
    primaryContainer: Color(0xFF6F1617),
    onPrimaryContainer: Color(0xFFFFDAD7),
    secondary: Color(0xFFE0B9BA),
    onSecondary: Color(0xFF412728),
    secondaryContainer: Color(0xFF5A3D3E),
    onSecondaryContainer: Color(0xFFFFDADA),
    tertiary: Color(0xFFD7BCC1),
    onTertiary: Color(0xFF3D2528),
    tertiaryContainer: Color(0xFF563B3F),
    onTertiaryContainer: Color(0xFFF4DDE1),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: _darkSurface,
    onSurface: _darkText,
    onSurfaceVariant: _darkTextSecondary,
    outline: Color(0xFF8E6C6C),
    outlineVariant: _darkBorder,
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
    inverseSurface: Color(0xFFF5EDED),
    onInverseSurface: Color(0xFF251314),
    inversePrimary: _burgundy,
    surfaceTint: _roseGold,
  );

  static ThemeData get light => _buildTheme(
        scheme: _lightScheme,
        scaffoldBackground: _lightBg,
        surfaceDim: _lightBgSecondary,
        elevatedSurface: _lightSurfaceAlt,
        border: _lightBorder,
      );

  static ThemeData get dark => _buildTheme(
        scheme: _darkScheme,
        scaffoldBackground: _darkBg,
        surfaceDim: _darkBgSecondary,
        elevatedSurface: _darkSurfaceAlt,
        border: _darkBorder,
      );

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color surfaceDim,
    required Color elevatedSurface,
    required Color border,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: scaffoldBackground,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        shadowColor: scheme.shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.4),
          borderRadius: BorderRadius.circular(999),
        ),
        dividerColor: border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: elevatedSurface,
          disabledForegroundColor: scheme.onSurfaceVariant,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary.withOpacity(0.28)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurface,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withOpacity(0.9),
          fontSize: 14,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.secondary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondary
              : scheme.outlineVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondary.withOpacity(0.42)
              : elevatedSurface,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        side: BorderSide(color: scheme.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: elevatedSurface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        secondaryLabelStyle:
            TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w700),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        selectedTileColor: scheme.primaryContainer.withOpacity(0.72),
        selectedColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer.withOpacity(0.45),
        circularTrackColor: scheme.primaryContainer.withOpacity(0.45),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
