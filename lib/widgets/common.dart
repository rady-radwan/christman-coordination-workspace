import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../util/dates.dart';

/// Screens at least this wide use the Windows layout (sidebar, list, details).
const wideBreakpoint = 1000.0;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Christman logo in the right color for light or dark backgrounds.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.full = false, this.height = 20, this.onDark});
  final bool full;
  final double height;

  /// Force the light-on-dark logo (true) or the dark-on-light one (false), e.g. on the sidebar.
  final bool? onDark;

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? CwColors.of(context).dark;
    final kind = full ? 'full' : 'mark';
    return Image.asset(
      'assets/logo/christman-$kind-${dark ? 'dark' : 'light'}.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: full ? 'Christman, since 1894' : 'Christman',
    );
  }
}

/// "COORDINATION WORKSPACE" under the logo.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.size = 15, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        'COORDINATION WORKSPACE',
        style: condensed(size, color: color ?? CwColors.of(context).accentText, letterSpacing: size * 0.13),
      );
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.large = false});
  final Priority priority;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final look = priorityLook(priority, CwColors.of(context));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 7, vertical: large ? 3 : 2),
      decoration: BoxDecoration(color: look.solid, borderRadius: BorderRadius.circular(5)),
      child: Text(
        priority.label.toUpperCase(),
        style: TextStyle(fontSize: large ? 12 : 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: look.onSolid),
      ),
    );
  }
}

/// Priority choice in forms: colored dot when off, filled with the priority color when on.
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority, required this.selected, required this.onTap});
  final Priority priority;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final look = priorityLook(priority, c);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? look.solid : look.tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? look.solid : look.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected)
                Icon(Icons.check, size: 16, color: look.onSolid)
              else
                StatusDot(look.solid, size: 9),
              const SizedBox(width: 7),
              Text(priority.label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? look.onSolid : look.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 7});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.large = false, this.short = false});
  final ItemStatus status;
  final bool large;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final fg = c.statusFg(status);
    return Tooltip(
      message: status.meaning,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 10 : 9, vertical: large ? 4 : 3),
        decoration: BoxDecoration(color: c.statusBg(status), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusDot(fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(short ? status.shortLabel : status.label,
                softWrap: true,
                style: TextStyle(fontSize: large ? 13 : 12, fontWeight: FontWeight.w700, color: fg, height: 1.2)),
          ),
        ]),
      ),
    );
  }
}

/// Red "OVERDUE · 3 days", or the due date in gray, or nothing.
class DueLabel extends StatelessWidget {
  const DueLabel(this.item, {super.key, this.size = 13});
  final Item item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final days = item.overdueDays();
    if (days > 0) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(c.urgentText, size: 8),
        const SizedBox(width: 6),
        Text(overdueText(days),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: c.urgentText)),
      ]);
    }
    if (!item.status.isActive) {
      final when = item.closedAt ?? item.updatedAt;
      return Text('${item.status == ItemStatus.voided ? 'Voided' : 'Closed'} ${weekdayDate(when)}',
          style: TextStyle(fontSize: size, color: c.muted));
    }
    if (item.dueDate == null) return Text('No due date', style: TextStyle(fontSize: size, color: c.muted));
    return Text(dueText(item.dueDate!), style: TextStyle(fontSize: size, color: c.muted));
  }
}

/// Item number such as "NMC-CL-014" in copper.
class ItemNumber extends StatelessWidget {
  const ItemNumber(this.number, {super.key, this.size = 16});
  final String number;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        number,
        style: condensed(size, color: CwColors.of(context).accentText, letterSpacing: 0.3)
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

/// Small rounded tag, e.g. a trade name.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.strong = false});
  final String text;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: strong ? c.accent : c.line2, width: strong ? 1.5 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 15, color: c.muted), const SizedBox(width: 5)],
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
        ),
      ]),
    );
  }
}

/// Rounded toggle chip used for filters and form choices.
class CwChip extends StatelessWidget {
  const CwChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.trailing});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final fg = selected ? c.accentText : c.ink2;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.accentSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? c.accent : c.line2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: fg)),
                if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 16, color: fg)],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.size = 36, this.strong = false});
  final String initials;
  final double size;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? c.avatarBg : c.pill,
        shape: BoxShape.circle,
        border: strong ? null : Border.all(color: c.line2),
      ),
      child: Text(initials,
          style: TextStyle(color: strong ? c.avatarInk : c.ink2, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: c.muted)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// A rounded box with a light background, used for groups of facts.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.highlight = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: highlight ? c.accentSoft : c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? c.accent : c.line, width: highlight ? 2 : 1),
      ),
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: c.dashed),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: condensed(22, color: c.ink)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: c.muted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      ),
    );
  }
}

/// Label above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink2)),
        if (hint != null) TextSpan(text: '  $hint', style: TextStyle(fontSize: 12, color: c.muted)),
      ])),
    );
  }
}

/// Shows a message from a failed action.
void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E), foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Opens a form: as a dialog on Windows, as a full screen on phones.
Future<T?> openForm<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  if (isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 860),
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                const SizedBox(width: 8),
              ],
            ),
            body: builder(ctx),
          ),
        ),
      ),
    );
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => Scaffold(appBar: AppBar(title: Text(title)), body: builder(ctx)),
  ));
}

/// Asks for an optional note (used by status changes and passing the ball).
Future<String?> askNote(BuildContext context,
    {required String title, String? body, required String ok, String hint = 'Add a note (optional)', bool required = false}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (body != null) ...[Text(body), const SizedBox(height: 12)],
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(hintText: hint),
              onChanged: (_) => setState(() {}),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: required && ctrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, ctrl.text),
            child: Text(ok),
          ),
        ],
      ),
    ),
  );
}
