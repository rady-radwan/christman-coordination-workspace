import 'package:flutter/material.dart';

import 'models.dart';

/// Brand copper from the Christman logo.
const brandCopper = Color(0xFFAE734B);

/// All app colors for one mode. Matches the approved mockup.
@immutable
class CwColors extends ThemeExtension<CwColors> {
  const CwColors({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.line2,
    required this.head,
    required this.headLine,
    required this.pill,
    required this.accent,
    required this.accentInk,
    required this.accentText,
    required this.selBg,
    required this.selFg,
    required this.avatarBg,
    required this.avatarInk,
    required this.tabOff,
    required this.dashed,
    required this.urgentText,
    required this.statusColors,
    required this.panel,
    required this.card,
    required this.side,
    required this.sideInk,
    required this.sideMuted,
    required this.sideLine,
    required this.sideSel,
  });

  final bool dark;
  final Color bg, surface, surface2, ink, ink2, muted, line, line2, head, headLine, pill;
  final Color accent, accentInk, accentText, selBg, selFg, avatarBg, avatarInk, tabOff, dashed, urgentText;

  /// Middle list panel and the cards on it.
  final Color panel, card;

  /// Soft copper background (Ball in Court card, selected filters).
  Color get accentSoft => dark ? const Color(0xFF2A2018) : const Color(0xFFF6ECE3);

  /// Background behind urgent/overdue text.
  Color get urgentBg => dark ? const Color(0xFF3B1A18) : const Color(0xFFFBE4E2);

  /// Left sidebar (desktop): warm dark brown in both modes.
  final Color side, sideInk, sideMuted, sideLine, sideSel;

  /// Status -> (text color, background color).
  final Map<ItemStatus, (Color, Color)> statusColors;

  Color statusFg(ItemStatus s) => statusColors[s]!.$1;
  Color statusBg(ItemStatus s) => statusColors[s]!.$2;

  static const light = CwColors(
    dark: false,
    bg: Color(0xFFF4F2EE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF8F7F4),
    ink: Color(0xFF1A1A1A),
    ink2: Color(0xFF3A3835),
    muted: Color(0xFF5C5A56),
    line: Color(0xFFDEDAD3),
    line2: Color(0xFFC9C4BB),
    head: Color(0xFFFFFFFF),
    headLine: Color(0xFFDEDAD3),
    pill: Color(0xFFF4F2EE),
    accent: Color(0xFF8C5A32),
    accentInk: Color(0xFFFFFFFF),
    accentText: Color(0xFF8C5A32),
    selBg: Color(0xFF1A1A1A),
    selFg: Color(0xFFFFFFFF),
    avatarBg: Color(0xFFEFE4DA),
    avatarInk: Color(0xFF6E4526),
    tabOff: Color(0xFF77736D),
    dashed: Color(0xFFA39E96),
    urgentText: Color(0xFFB3261E),
    statusColors: {
      ItemStatus.open: (Color(0xFF1F5FAD), Color(0xFFE3EDFA)),
      ItemStatus.inReview: (Color(0xFF7A5600), Color(0xFFFDF1D6)),
      ItemStatus.responseSubmitted: (Color(0xFFA84600), Color(0xFFFDE7D7)),
      ItemStatus.modelUpdated: (Color(0xFF6B3FA0), Color(0xFFEFE7F8)),
      ItemStatus.closed: (Color(0xFF2E7D4F), Color(0xFFE3F1E8)),
      ItemStatus.onHold: (Color(0xFF545A61), Color(0xFFECEDEE)),
      ItemStatus.voided: (Color(0xFF3A3D41), Color(0xFFDCDDDF)),
    },
    panel: Color(0xFFE9E5DE),
    card: Color(0xFFFFFFFF),
    side: Color(0xFF231D18),
    sideInk: Color(0xFFF3EEE8),
    sideMuted: Color(0xFFB0A79C),
    sideLine: Color(0xFF3B322B),
    sideSel: Color(0xFFAE734B),
  );

  static const darkColors = CwColors(
    dark: true,
    bg: Color(0xFF121212),
    surface: Color(0xFF1C1C1C),
    surface2: Color(0xFF242424),
    ink: Color(0xFFEDEBE7),
    ink2: Color(0xFFD6D2CB),
    muted: Color(0xFFA9A49C),
    line: Color(0xFF2C2C2C),
    line2: Color(0xFF45423E),
    head: Color(0xFF0A0A0A),
    headLine: Color(0xFF242424),
    pill: Color(0xFF1F1F1F),
    accent: Color(0xFFB98052),
    accentInk: Color(0xFF141414),
    accentText: Color(0xFFD19A6C),
    selBg: Color(0xFFEDEBE7),
    selFg: Color(0xFF141414),
    avatarBg: Color(0xFF3A2B1F),
    avatarInk: Color(0xFFE3B48C),
    tabOff: Color(0xFF8E8982),
    dashed: Color(0xFF5A5650),
    urgentText: Color(0xFFF2867E),
    statusColors: {
      ItemStatus.open: (Color(0xFF8AB8F0), Color(0xFF1A2A40)),
      ItemStatus.inReview: (Color(0xFFF0C55A), Color(0xFF3A2F14)),
      ItemStatus.responseSubmitted: (Color(0xFFF5A167), Color(0xFF3D2616)),
      ItemStatus.modelUpdated: (Color(0xFFC9AAF2), Color(0xFF2D2140)),
      ItemStatus.closed: (Color(0xFF7BC896), Color(0xFF1D3326)),
      ItemStatus.onHold: (Color(0xFFB5BAC0), Color(0xFF2B2E31)),
      ItemStatus.voided: (Color(0xFF8E9297), Color(0xFF232426)),
    },
    panel: Color(0xFF1E1F21),
    card: Color(0xFF2A2B2E),
    side: Color(0xFF1A1512),
    sideInk: Color(0xFFF1ECE6),
    sideMuted: Color(0xFFA49B90),
    sideLine: Color(0xFF332B25),
    sideSel: Color(0xFFB98052),
  );

  static CwColors of(BuildContext context) => Theme.of(context).extension<CwColors>() ?? light;

  @override
  CwColors copyWith() => this;

  @override
  CwColors lerp(ThemeExtension<CwColors>? other, double t) {
    if (other is! CwColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Fonts offered in Settings. '' is the built-in Christman look (Barlow).
const fontChoices = <String>[
  '',
  'Roboto',
  'Open Sans',
  'Google Sans',
  'Inter',
  'Montserrat',
  'Work Sans',
  'Lato',
  'Josefin Sans',
  'Poppins',
  'Nunito Sans',
  'Source Sans 3',
  'IBM Plex Sans',
  'Noto Sans',
];

String fontLabel(String f) => f.isEmpty ? 'Barlow (Christman default)' : f;

/// Family used by [condensed] headings; follows the chosen font.
String _headingFamily = 'BarlowCondensed';

ThemeData buildTheme(Brightness brightness, {String font = ''}) {
  final c = brightness == Brightness.dark ? CwColors.darkColors : CwColors.light;
  final family = fontChoices.contains(font) && font.isNotEmpty ? font : 'Barlow';
  _headingFamily = family == 'Barlow' ? 'BarlowCondensed' : family;
  final scheme = ColorScheme.fromSeed(seedColor: brandCopper, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: c.accentInk,
    secondary: c.selBg,
    onSecondary: c.selFg,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.line2,
    outlineVariant: c.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: family,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
  );
  OutlineInputBorder border(Color color, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: family),
    appBarTheme: AppBarTheme(
      backgroundColor: c.head,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: c.headLine)),
      titleTextStyle: TextStyle(
        fontFamily: _headingFamily,
        fontWeight: FontWeight.w700,
        fontSize: 22,
        color: c.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(c.line2),
      enabledBorder: border(c.line2),
      focusedBorder: border(c.accent, 2),
      hintStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        minimumSize: const Size(64, 48),
        textStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 44),
        side: BorderSide(color: c.line2),
        textStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        textStyle: TextStyle(fontFamily: family, fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    dividerColor: c.line,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? c.accentText : c.tabOff,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.accentText : c.tabOff)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.selBg,
      contentTextStyle: TextStyle(color: c.selFg, fontFamily: family, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Heading style used for section titles and the "Coordination Workspace" wordmark.
/// Barlow Condensed by default; the chosen font (slightly smaller) otherwise.
TextStyle condensed(double size, {Color? color, double letterSpacing = 0}) => TextStyle(
      fontFamily: _headingFamily,
      fontWeight: FontWeight.w700,
      fontSize: _headingFamily == 'BarlowCondensed' ? size : size * 0.86,
      height: 1.05,
      color: color,
      letterSpacing: letterSpacing,
    );
