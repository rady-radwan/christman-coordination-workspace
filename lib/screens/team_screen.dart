import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';

/// Project team (name, company, trade, email, role), approvals and member suggestions.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final admin = s.isAdmin;
    final lead = s.myRole == Role.tradeLead;
    final wide = isWide(context);

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        await s.reloadTeam();
        if (context.mounted) showInfo(context, done);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final teamRows = s.members.map((m) => (m, s.person(m.userId))).where((r) => r.$2 != null).toList()
      ..sort((a, b) {
        final ra = Role.projectRoles.indexOf(a.$1.role), rb = Role.projectRoles.indexOf(b.$1.role);
        if (ra != rb) return ra.compareTo(rb);
        return a.$2!.name.toLowerCase().compareTo(b.$2!.name.toLowerCase());
      });
    final suggested = s.invites.where((i) => i.status == 'suggested').toList();
    final invited = s.invites.where((i) => i.status == 'approved').toList();
    final mine = s.invites.where((i) => i.suggestedBy == s.me?.id).toList();

    final children = <Widget>[];

    if (admin && s.pendingPeople.isNotEmpty) {
      children.add(SectionLabel('Waiting for approval · ${s.pendingPeople.length}'));
      children.add(const SizedBox(height: 8));
      for (final p in s.pendingPeople) {
        children.add(_Card(
          title: p.name,
          lines: [p.email, if (p.company.isNotEmpty) p.company, if (p.createdAt != null) 'Signed up ${dayTimeText(p.createdAt!)}'],
          highlight: true,
          actions: [
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Decline ${p.name}?', 'They will not get access. You can approve them later from the Supabase dashboard.', ok: 'Decline', danger: true)) {
                  await run(() => s.api.setProfileStatus(p.id, 'removed'), 'Declined ${p.name}');
                }
              },
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () async {
                final r = await showDialog<_MemberResult>(
                  context: context,
                  builder: (_) => _MemberDialog(title: 'Approve ${p.name}', existingEmail: p.email),
                );
                if (r == null) return;
                await run(() async {
                  await s.api.setProfileStatus(p.id, 'approved');
                  await s.api.setMember(projectId: s.project!.id, userId: p.id, role: r.role, tradeId: r.tradeId);
                }, 'Approved ${p.name} and added to ${s.project!.code}');
              },
              child: const Text('Approve'),
            ),
          ],
        ));
      }
      children.add(const SizedBox(height: 20));
    }

    if (admin && suggested.isNotEmpty) {
      children.add(SectionLabel('Suggested by trade leads · ${suggested.length}'));
      children.add(const SizedBox(height: 8));
      for (final i in suggested) {
        children.add(_Card(
          title: i.name.isEmpty ? i.email : i.name,
          lines: [
            i.email,
            [if (i.company.isNotEmpty) i.company, s.tradeById(i.tradeId)?.name ?? '', i.role.label].where((x) => x.isNotEmpty).join(' · '),
            'Suggested by ${s.person(i.suggestedBy)?.name ?? 'a trade lead'} · ${dayText(i.createdAt)}',
          ],
          highlight: true,
          actions: [
            TextButton(onPressed: () => run(() => s.api.setInviteStatus(i.id, 'rejected'), 'Suggestion rejected'), child: const Text('Reject')),
            FilledButton(onPressed: () => run(() => s.api.setInviteStatus(i.id, 'approved'), 'Approved ${i.email}'), child: const Text('Approve')),
          ],
        ));
      }
      children.add(const SizedBox(height: 20));
    }

    children.add(SectionLabel('Project team · ${teamRows.length}'));
    children.add(const SizedBox(height: 8));
    if (wide) {
      children.add(Container(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.muted),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 60,
            columns: [
              const DataColumn(label: Text('NAME')),
              const DataColumn(label: Text('COMPANY')),
              const DataColumn(label: Text('TRADE')),
              const DataColumn(label: Text('EMAIL')),
              const DataColumn(label: Text('ROLE')),
              if (admin) const DataColumn(label: Text('')),
            ],
            rows: [
              for (final r in teamRows)
                DataRow(cells: [
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    Avatar(initials: r.$2!.initials, size: 32, strong: r.$1.role == Role.coordinator),
                    const SizedBox(width: 10),
                    Text(r.$2!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r.$2!.isAdmin) ...[const SizedBox(width: 6), const Tag('Admin')],
                  ])),
                  DataCell(Text(r.$2!.company)),
                  DataCell(Text(s.tradeById(r.$1.tradeId)?.name ?? '—')),
                  DataCell(SelectableText(r.$2!.email)),
                  DataCell(Text(r.$1.role.label)),
                  if (admin) DataCell(_MemberMenu(member: r.$1, profile: r.$2!, run: run)),
                ]),
            ],
          ),
        ),
      ));
    } else {
      for (final r in teamRows) {
        children.add(_Card(
          title: r.$2!.name,
          lines: [
            [r.$2!.company, s.tradeById(r.$1.tradeId)?.name ?? '', r.$1.role.label].where((x) => x.isNotEmpty).join(' · '),
            r.$2!.email,
          ],
          actions: admin ? [_MemberMenu(member: r.$1, profile: r.$2!, run: run)] : const [],
        ));
      }
    }

    if (admin && invited.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(SectionLabel('Added, not signed in yet · ${invited.length}'));
      children.add(const SizedBox(height: 8));
      for (final i in invited) {
        children.add(_Card(
          title: i.name.isEmpty ? i.email : i.name,
          lines: [
            i.email,
            [if (i.company.isNotEmpty) i.company, s.tradeById(i.tradeId)?.name ?? '', i.role.label].where((x) => x.isNotEmpty).join(' · '),
            'They join the project automatically the first time they sign in.',
          ],
          actions: [
            TextButton(onPressed: () => run(() => s.api.deleteInvite(i.id), 'Removed the invitation'), child: const Text('Cancel invitation')),
          ],
        ));
      }
    }

    if (lead && mine.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(const SectionLabel('My suggestions'));
      children.add(const SizedBox(height: 8));
      for (final i in mine) {
        final status = switch (i.status) {
          'suggested' => 'Waiting for the admin',
          'approved' => 'Approved — they can sign in now',
          'used' => 'Approved and signed in',
          'rejected' => 'Not approved',
          _ => i.status,
        };
        children.add(_Card(title: i.name.isEmpty ? i.email : i.name, lines: [i.email, status]));
      }
    }

    return Column(children: [
      PageHeader(
        title: 'Team',
        actions: [
          if (admin)
            FilledButton.icon(
              onPressed: () async {
                final r = await showDialog<_MemberResult>(context: context, builder: (_) => const _MemberDialog(title: 'Add a person'));
                if (r == null) return;
                await run(
                  () => s.api.invite(projectId: s.project!.id, email: r.email, name: r.name, company: r.company, role: r.role, tradeId: r.tradeId),
                  'Added ${r.email}. They can sign in with their email now.',
                );
              },
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add Person'),
            ),
          if (lead)
            FilledButton.icon(
              onPressed: () async {
                final r = await showDialog<_MemberResult>(
                  context: context,
                  builder: (_) => _MemberDialog(title: 'Suggest a team member', fixedTrade: s.myTradeId),
                );
                if (r == null) return;
                await run(
                  () => s.api.invite(
                      projectId: s.project!.id,
                      email: r.email,
                      name: r.name,
                      company: r.company,
                      role: Role.tradeMember,
                      tradeId: s.myTradeId,
                      suggestion: true),
                  'Sent to the admin for approval',
                );
              },
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Suggest Member'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => s.reloadTeam(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.lines, this.actions = const [], this.highlight = false});
  final String title;
  final List<String> lines;
  final List<Widget> actions;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: highlight ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlight ? c.accent.withValues(alpha: 0.5) : c.line),
        ),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              for (final l in lines.where((l) => l.isNotEmpty)) Text(l, style: TextStyle(fontSize: 13, color: c.ink2)),
            ]),
          ),
          if (actions.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [for (final a in actions) Padding(padding: const EdgeInsets.only(left: 6), child: a)]),
        ]),
      ),
    );
  }
}

class _MemberMenu extends StatelessWidget {
  const _MemberMenu({required this.member, required this.profile, required this.run});
  final Member member;
  final Profile profile;
  final Future<void> Function(Future<void> Function() action, String done) run;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return PopupMenuButton<String>(
      tooltip: 'Change',
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            final r = await showDialog<_MemberResult>(
              context: context,
              builder: (_) => _MemberDialog(
                title: 'Change ${profile.name}',
                existingEmail: profile.email,
                initialRole: member.role,
                initialTrade: member.tradeId,
              ),
            );
            if (r == null) return;
            await run(() => s.api.setMember(projectId: member.projectId, userId: member.userId, role: r.role, tradeId: r.tradeId),
                'Saved ${profile.name}');
          case 'admin':
            await run(() => s.api.setAdmin(profile.id, !profile.isAdmin),
                profile.isAdmin ? '${profile.name} is no longer an admin' : '${profile.name} is now an admin');
          case 'remove':
            if (!context.mounted) return;
            if (await confirm(context, 'Remove ${profile.name} from ${s.project?.code}?',
                'They keep their account but no longer see this project. Their replies stay.',
                ok: 'Remove', danger: true)) {
              await run(() => s.api.removeMember(member.projectId, member.userId), 'Removed ${profile.name}');
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Change role or trade')),
        if (profile.id != s.me?.id)
          PopupMenuItem(value: 'admin', child: Text(profile.isAdmin ? 'Remove admin rights' : 'Make admin (all projects)')),
        if (profile.id != s.me?.id) const PopupMenuItem(value: 'remove', child: Text('Remove from project')),
      ],
    );
  }
}

class _MemberResult {
  _MemberResult({required this.email, required this.name, required this.company, required this.role, this.tradeId});
  final String email;
  final String name;
  final String company;
  final Role role;
  final String? tradeId;
}

/// Add / approve / change a person: email, name, company, role and trade.
class _MemberDialog extends StatefulWidget {
  const _MemberDialog({required this.title, this.existingEmail, this.initialRole, this.initialTrade, this.fixedTrade});
  final String title;

  /// Set when the person already has an account (approve or change).
  final String? existingEmail;
  final Role? initialRole;
  final String? initialTrade;

  /// Trade leads suggest members for their own trade only.
  final String? fixedTrade;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();
  late Role _role = widget.fixedTrade != null ? Role.tradeMember : (widget.initialRole ?? Role.tradeMember);
  late String? _trade = widget.fixedTrade ?? widget.initialTrade;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _company.dispose();
    super.dispose();
  }

  void _ok() {
    final email = widget.existingEmail ?? _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    if (_role.needsTrade && _trade == null) {
      setState(() => _error = 'Pick the trade.');
      return;
    }
    Navigator.pop(
      context,
      _MemberResult(email: email, name: _name.text.trim(), company: _company.text.trim(), role: _role, tradeId: _role.needsTrade ? _trade : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = CwColors.of(context);
    final isNew = widget.existingEmail == null;
    final lead = widget.fixedTrade != null;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (isNew) ...[
              const FieldLabel('Email'),
              TextField(controller: _email, autofocus: true, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              const FieldLabel('Name'),
              TextField(controller: _name, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              const FieldLabel('Company'),
              TextField(controller: _company, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
            ] else
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(widget.existingEmail!, style: TextStyle(color: c.muted))),
            if (!lead) ...[
              FieldLabel('Role on ${s.project?.code ?? 'this project'}'),
              DropdownButtonFormField<Role>(
                initialValue: _role,
                items: Role.projectRoles.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 10),
            ],
            if (_role.needsTrade) ...[
              const FieldLabel('Trade'),
              lead
                  ? Text(s.tradeById(widget.fixedTrade)?.label ?? '', style: const TextStyle(fontWeight: FontWeight.w600))
                  : DropdownButtonFormField<String>(
                      initialValue: _trade,
                      items: s.trades.map((t) => DropdownMenuItem(value: t.id, child: Text(t.label))).toList(),
                      onChanged: (v) => setState(() => _trade = v),
                    ),
            ],
            if (lead)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('The Christman admin approves this person before they can sign in to the project.',
                    style: TextStyle(fontSize: 13, color: c.muted)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: Text(lead ? 'Send Suggestion' : 'Save')),
      ],
    );
  }
}
