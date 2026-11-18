import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet "Soft Elegant Education": dasar Warm Ivory & Charcoal, identitas Muted Plum, aksen
/// Dusty Rose / Soft Amber / Lavender. Semua warna aplikasi berasal dari token ini (terang & gelap).
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
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.accent,
    required this.amber,
    required this.lavender,
    required this.success,
    required this.info,
    required this.warning,
    required this.chartNumerasi,
    required this.chartAttendance,
    required this.chartSubject,
  });

  /// Teks utama (Charcoal).
  final Color ink;
  /// Teks sekunder.
  final Color sl;
  /// Teks tersier / label sumbu.
  final Color st;
  /// Garis tepi.
  final Color si;
  /// Garis halus / latar netral komponen.
  final Color mi;
  /// Latar halaman (Warm Ivory).
  final Color fo;
  /// Permukaan kartu.
  final Color su;
  /// Latar terluar.
  final Color bg;
  /// Kesalahan.
  final Color danger;
  /// Identitas utama (Muted Plum): tombol utama, navigasi aktif, seri Literasi.
  final Color primary;
  /// Teks/ikon di atas [primary].
  final Color onPrimary;
  /// Latar lembut pilihan aktif.
  final Color primarySoft;
  /// Aksen sekunder (Dusty Rose).
  final Color accent;
  /// Penekanan informasi (Soft Amber).
  final Color amber;
  /// Aksen pendukung (Lavender).
  final Color lavender;
  /// Status berhasil/tuntas.
  final Color success;
  /// Status informasi.
  final Color info;
  /// Status perlu perhatian.
  final Color warning;
  /// Seri grafik Numerasi (Dusty Rose, kontras cukup untuk garis).
  final Color chartNumerasi;
  /// Seri grafik Kehadiran (Soft Amber, kontras cukup).
  final Color chartAttendance;
  /// Seri grafik mata pelajaran (Lavender, kontras cukup).
  final Color chartSubject;

  static const light = AppColors(
    ink: Color(0xFF29272D),
    sl: Color(0xFF4E4A54),
    st: Color(0xFF6B6571),
    si: Color(0xFFCFC7CB),
    mi: Color(0xFFEAE4E2),
    fo: Color(0xFFF5F2F0),
    su: Color(0xFFFFFDFB),
    bg: Color(0xFFE6DFDC),
    danger: Color(0xFFA8463F),
    primary: Color(0xFF80678C),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFEFE8F2),
    accent: Color(0xFFB9828C),
    amber: Color(0xFFC49A60),
    lavender: Color(0xFFA99AB8),
    success: Color(0xFF4E7A62),
    info: Color(0xFF5C7896),
    warning: Color(0xFF8C6934),
    chartNumerasi: Color(0xFFA06A75),
    chartAttendance: Color(0xFF98713A),
    chartSubject: Color(0xFF7C6C92),
  );

  static const dark = AppColors(
    ink: Color(0xFFEFEAF0),
    sl: Color(0xFFC9C1CD),
    st: Color(0xFFA69EAC),
    si: Color(0xFF4B4551),
    mi: Color(0xFF35303A),
    fo: Color(0xFF18161B),
    su: Color(0xFF221F26),
    bg: Color(0xFF0F0E11),
    danger: Color(0xFFE07A70),
    primary: Color(0xFFB9A1C6),
    onPrimary: Color(0xFF1E1A22),
    primarySoft: Color(0xFF3A3143),
    accent: Color(0xFFD3A1AA),
    amber: Color(0xFFD9B07A),
    lavender: Color(0xFFC2B5CF),
    success: Color(0xFF8DBF9F),
    info: Color(0xFF9DB6D1),
    warning: Color(0xFFD9B07A),
    chartNumerasi: Color(0xFFD3A1AA),
    chartAttendance: Color(0xFFD9B07A),
    chartSubject: Color(0xFFC2B5CF),
  );

  // Kartu "gelap" (hero, sidebar logo, login): plum tua yang sama di kedua mode.
  static const darkCardStart = Color(0xFF554561);
  static const darkCardEnd = Color(0xFF2E2733);
  static const onDarkCard = Color(0xFFF5F2F0);
  static const onDarkCardMuted = Color(0xFFDCD1E1);
  static const onDarkCardBorder = Color(0xFF8C7C97);

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
    Color? primary,
    Color? onPrimary,
    Color? primarySoft,
    Color? accent,
    Color? amber,
    Color? lavender,
    Color? success,
    Color? info,
    Color? warning,
    Color? chartNumerasi,
    Color? chartAttendance,
    Color? chartSubject,
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
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      amber: amber ?? this.amber,
      lavender: lavender ?? this.lavender,
      success: success ?? this.success,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      chartNumerasi: chartNumerasi ?? this.chartNumerasi,
      chartAttendance: chartAttendance ?? this.chartAttendance,
      chartSubject: chartSubject ?? this.chartSubject,
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
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      lavender: Color.lerp(lavender, other.lavender, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      chartNumerasi: Color.lerp(chartNumerasi, other.chartNumerasi, t)!,
      chartAttendance: Color.lerp(chartAttendance, other.chartAttendance, t)!,
      chartSubject: Color.lerp(chartSubject, other.chartSubject, t)!,
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
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.ink,
      secondary: c.accent,
      onSecondary: c.onPrimary,
      tertiary: c.amber,
      onTertiary: c.ink,
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
      splashColor: c.primarySoft,
      highlightColor: c.primarySoft.withAlpha(140),
      focusColor: c.primarySoft,
      hoverColor: c.primarySoft.withAlpha(110),
      dividerColor: c.mi,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.su,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: c.st),
        border: border(c.si),
        enabledBorder: border(c.si),
        focusedBorder: border(c.primary, 2),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 2),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.su,
        selectedItemColor: c.primary,
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withAlpha(70),
        selectionHandleColor: c.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : null),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.st),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.mi),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.primary)),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(6)),
        textStyle: GoogleFonts.inter(fontSize: 12, color: c.su),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: c.sl),
        dividerThickness: 1,
      ),
      chipTheme: ChipThemeData(
        selectedColor: c.primarySoft,
        checkmarkColor: c.primary,
        side: BorderSide(color: c.si),
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
