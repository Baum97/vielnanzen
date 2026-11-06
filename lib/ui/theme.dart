import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Design-System: ruhig, typografiegetrieben, eine Akzentfarbe.
class AppColors {
  static const bgBaseLight = Color(0xFFF7F7F5);
  static const bgBaseDark = Color(0xFF0E0F11);
  static const bgSurfaceLight = Color(0xFFFFFFFF);
  static const bgSurfaceDark = Color(0xFF17181B);
  static const bgElevatedDark = Color(0xFF1F2125);
  static const textPrimaryLight = Color(0xFF111214);
  static const textPrimaryDark = Color(0xFFF2F2F0);
  static const textSecondaryLight = Color(0xFF5F636B);
  static const textSecondaryDark = Color(0xFFA0A4AB);
  static const textTertiaryLight = Color(0xFF9A9EA5);
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

  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color pos(BuildContext c) => _dark(c) ? positiveDark : positive;
  static Color neg(BuildContext c) => _dark(c) ? criticalDark : critical;
  static Color warn(BuildContext c) => _dark(c) ? warningDark : warning;
}

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? AppColors.accentDark : AppColors.accent,
      onPrimary: Colors.white,
      secondary: dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
      onSecondary: dark ? AppColors.bgBaseDark : AppColors.bgBaseLight,
      surface: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
      onSurface: dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
      surfaceContainerHighest: dark ? AppColors.bgElevatedDark : const Color(0xFFF0F0EE),
      outline: dark ? AppColors.separatorDark : AppColors.separatorLight,
      error: dark ? AppColors.criticalDark : AppColors.critical,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.bgBaseDark : AppColors.bgBaseLight,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.bgBaseDark : AppColors.bgBaseLight,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurface)),
        height: 68,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 36, height: 42 / 36, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        displaySmall: TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 19, height: 24 / 19, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400),
        labelSmall: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
      ),
      cardTheme: CardThemeData(
        color: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline)),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: dark ? AppColors.separatorDark : AppColors.separatorLight),
      ),
      dividerColor: dark ? AppColors.separatorDark : AppColors.separatorLight,
      dividerTheme: DividerThemeData(color: dark ? AppColors.separatorDark : AppColors.separatorLight, space: 1),
    );
  }
}

/// Betragsformatierung de-DE mit echtem Minuszeichen; Beträge in Cent.
class AmountFormat {
  static final _full = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _int = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
  static final _compact = NumberFormat.compactCurrency(locale: 'de_DE', symbol: '€', decimalDigits: 1);
  static const hidden = '•••,•• €';

  static String format(int cents, {bool discreet = false, bool round = false}) {
    if (discreet) return hidden;
    final v = cents / 100;
    final f = (round || cents.abs() >= 1000000) ? _int : _full;
    return f.format(v).replaceFirst('-', '−');
  }

  /// Kurz für Achsen/Kacheln: "1,2 Tsd. €".
  static String compact(int cents, {bool discreet = false}) {
    if (discreet) return '•••';
    if (cents.abs() < 100000) return format(cents, round: true);
    return _compact.format(cents / 100).replaceFirst('-', '−');
  }

  static String signed(int cents, {bool discreet = false}) {
    if (discreet) return hidden;
    final body = format(cents.abs());
    if (cents > 0) return '+$body';
    if (cents < 0) return '−$body';
    return body;
  }

  static String percent(double v, {bool signed = false}) {
    final p = (v * 100).round();
    if (!signed) return '$p %';
    if (p > 0) return '+$p %';
    if (p < 0) return '−${p.abs()} %';
    return '±0 %';
  }

  static final date = DateFormat('dd.MM.yyyy', 'de_DE');
  static final dateShort = DateFormat('dd.MM.', 'de_DE');
  static final dayMonth = DateFormat('d. MMM', 'de_DE');
  static final weekdayDate = DateFormat('EEEE, d. MMMM', 'de_DE');
  static final monthYear = DateFormat('MMMM yyyy', 'de_DE');
  static final monthShort = DateFormat('MMM', 'de_DE');
  static final monthYearShort = DateFormat('MMM yy', 'de_DE');
  static final year = DateFormat('yyyy', 'de_DE');
}

Color parseHexColor(String? hex, {Color fallback = const Color(0xFF9A9EA5)}) {
  if (hex == null) return fallback;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// Symbol zu einem Kategorie-Icon-Namen aus categories.json.
IconData categoryIcon(String? name) => switch (name) {
      'house' => Icons.home_outlined,
      'lightning' => Icons.bolt_outlined,
      'drop' => Icons.water_drop_outlined,
      'wifi' => Icons.wifi,
      'tv' => Icons.tv_outlined,
      'basket' => Icons.shopping_basket_outlined,
      'cart' => Icons.shopping_cart_outlined,
      'bread' => Icons.bakery_dining_outlined,
      'store' => Icons.storefront_outlined,
      'car' => Icons.directions_car_outlined,
      'train' => Icons.train_outlined,
      'fuel' => Icons.local_gas_station_outlined,
      'taxi' => Icons.local_taxi_outlined,
      'parking' => Icons.local_parking,
      'wrench' => Icons.build_outlined,
      'receipt' => Icons.receipt_long_outlined,
      'play' => Icons.play_circle_outline,
      'music' => Icons.music_note_outlined,
      'newspaper' => Icons.newspaper_outlined,
      'cloud' => Icons.cloud_outlined,
      'fitness' => Icons.fitness_center,
      'gaming' => Icons.sports_esports_outlined,
      'shield' => Icons.shield_outlined,
      'health' => Icons.health_and_safety_outlined,
      'heart' => Icons.favorite_outline,
      'pill' => Icons.medication_outlined,
      'glasses' => Icons.visibility_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'delivery' => Icons.delivery_dining_outlined,
      'movie' => Icons.movie_outlined,
      'palette' => Icons.palette_outlined,
      'flight' => Icons.flight_outlined,
      'bag' => Icons.shopping_bag_outlined,
      'shirt' => Icons.checkroom_outlined,
      'devices' => Icons.devices_outlined,
      'chair' => Icons.chair_outlined,
      'family' => Icons.family_restroom,
      'child' => Icons.child_care_outlined,
      'school' => Icons.school_outlined,
      'pets' => Icons.pets_outlined,
      'gift' => Icons.card_giftcard_outlined,
      'bank' => Icons.account_balance_outlined,
      'cash' => Icons.payments_outlined,
      'income' => Icons.south_west,
      'work' => Icons.work_outline,
      'account' => Icons.account_balance_outlined,
      'trending' => Icons.trending_up,
      'refund' => Icons.undo,
      'savings' => Icons.savings_outlined,
      'transfer' => Icons.swap_horiz,
      _ => Icons.category_outlined,
    };
