import 'package:flutter/material.dart';

import 'models.dart';

/// Brand copper from the Christman logo.
const brandCopper = Color(0xFFAE734B);

// =====================================================================
// Appearance: each person's own theme, colors, font and text size.
// Saved on their account, so it follows them to every computer and phone.
// =====================================================================

/// Background family used for pages, panels and lines.
enum Tone {
  warm('Warm'),
  neutral('Neutral'),
  cool('Cool');

  const Tone(this.label);
  final String label;

  static Tone fromName(String? s) => values.firstWhere((t) => t.name == s, orElse: () => warm);
}

/// A ready-made color theme.
class ThemePreset {
  const ThemePreset(this.id, this.name, this.accent, this.sidebar, this.tone);
  final String id;
  final String name;
  final Color accent;
  final Color sidebar;
  final Tone tone;
}

const themePresets = <ThemePreset>[
  ThemePreset('christman', 'Christman Copper', brandCopper, Color(0xFF231D18), Tone.warm),
  ThemePreset('blueprint', 'Blueprint', Color(0xFF2F6FD0), Color(0xFF13233A), Tone.cool),
  ThemePreset('steel', 'Structural Steel', Color(0xFF4F6D86), Color(0xFF1D242B), Tone.neutral),
  ThemePreset('safety', 'Safety Orange', Color(0xFFE07000), Color(0xFF1B1B1B), Tone.neutral),
  ThemePreset('forest', 'Green Building', Color(0xFF2E7D5B), Color(0xFF15241D), Tone.neutral),
  ThemePreset('plum', 'Plum', Color(0xFF7B4FA0), Color(0xFF211A2A), Tone.neutral),
  ThemePreset('paper', 'Paper (light sidebar)', brandCopper, Color(0xFFEDE6DD), Tone.warm),
];

/// Accent colors offered as swatches (people can also type their own hex color).
const accentSwatches = <Color>[
  brandCopper,
  Color(0xFFC0392B),
  Color(0xFFE07000),
  Color(0xFFC99A06),
  Color(0xFF2E7D5B),
  Color(0xFF0F8A8A),
  Color(0xFF2F6FD0),
  Color(0xFF3949AB),
  Color(0xFF7B4FA0),
  Color(0xFFB0457A),
  Color(0xFF4F6D86),
  Color(0xFF5F5A54),
];

const sidebarSwatches = <Color>[
  Color(0xFF231D18),
  Color(0xFF1B1B1B),
  Color(0xFF0F1115),
  Color(0xFF13233A),
  Color(0xFF15241D),
  Color(0xFF211A2A),
  Color(0xFF3B2A1E),
  Color(0xFF2B3440),
  Color(0xFFEDE6DD),
  Color(0xFFE7ECF2),
  Color(0xFFF4F4F4),
];

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

String colorToHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? colorFromHex(String? s) {
  if (s == null) return null;
  final h = s.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

class Appearance {
  const Appearance({
    this.mode = ThemeMode.system,
    this.preset = 'christman',
    this.accent,
    this.sidebar,
    this.tone,
    this.font = '',
    this.textScale = 1.0,
  });

  final ThemeMode mode;
  final String preset;

  /// Own colors; null = take them from the preset.
  final Color? accent;
  final Color? sidebar;
  final Tone? tone;

  final String font;

  /// 0.85 – 1.35; 1.0 is the normal size.
  final double textScale;

  static const textScaleMin = 0.85;
  static const textScaleMax = 1.35;

  ThemePreset get presetSpec => themePresets.firstWhere((p) => p.id == preset, orElse: () => themePresets.first);
  Color get accentColor => accent ?? presetSpec.accent;
  Color get sidebarColor => sidebar ?? presetSpec.sidebar;
  Tone get toneValue => tone ?? presetSpec.tone;
  bool get isCustomized => accent != null || sidebar != null || tone != null;

  Appearance copyWith({
    ThemeMode? mode,
    String? preset,
    Color? accent,
    Color? sidebar,
    Tone? tone,
    String? font,
    double? textScale,
    bool clearColors = false,
  }) =>
      Appearance(
        mode: mode ?? this.mode,
        preset: preset ?? this.preset,
        accent: clearColors ? null : (accent ?? this.accent),
        sidebar: clearColors ? null : (sidebar ?? this.sidebar),
        tone: clearColors ? null : (tone ?? this.tone),
        font: font ?? this.font,
        textScale: (textScale ?? this.textScale).clamp(textScaleMin, textScaleMax).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'preset': preset,
        if (accent != null) 'accent': colorToHex(accent!),
        if (sidebar != null) 'sidebar': colorToHex(sidebar!),
        if (tone != null) 'tone': tone!.name,
        'font': font,
        'textScale': double.parse(textScale.toStringAsFixed(2)),
      };

  factory Appearance.fromJson(Map<String, dynamic>? j) {
    if (j == null || j.isEmpty) return const Appearance();
    final scale = (j['textScale'] as num?)?.toDouble() ?? 1.0;
    final font = (j['font'] ?? '') as String;
    return Appearance(
      mode: ThemeMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => ThemeMode.system),
      preset: themePresets.any((p) => p.id == j['preset']) ? j['preset'] as String : 'christman',
      accent: colorFromHex(j['accent'] as String?),
      sidebar: colorFromHex(j['sidebar'] as String?),
      tone: j['tone'] == null ? null : Tone.fromName(j['tone'] as String?),
      font: fontChoices.contains(font) ? font : '',
      textScale: scale.clamp(textScaleMin, textScaleMax).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.mode == mode &&
      other.preset == preset &&
      other.accent == accent &&
      other.sidebar == sidebar &&
      other.tone == tone &&
      other.font == font &&
      other.textScale == textScale;

  @override
  int get hashCode => Object.hash(mode, preset, accent, sidebar, tone, font, textScale);
}

// ------------------------------------------------------------------ color helpers

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Darkens (or lightens) [c] step by step until it reaches [target] contrast with [against].
Color reachContrast(Color c, Color against, double target, {required bool darker}) {
  var hsl = HSLColor.fromColor(c);
  var out = c;
  for (var i = 0; i < 50 && contrast(out, against) < target; i++) {
    final l = (hsl.lightness + (darker ? -0.02 : 0.02)).clamp(0.0, 1.0).toDouble();
    hsl = hsl.withLightness(l);
    out = hsl.toColor();
    if (l == 0.0 || l == 1.0) break;
  }
  return out;
}

Color mix(Color top, double amount, Color under) => Color.alphaBlend(top.withValues(alpha: amount), under);

// =====================================================================
// All app colors for one mode, built from the person's appearance.
// =====================================================================

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
    required this.accentSoft,
    required this.selBg,
    required this.selFg,
    required this.avatarBg,
    required this.avatarInk,
    required this.tabOff,
    required this.dashed,
    required this.urgentText,
    required this.urgentBg,
    required this.statusColors,
    required this.panel,
    required this.card,
    required this.side,
    required this.sideInk,
    required this.sideMuted,
    required this.sideLine,
    required this.sideSel,
    required this.sideAccent,
    required this.sideIsDark,
  });

  final bool dark;
  final Color bg, surface, surface2, ink, ink2, muted, line, line2, head, headLine, pill;
  final Color accent, accentInk, accentText, accentSoft, selBg, selFg, avatarBg, avatarInk, tabOff, dashed;
  final Color urgentText, urgentBg;

  /// Middle list panel and the cards on it.
  final Color panel, card;

  /// Left sidebar (Windows).
  final Color side, sideInk, sideMuted, sideLine, sideSel, sideAccent;
  final bool sideIsDark;

  /// Status -> (text color, background color).
  final Map<ItemStatus, (Color, Color)> statusColors;

  Color statusFg(ItemStatus s) => statusColors[s]!.$1;
  Color statusBg(ItemStatus s) => statusColors[s]!.$2;

  static const _lightStatus = {
    ItemStatus.open: (Color(0xFF1F5FAD), Color(0xFFE3EDFA)),
    ItemStatus.inReview: (Color(0xFF7A5600), Color(0xFFFDF1D6)),
    ItemStatus.responseSubmitted: (Color(0xFFA84600), Color(0xFFFDE7D7)),
    ItemStatus.modelUpdated: (Color(0xFF6B3FA0), Color(0xFFEFE7F8)),
    ItemStatus.closed: (Color(0xFF2E7D4F), Color(0xFFE3F1E8)),
    ItemStatus.onHold: (Color(0xFF545A61), Color(0xFFECEDEE)),
    ItemStatus.voided: (Color(0xFF3A3D41), Color(0xFFDCDDDF)),
  };

  static const _darkStatus = {
    ItemStatus.open: (Color(0xFF8AB8F0), Color(0xFF1A2A40)),
    ItemStatus.inReview: (Color(0xFFF0C55A), Color(0xFF3A2F14)),
    ItemStatus.responseSubmitted: (Color(0xFFF5A167), Color(0xFF3D2616)),
    ItemStatus.modelUpdated: (Color(0xFFC9AAF2), Color(0xFF2D2140)),
    ItemStatus.closed: (Color(0xFF7BC896), Color(0xFF1D3326)),
    ItemStatus.onHold: (Color(0xFFB5BAC0), Color(0xFF2B2E31)),
    ItemStatus.voided: (Color(0xFF8E9297), Color(0xFF232426)),
  };

  /// (bg, surface, surface2, head, panel, card, pill, line, line2, ink, ink2, muted, tabOff, dashed)
  static List<Color> _base(Tone tone, bool dark) {
    if (!dark) {
      return switch (tone) {
        Tone.warm => const [
            Color(0xFFF4F2EE), Color(0xFFFFFFFF), Color(0xFFF8F7F4), Color(0xFFFFFFFF), Color(0xFFE9E5DE), Color(0xFFFFFFFF),
            Color(0xFFF4F2EE), Color(0xFFDEDAD3), Color(0xFFC9C4BB), Color(0xFF1A1A1A), Color(0xFF3A3835), Color(0xFF5C5A56),
            Color(0xFF6F6B65), Color(0xFFA39E96),
          ],
        Tone.neutral => const [
            Color(0xFFF2F3F5), Color(0xFFFFFFFF), Color(0xFFF8F9FA), Color(0xFFFFFFFF), Color(0xFFE5E7EA), Color(0xFFFFFFFF),
            Color(0xFFF1F3F5), Color(0xFFDCDFE3), Color(0xFFC5CAD0), Color(0xFF18191B), Color(0xFF36393E), Color(0xFF595E66),
            Color(0xFF6B7078), Color(0xFF9DA3AB),
          ],
        Tone.cool => const [
            Color(0xFFEDF1F6), Color(0xFFFFFFFF), Color(0xFFF6F8FB), Color(0xFFFFFFFF), Color(0xFFE0E7EF), Color(0xFFFFFFFF),
            Color(0xFFEDF2F7), Color(0xFFD5DDE6), Color(0xFFBEC9D5), Color(0xFF141A21), Color(0xFF323C48), Color(0xFF536071),
            Color(0xFF647184), Color(0xFF97A3B3),
          ],
      };
    }
    return switch (tone) {
      Tone.warm => const [
          Color(0xFF121212), Color(0xFF1C1C1C), Color(0xFF242424), Color(0xFF0A0A0A), Color(0xFF1E1F21), Color(0xFF2A2B2E),
          Color(0xFF1F1F1F), Color(0xFF2C2C2C), Color(0xFF45423E), Color(0xFFEDEBE7), Color(0xFFD6D2CB), Color(0xFFA9A49C),
          Color(0xFF8E8982), Color(0xFF5A5650),
        ],
      Tone.neutral => const [
          Color(0xFF111315), Color(0xFF1A1C1F), Color(0xFF22252A), Color(0xFF0A0B0C), Color(0xFF1C1F23), Color(0xFF272B30),
          Color(0xFF1D2024), Color(0xFF2A2E33), Color(0xFF41464D), Color(0xFFECEEF0), Color(0xFFD0D4D9), Color(0xFFA0A6AE),
          Color(0xFF878E97), Color(0xFF545A62),
        ],
      Tone.cool => const [
          Color(0xFF0F141A), Color(0xFF172029), Color(0xFF1E2832), Color(0xFF0A0E13), Color(0xFF18222C), Color(0xFF22303C),
          Color(0xFF1A2430), Color(0xFF26313D), Color(0xFF3B4856), Color(0xFFE8EEF4), Color(0xFFCAD5E0), Color(0xFF9AA8B7),
          Color(0xFF82909F), Color(0xFF4F5D6C),
        ],
    };
  }

  factory CwColors.build(Appearance a, {required bool dark}) {
    final b = _base(a.toneValue, dark);
    final bg = b[0], surface = b[1], surface2 = b[2], head = b[3], panel = b[4], card = b[5], pill = b[6];
    final line = b[7], line2 = b[8], ink = b[9], ink2 = b[10], muted = b[11], tabOff = b[12], dashed = b[13];
    final base = a.accentColor;

    // Accent: strong enough for white text in light mode; light enough for dark text in dark mode.
    final Color accent, accentInk, accentText;
    if (!dark) {
      accent = reachContrast(base, Colors.white, 4.6, darker: true);
      accentInk = Colors.white;
      accentText = reachContrast(base, surface, 4.8, darker: true);
    } else {
      accent = reachContrast(base, const Color(0xFF141414), 5.2, darker: false);
      accentInk = const Color(0xFF141414);
      accentText = reachContrast(base, surface, 6.0, darker: false);
    }

    // Sidebar: dark mode keeps it dark even if a light sidebar was chosen.
    var side = a.sidebarColor;
    if (dark) {
      final hsl = HSLColor.fromColor(side);
      side = hsl.withLightness((hsl.lightness * 0.75).clamp(0.04, 0.12).toDouble()).toColor();
    }
    final sideIsDark = side.computeLuminance() < 0.25;
    final sideInk = sideIsDark ? const Color(0xFFF3EEE8) : const Color(0xFF1E1A16);
    final sideMuted = mix(sideInk, 0.62, side);
    final sideLine = mix(sideInk, 0.12, side);
    final sideAccent = reachContrast(base, side, 4.8, darker: !sideIsDark);

    return CwColors(
      dark: dark,
      bg: bg,
      surface: surface,
      surface2: surface2,
      ink: ink,
      ink2: ink2,
      muted: muted,
      line: line,
      line2: line2,
      head: head,
      headLine: line,
      pill: pill,
      accent: accent,
      accentInk: accentInk,
      accentText: accentText,
      accentSoft: mix(base, dark ? 0.16 : 0.10, surface),
      selBg: ink,
      selFg: surface,
      avatarBg: mix(base, dark ? 0.28 : 0.16, surface),
      avatarInk: accentText,
      tabOff: tabOff,
      dashed: dashed,
      urgentText: dark ? const Color(0xFFF2867E) : const Color(0xFFB3261E),
      urgentBg: dark ? const Color(0xFF3B1A18) : const Color(0xFFFBE4E2),
      statusColors: dark ? _darkStatus : _lightStatus,
      panel: panel,
      card: card,
      side: side,
      sideInk: sideInk,
      sideMuted: sideMuted,
      sideLine: sideLine,
      sideSel: base,
      sideAccent: sideAccent,
      sideIsDark: sideIsDark,
    );
  }

  static final CwColors fallback = CwColors.build(const Appearance(), dark: false);

  static CwColors of(BuildContext context) => Theme.of(context).extension<CwColors>() ?? fallback;

  @override
  CwColors copyWith() => this;

  @override
  CwColors lerp(ThemeExtension<CwColors>? other, double t) {
    if (other is! CwColors) return this;
    return t < 0.5 ? this : other;
  }
}

// =====================================================================
// Priority colors: Urgent red, Critical orange, High amber, Medium blue, Low green.
// =====================================================================

class PriorityLook {
  const PriorityLook({required this.solid, required this.onSolid, required this.text, required this.tint, required this.border});

  /// Badge / selected chip background and its text.
  final Color solid, onSolid;

  /// Colored text on normal backgrounds.
  final Color text;

  /// Light card background and border.
  final Color tint, border;
}

PriorityLook priorityLook(Priority p, CwColors c) {
  final (Color solid, Color onSolid, Color lightText, Color darkText) = switch (p) {
    Priority.urgent => (const Color(0xFFC62828), Colors.white, const Color(0xFFB3261E), const Color(0xFFF2867E)),
    Priority.critical => (const Color(0xFFD9480F), Colors.white, const Color(0xFFB83E0C), const Color(0xFFF7A06E)),
    Priority.high => (const Color(0xFFF0A81C), const Color(0xFF1A1A1A), const Color(0xFF8A5A00), const Color(0xFFF3C55B)),
    Priority.medium => (const Color(0xFF1F6FD1), Colors.white, const Color(0xFF1B5FB4), const Color(0xFF8AB8F0)),
    Priority.low => (const Color(0xFF3C8455), Colors.white, const Color(0xFF2E6B44), const Color(0xFF86CFA0)),
  };
  return PriorityLook(
    solid: solid,
    onSolid: onSolid,
    text: c.dark ? darkText : lightText,
    tint: mix(solid, c.dark ? 0.15 : 0.08, c.card),
    border: mix(solid, c.dark ? 0.55 : 0.40, c.card),
  );
}

// =====================================================================
// Material theme
// =====================================================================

/// Family used by [condensed] headings; follows the chosen font.
String _headingFamily = 'BarlowCondensed';

ThemeData buildTheme(Brightness brightness, Appearance a) {
  final c = CwColors.build(a, dark: brightness == Brightness.dark);
  final family = a.font.isNotEmpty && fontChoices.contains(a.font) ? a.font : 'Barlow';
  _headingFamily = family == 'Barlow' ? 'BarlowCondensed' : family;
  final scheme = ColorScheme.fromSeed(seedColor: a.accentColor, brightness: brightness).copyWith(
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
      titleTextStyle: TextStyle(fontFamily: _headingFamily, fontWeight: FontWeight.w700, fontSize: 22, color: c.ink),
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
        minimumSize: const Size(64, 46),
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
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentInk : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentSoft : c.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentText : c.ink2),
        side: WidgetStatePropertyAll(BorderSide(color: c.line2)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
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

/// Heading style used for section titles and the wordmark.
/// Barlow Condensed by default; the chosen font (slightly smaller) otherwise.
TextStyle condensed(double size, {Color? color, double letterSpacing = 0}) => TextStyle(
      fontFamily: _headingFamily,
      fontWeight: FontWeight.w700,
      fontSize: _headingFamily == 'BarlowCondensed' ? size : size * 0.86,
      height: 1.05,
      color: color,
      letterSpacing: letterSpacing,
    );
