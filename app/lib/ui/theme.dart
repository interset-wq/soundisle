import 'package:flutter/material.dart';

class AppColors {
  static const accent = Color(0xFF7B6CFF);
  static const accentAlt = Color(0xFFFF6B9A);
  static const darkBackground = Color(0xFF0A0A11);
  static const darkSurface = Color(0xFF14141E);
  static const darkCard = Color(0xFF1B1B27);
  static const lightBackground = Color(0xFFF7F6FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0x14000000);
}

/// Theme-aware neutrals.
///
/// The UI was originally written against a fixed dark background, so many
/// widgets used translucent white for secondary text, icons, borders and
/// subtle fills. These helpers keep the same contrast in the light theme
/// without sprinkling `Brightness` checks through every page.
extension AppThemeColors on BuildContext {
  /// White-ish in the dark theme, near-black in the light theme.
  Color neutral(double alpha) =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: alpha);

  /// Background for inverted pills (play-all buttons, the main play button).
  Color get invertedFill => Theme.of(this).colorScheme.onSurface;

  /// Foreground used on top of [invertedFill].
  Color get invertedInk => Theme.of(this).colorScheme.surface;

  /// Subtle translucent fill for cards and chips.
  Color get subtleFill => neutral(
    Theme.of(this).brightness == Brightness.dark ? 0.045 : 0.05,
  );

  /// Hairline border between cards and the page background.
  Color get subtleBorder => neutral(
    Theme.of(this).brightness == Brightness.dark ? 0.05 : 0.08,
  );
}

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF9C8FFF),
      secondary: AppColors.accentAlt,
      surface: AppColors.darkSurface,
      surfaceContainerHighest: AppColors.darkCard,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF101018),
        indicatorColor: AppColors.accent.withValues(alpha: 0.22),
        height: 68,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: const Color(0xFF0D0D15),
        indicatorColor: AppColors.accent.withValues(alpha: 0.22),
        selectedLabelTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        labelType: NavigationRailLabelType.all,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
        thumbColor: Colors.white,
        overlayColor: Colors.white.withValues(alpha: 0.1),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1B1B27),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF161620),
        modalBackgroundColor: Color(0xFF161620),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E2E42),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: AppColors.accent,
        closeIconColor: Colors.white70,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06), thickness: 1),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF6B5CE6),
      secondary: AppColors.accentAlt,
      surface: AppColors.lightSurface,
      surfaceContainerHighest: const Color(0xFFF0EEF7),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        height: 68,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        selectedLabelTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        labelType: NavigationRailLabelType.all,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: scheme.onSurface,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.16),
        thumbColor: scheme.onSurface,
        overlayColor: scheme.onSurface.withValues(alpha: 0.08),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2E2E42),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: AppColors.accent,
        closeIconColor: Colors.white70,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.42)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      dividerTheme: DividerThemeData(color: scheme.onSurface.withValues(alpha: 0.08), thickness: 1),
    );
  }

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5),
        displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: base.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      );
}

String formatCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}
