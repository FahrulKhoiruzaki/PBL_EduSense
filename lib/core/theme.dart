import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ink,
    required this.sl,
    required this.st,
    required this.si,
    required this.mi,
    required this.fo,
    required this.su,
    required this.bg,
    required this.danger,
  });

  final Color ink;
  final Color sl;
  final Color st;
  final Color si;
  final Color mi;
  final Color fo;
  final Color su;
  final Color bg;
  final Color danger;

  static const light = AppColors(
    ink: Color(0xFF16171A),
    sl: Color(0xFF4A4D53),
    st: Color(0xFF6B6E75),
    si: Color(0xFFC4C7CC),
    mi: Color(0xFFE3E5E8),
    fo: Color(0xFFF2F3F5),
    su: Color(0xFFFFFFFF),
    bg: Color(0xFFD9DBDF),
    danger: Color(0xFFB3423A),
  );

  static const dark = AppColors(
    ink: Color(0xFFF2F3F5),
    sl: Color(0xFFA6A9AF),
    st: Color(0xFF9A9DA4),
    si: Color(0xFF4A4D53),
    mi: Color(0xFF2A2C30),
    fo: Color(0xFF0F1012),
    su: Color(0xFF1A1B1E),
    bg: Color(0xFF050506),
    danger: Color(0xFFB3423A),
  );

  static const darkCardStart = Color(0xFF2A2C30);
  static const darkCardEnd = Color(0xFF16171A);
  static const onDarkCard = Color(0xFFF2F3F5);
  static const onDarkCardMuted = Color(0xFFC4C7CC);

  @override
  AppColors copyWith({
    Color? ink,
    Color? sl,
    Color? st,
    Color? si,
    Color? mi,
    Color? fo,
    Color? su,
    Color? bg,
    Color? danger,
  }) {
    return AppColors(
      ink: ink ?? this.ink,
      sl: sl ?? this.sl,
      st: st ?? this.st,
      si: si ?? this.si,
      mi: mi ?? this.mi,
      fo: fo ?? this.fo,
      su: su ?? this.su,
      bg: bg ?? this.bg,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      ink: Color.lerp(ink, other.ink, t)!,
      sl: Color.lerp(sl, other.sl, t)!,
      st: Color.lerp(st, other.st, t)!,
      si: Color.lerp(si, other.si, t)!,
      mi: Color.lerp(mi, other.mi, t)!,
      fo: Color.lerp(fo, other.fo, t)!,
      su: Color.lerp(su, other.su, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get _text => Theme.of(this).textTheme;

  TextStyle get styleH1 => _text.headlineLarge!;
  TextStyle get styleH1Small => _text.headlineMedium!;
  TextStyle get styleH2 => _text.titleLarge!;
  TextStyle get styleBig => _text.displayMedium!;
  TextStyle get styleNum => _text.headlineSmall!;
  TextStyle get styleBold => _text.titleMedium!;
  TextStyle get styleBody => _text.bodyMedium!;
  TextStyle get styleMedium => _text.bodyLarge!;
  TextStyle get styleMuted => _text.bodyMedium!.copyWith(color: colors.st);
  TextStyle get styleSoft => _text.bodyMedium!.copyWith(color: colors.sl);
  TextStyle get styleCaption => _text.bodySmall!;
  TextStyle get styleKick => _text.labelLarge!;
  TextStyle get styleBadge => _text.labelMedium!;
  TextStyle get styleError =>
      _text.bodySmall!.copyWith(color: colors.danger);
}

abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static TextTheme _textTheme(AppColors c) {
    TextStyle inter(
      double size,
      FontWeight weight, {
      required double height,
      double letterSpacing = 0,
      Color? color,
      bool tabular = false,
    }) {
      return GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height / size,
        letterSpacing: letterSpacing,
        color: color ?? c.ink,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );
    }

    return TextTheme(
      displayMedium:
          inter(36, FontWeight.w600, height: 40, letterSpacing: -1.08, tabular: true),
      headlineLarge:
          inter(32, FontWeight.w700, height: 38, letterSpacing: -0.96),
      headlineMedium:
          inter(28, FontWeight.w700, height: 34, letterSpacing: -0.84),
      headlineSmall: inter(22, FontWeight.w600, height: 26, tabular: true),
      titleLarge: inter(18, FontWeight.w600, height: 24, letterSpacing: -0.18),
      titleMedium: inter(14, FontWeight.w700, height: 20),
      bodyLarge: inter(14, FontWeight.w500, height: 20),
      bodyMedium: inter(14, FontWeight.w400, height: 20),
      bodySmall: inter(12, FontWeight.w400, height: 20, color: c.st),
      labelLarge: inter(13, FontWeight.w600, height: 16, color: c.st),
      labelMedium: inter(12, FontWeight.w600, height: 16),
    );
  }

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.ink,
      onPrimary: c.su,
      secondary: c.sl,
      onSecondary: c.su,
      error: c.danger,
      onError: Colors.white,
      surface: c.su,
      onSurface: c.ink,
      onSurfaceVariant: c.st,
      outline: c.si,
      outlineVariant: c.mi,
      surfaceContainerHighest: c.mi,
    );

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.fo,
      canvasColor: c.su,
      textTheme: _textTheme(c),
      extensions: [c],
      splashColor: c.mi,
      highlightColor: c.mi.withAlpha(120),
      dividerColor: c.mi,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.su,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: c.st),
        border: border(c.si),
        enabledBorder: border(c.si),
        focusedBorder: border(c.ink, 2),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 2),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.su,
        selectedItemColor: c.ink,
        unselectedItemColor: c.st,
        selectedLabelStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.su,
        modalBackgroundColor: c.su,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.su,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.ink,
          fixedSize: const Size(44, 44),
          minimumSize: const Size(44, 44),
        ),
      ),
    );
  }
}
