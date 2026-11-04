import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Design-System nach Spezifikation: ruhig, typografiegetrieben, eine Akzentfarbe.
class AppColors {
  static const bgBaseLight = Color(0xFFF7F7F5);
  static const bgBaseDark = Color(0xFF0E0F11);
  static const bgSurfaceLight = Color(0xFFFFFFFF);
  static const bgSurfaceDark = Color(0xFF17181B);
  static const bgElevatedLight = Color(0xFFFFFFFF);
  static const bgElevatedDark = Color(0xFF1F2125);
  static const textPrimaryLight = Color(0xFF111214);
  static const textPrimaryDark = Color(0xFFF2F2F0);
  static const textSecondaryLight = Color(0xFF5F636B);
  static const textSecondaryDark = Color(0xFFA0A4AB);
  static const textTertiaryLight = Color(0xFF9A9EA5);
  static const textTertiaryDark = Color(0xFF6B6F76);
  static const separatorLight = Color(0xFFE6E6E3);
  static const separatorDark = Color(0xFF2A2C30);
  static const accent = Color(0xFF2F5BEA);
  static const accentDark = Color(0xFF6E8BFF);
  static const positive = Color(0xFF1F9D6B);
  static const positiveDark = Color(0xFF3FCB8E);
  static const warning = Color(0xFFC98A12);
  static const warningDark = Color(0xFFF2B544);
  static const critical = Color(0xFFD6453D);
  static const criticalDark = Color(0xFFFF6B61);

  static const categoryPalette = [
    Color(0xFF5B7A99), // Schiefer
    Color(0xFF6B9E5E), // Salbei
    Color(0xFF4E8FB0), // Ozean
    Color(0xFFB0763F), // Terrakotta
    Color(0xFF8A6FA8), // Pflaume
    Color(0xFFC9A227), // Sand
    Color(0xFFC06A75), // Rose
    Color(0xFF5FA3A0), // Türkis
    Color(0xFF7A6F5F), // Taupe
    Color(0xFF9A7FB0), // Flieder
    Color(0xFF4E9E7A), // Smaragd
    Color(0xFF8A8F98), // Grau
  ];
}

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: dark ? AppColors.bgBaseDark : AppColors.bgBaseLight,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: dark ? AppColors.accentDark : AppColors.accent,
        onPrimary: Colors.white,
        secondary: dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        onSecondary: dark ? AppColors.bgBaseDark : AppColors.bgBaseLight,
        surface: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
        onSurface: dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        outline: dark ? AppColors.separatorDark : AppColors.separatorLight,
        error: dark ? AppColors.criticalDark : AppColors.critical,
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 40, height: 44 / 40, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400),
        labelSmall: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        color: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: dark ? AppColors.separatorDark : AppColors.separatorLight),
      ),
      dividerColor: dark ? AppColors.separatorDark : AppColors.separatorLight,
    );
  }
}

/// Betragsformatierung de-DE mit echtem Minuszeichen; Beträge in Cent.
class AmountFormat {
  static final _full = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _int = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  static String format(int cents, {bool discreet = false}) {
    if (discreet) return '•••,•• €';
    final v = cents / 100;
    if (cents.abs() >= 100000) {
      return _int.format(v).replaceFirst('-', '−');
    }
    return _full.format(v).replaceFirst('-', '−');
  }

  static String signed(int cents, {bool discreet = false}) {
    if (discreet) return '•••,•• €';
    final body = format(cents.abs(), discreet: discreet);
    if (cents > 0) return '+$body';
    if (cents < 0) return '−$body';
    return body;
  }

  static final date = DateFormat('dd.MM.yyyy', 'de_DE');
  static final dateShort = DateFormat('dd.MM.', 'de_DE');
  static final monthYear = DateFormat('MMMM yyyy', 'de_DE');
}

Color parseHexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
