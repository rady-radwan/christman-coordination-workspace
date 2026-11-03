import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Settings › Appearance: light/dark, color themes, own colors, font and text size.
/// Saved on the person's account, so each person keeps their own look on every device.
class AppearancePanel extends StatelessWidget {
  const AppearancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final a = s.appearance;
    void set(Appearance next) => s.setAppearance(next);

    Widget heading(String text, [String? hint]) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            if (hint != null) TextSpan(text: '   $hint', style: TextStyle(fontSize: 13, color: c.muted)),
          ])),
        );

    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Appearance', style: condensed(22, color: c.ink))),
          TextButton.icon(
            onPressed: a == const Appearance() ? null : () => set(const Appearance()),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset to Christman default'),
          ),
        ]),
        Text('Your choices are saved on your account and only change the app for you.',
            style: TextStyle(fontSize: 13, color: c.muted)),

        heading('Light or dark'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ButtonSegment(value: ThemeMode.system, label: Text('Same as device'), icon: Icon(Icons.brightness_auto_outlined)),
          ],
          selected: {a.mode},
          onSelectionChanged: (v) => set(a.copyWith(mode: v.first)),
        ),

        heading('Color theme'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in themePresets)
            _PresetCard(
              preset: p,
              selected: a.preset == p.id && !a.isCustomized,
              onTap: () => set(a.copyWith(preset: p.id, clearColors: true)),
            ),
        ]),

        heading('Accent color', 'buttons, links, selected items'),
        _Swatches(
          colors: accentSwatches,
          selected: a.accentColor,
          onPick: (col) => set(a.copyWith(accent: col)),
          onCustom: () async {
            final col = await _askHex(context, 'Accent color', a.accentColor);
            if (col != null) set(a.copyWith(accent: col));
          },
        ),

        heading('Sidebar color', 'Windows'),
        _Swatches(
          colors: sidebarSwatches,
          selected: a.sidebarColor,
          onPick: (col) => set(a.copyWith(sidebar: col)),
          onCustom: () async {
            final col = await _askHex(context, 'Sidebar color', a.sidebarColor);
            if (col != null) set(a.copyWith(sidebar: col));
          },
        ),

        heading('Background tone'),
        SegmentedButton<Tone>(
          segments: [for (final t in Tone.values) ButtonSegment(value: t, label: Text(t.label))],
          selected: {a.toneValue},
          onSelectionChanged: (v) => set(a.copyWith(tone: v.first)),
        ),

        heading('Font'),
        DropdownButtonFormField<String>(
          key: ValueKey('font-${a.font}'),
          initialValue: fontChoices.contains(a.font) ? a.font : '',
          isExpanded: true,
          items: [
            for (final f in fontChoices)
              DropdownMenuItem(
                value: f,
                child: Text(fontLabel(f), style: TextStyle(fontFamily: f.isEmpty ? 'Barlow' : f, fontSize: 15)),
              ),
          ],
          onChanged: (v) => set(a.copyWith(font: v ?? '')),
        ),

        heading('Text size', '${(a.textScale * 100).round()}%'),
        Row(children: [
          Text('A', style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w700)),
          Expanded(
            child: Slider(
              value: a.textScale,
              min: Appearance.textScaleMin,
              max: Appearance.textScaleMax,
              divisions: ((Appearance.textScaleMax - Appearance.textScaleMin) / 0.05).round(),
              label: '${(a.textScale * 100).round()}%',
              onChanged: (v) => set(a.copyWith(textScale: double.parse(v.toStringAsFixed(2)))),
            ),
          ),
          Text('A', style: TextStyle(fontSize: 22, color: c.muted, fontWeight: FontWeight.w700)),
        ]),
        Wrap(spacing: 8, children: [
          for (final (label, v) in [('Small', 0.9), ('Normal', 1.0), ('Large', 1.15), ('Extra large', 1.3)])
            CwChip(label: label, selected: (a.textScale - v).abs() < 0.001, onTap: () => set(a.copyWith(textScale: v))),
        ]),

        heading('Preview'),
        const _Preview(),
      ]),
    );
  }
}

Future<Color?> _askHex(BuildContext context, String title, Color current) {
  final ctrl = TextEditingController(text: colorToHex(current));
  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final col = colorFromHex(ctrl.text);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FieldLabel('Hex color', hint: 'e.g. #AE734B'),
            TextField(controller: ctrl, autofocus: true, onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: col ?? Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CwColors.of(ctx).line2),
              ),
              alignment: Alignment.center,
              child: col == null ? const Text('Type 6 hex digits') : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: col == null ? null : () => Navigator.pop(ctx, col), child: const Text('Use Color')),
        ],
      );
    }),
  );
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.selected, required this.onTap});
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final look = CwColors.build(Appearance(preset: preset.id), dark: c.dark);
    return Semantics(
      button: true,
      selected: selected,
      label: preset.name,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.accent : c.line2, width: selected ? 2.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 168,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 58,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(width: 40, color: look.side, padding: const EdgeInsets.all(8), child: Align(alignment: Alignment.topLeft, child: Container(width: 10, height: 10, color: look.sideAccent))),
                  Expanded(
                    child: Container(
                      color: look.bg,
                      padding: const EdgeInsets.all(8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Container(height: 6, width: 54, decoration: BoxDecoration(color: look.line2, borderRadius: BorderRadius.circular(3))),
                        Container(height: 18, width: 62, decoration: BoxDecoration(color: look.accent, borderRadius: BorderRadius.circular(5))),
                      ]),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Row(children: [
                  Expanded(child: Text(preset.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink))),
                  if (selected) Icon(Icons.check_circle, size: 18, color: c.accent),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.selected, required this.onPick, required this.onCustom});
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final isCustom = !colors.contains(selected);
    Widget dot(Color col, bool on, VoidCallback tap, {String? tip, Widget? child}) => Tooltip(
          message: tip ?? colorToHex(col),
          child: InkWell(
            onTap: tap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                border: Border.all(color: on ? c.ink : c.line2, width: on ? 3 : 1),
              ),
              alignment: Alignment.center,
              child: child ??
                  (on ? Icon(Icons.check, size: 18, color: col.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null),
            ),
          ),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final col in colors) dot(col, col == selected, () => onPick(col)),
      dot(
        isCustom ? selected : c.surface,
        isCustom,
        onCustom,
        tip: 'Your own color (hex)',
        child: Icon(Icons.colorize, size: 18, color: isCustom ? (selected.computeLuminance() > 0.5 ? Colors.black : Colors.white) : c.ink2),
      ),
    ]);
  }
}

/// A small sample of the app in the chosen look.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    Widget card(Priority p, String number, String title) {
      final look = priorityLook(p, c);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: look.tint, borderRadius: BorderRadius.circular(12), border: Border.all(color: look.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [ItemNumber(number), const SizedBox(width: 8), PriorityBadge(p)]),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: c.ink)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 120,
          height: 270,
          color: c.side,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BrandLogo(height: 11, onDark: c.sideIsDark),
            const SizedBox(height: 6),
            Text('COORDINATION', style: condensed(11, color: c.sideAccent, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            for (final (label, on) in [('Ball in Court', false), ('All Items', true), ('Team', false)])
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: on ? c.sideSel.withValues(alpha: 0.26) : null, borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: TextStyle(fontSize: 12, color: c.sideInk, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
              ),
          ]),
        ),
        Expanded(
          child: Container(
            height: 270,
            color: c.panel,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              card(Priority.urgent, 'NMC-CL-014', 'Supply duct hits W14 beam'),
              card(Priority.high, 'NMC-SL-006', 'Storm drain needs a sleeve'),
              Row(children: [
                FilledButton(onPressed: () {}, child: const Text('New Item')),
                const SizedBox(width: 8),
                TextButton(onPressed: () {}, child: const Text('Link')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
