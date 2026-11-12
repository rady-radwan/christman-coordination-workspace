import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/update_widgets.dart';
import 'appearance_panel.dart';
import 'notifications_screen.dart';
import 'project_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final wide = isWide(context);
    return Column(children: [
      const PageHeader(title: 'Settings', subtitle: appName),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!wide && s.isAdmin) ...[
                    Panel(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('Project Setup', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Trades, item types, levels and abbreviations'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => s.open(Section.setup),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const _Profile(),
                  const SizedBox(height: 16),
                  const AppearancePanel(),
                  const SizedBox(height: 16),
                  const _SizesPanel(),
                  const SizedBox(height: 16),
                  Panel(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Account', style: condensed(22, color: c.ink)),
                      const SizedBox(height: 6),
                      Text('Signed in as ${s.me?.email ?? ''}${s.isAdmin ? ' · Admin' : ''}', style: TextStyle(color: c.ink2)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        OutlinedButton.icon(
                          onPressed: () => showProjectPicker(context),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text('Switch project (${s.projects.length})'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (await confirm(context, 'Sign out?', 'You can sign in again with a new code from your email.', ok: 'Sign out')) {
                              await s.signOut();
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign out'),
                        ),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  const _UpdatesPanel(),
                  const SizedBox(height: 16),
                  Text('$appName · version $appVersion\nThe Christman Company', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted)),
                ]),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _Profile extends StatefulWidget {
  const _Profile();

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  late final s = context.read<AppState>();
  late final _name = TextEditingController(text: s.me?.name ?? '');
  late final _company = TextEditingController(text: s.me?.company ?? '');
  late final _phone = TextEditingController(text: s.me?.phone ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('My details', style: condensed(22, color: c.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 10, children: [
          SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FieldLabel('Name'), TextField(controller: _name)])),
          SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FieldLabel('Company'), TextField(controller: _company)])),
          SizedBox(width: 300, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FieldLabel('Phone'), TextField(controller: _phone)])),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_name.text.trim().isEmpty) return;
                    setState(() => _busy = true);
                    try {
                      await s.updateMyDetails(name: _name.text, company: _company.text, phone: _phone.text);
                      if (context.mounted) showInfo(context, 'Saved');
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('Save'),
          ),
        ),
      ]),
    );
  }
}

/// This version, and a button to look for a newer one.
class _UpdatesPanel extends StatefulWidget {
  const _UpdatesPanel();

  @override
  State<_UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends State<_UpdatesPanel> {
  bool _checking = false;

  Future<void> _check() async {
    final s = context.read<AppState>();
    setState(() => _checking = true);
    final found = await s.checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (found) {
      await showUpdateDialog(context, s.update!);
    } else {
      showInfo(context, 'You have the newest version ($appVersion).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final r = s.update;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('App version', style: condensed(22, color: c.ink)),
        const SizedBox(height: 6),
        Text(
          r == null
              ? 'You have version $appVersion.${s.updateCheckedAt == null ? '' : ' Last checked ${timeText(s.updateCheckedAt!)}.'}'
              : 'You have version $appVersion. Version ${r.version} is ready to install.',
          style: TextStyle(color: c.ink2),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (r != null)
            FilledButton.icon(onPressed: () => showUpdateDialog(context, r), icon: const Icon(Icons.system_update_alt), label: Text('Get version ${r.version}')),
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            label: const Text('Check for updates'),
          ),
        ]),
      ]),
    );
  }
}

/// Item photo size, description text size, card color and panel widths (saved for this person).
class _SizesPanel extends StatelessWidget {
  const _SizesPanel();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final v = s.view;
    Widget row(String title, String value, Widget slider, {String? hint}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: c.accentText)),
            ]),
            if (hint != null) Text(hint, style: TextStyle(fontSize: 13, color: c.muted)),
            slider,
          ]),
        );
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Layout and sizes', style: condensed(22, color: c.ink)),
        const SizedBox(height: 4),
        Text('Your own choices; they follow you to any computer you sign in on.', style: TextStyle(color: c.ink2)),
        row(
          'Item photo size',
          '${(v.photoShare * 100).round()}% of the width',
          Slider(
            value: v.photoShare,
            min: ViewPrefs.photoMin,
            max: ViewPrefs.photoMax,
            divisions: ((ViewPrefs.photoMax - ViewPrefs.photoMin) * 20).round(),
            onChanged: (x) => s.setView(v.copyWith(photoShare: x)),
          ),
          hint: 'The photo sits beside the description on an item page. You can also drag the edge between them.',
        ),
        row(
          'Description text size',
          '${v.descSize.round()}',
          Slider(
            value: v.descSize,
            min: ViewPrefs.descMin,
            max: ViewPrefs.descMax,
            divisions: (ViewPrefs.descMax - ViewPrefs.descMin).round(),
            onChanged: (x) => s.setView(v.copyWith(descSize: x.roundToDouble())),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
          child: Text('Example: the duct crosses the steel beam above the corridor ceiling.',
              style: TextStyle(fontSize: v.descSize, height: 1.5, fontWeight: FontWeight.w500, color: c.ink)),
        ),
        row(
          'Item card color',
          v.cardTint == 0 ? 'Off' : '${(v.cardTint * 100).round()}%',
          Slider(
            value: v.cardTint,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (x) => s.setView(v.copyWith(cardTint: x)),
          ),
          hint: 'How strongly the priority color fills the item cards in the list.',
        ),
        const SizedBox(height: 10),
        Text('Panel widths', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        Text('Drag the edge between any two panels (sidebar, item list, item page, facts column, schedule task names). '
            'Double-click an edge to put it back.',
            style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => s.setView(v.resetPanels().copyWith(photoShare: 0.5, descSize: 17, cardTint: 0.5, dayW: 0)),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset all sizes'),
          ),
        ),
      ]),
    );
  }
}
