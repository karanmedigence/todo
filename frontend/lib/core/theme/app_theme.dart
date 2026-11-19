import 'package:material_ui/material_ui.dart';

class AppTheme {
  AppTheme._();

  static const gold = Color(0xFFEFBF04);
  static const goldLight = Color(0xFFF2D790);
  static const goldDark = Color(0xFF9F7A2A);
  static const black = Color(0xFF0B0B0A);
  static const charcoal = Color(0xFF141412);
  static const elevated = Color(0xFF1D1C19);
  static const muted = Color(0xFFAAA69C);

  static ThemeData get dark {
    final colorScheme = const ColorScheme.dark(
      primary: gold,
      onPrimary: black,
      secondary: goldLight,
      onSecondary: black,
      surface: charcoal,
      onSurface: Color(0xFFF7F4EA),
      error: Color(0xFFE58A7D),
      onError: black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: black,
      canvasColor: charcoal,
      splashColor: gold.withValues(alpha: 0.12),
      highlightColor: gold.withValues(alpha: 0.06),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: black,
        foregroundColor: Color(0xFFF7F4EA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFFF7F4EA),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: charcoal,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF292820)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: charcoal,
        hintStyle: const TextStyle(color: muted),
        labelStyle: const TextStyle(color: muted),
        floatingLabelStyle: const TextStyle(color: gold),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF343229)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE58A7D)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE58A7D), width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: black,
          disabledBackgroundColor: const Color(0xFF4A4537),
          disabledForegroundColor: muted,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: Color(0xFF625638)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: goldLight),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? gold : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(black),
        side: const BorderSide(color: goldDark, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF292820),
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: Color(0xFFF7F4EA),
          fontSize: 36,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineMedium: TextStyle(
          color: Color(0xFFF7F4EA),
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleLarge: TextStyle(
          color: Color(0xFFF7F4EA),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: Color(0xFFF7F4EA),
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: TextStyle(color: muted, fontSize: 14, height: 1.45),
      ),
    );
  }
}
