import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'project_setup_screen.dart';

/// Logo, app name and a narrow column for the sign-in steps.
class AuthFrame extends StatelessWidget {
  const AuthFrame({super.key, required this.children, this.trailing});
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const BrandLogo(full: true, height: 34),
                  const Spacer(),
                  if (trailing != null) trailing!,
                ]),
                const SizedBox(height: 10),
                AppWordmark(size: 17, color: c.accentText),
                const SizedBox(height: 40),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeStep = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _email.text = context.read<AppState>().settings.lastEmail;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _run(Future<void> Function(AppState s) action) async {
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _emailText => _email.text.trim();

  Future<void> _send() => _run((s) async {
        if (!_emailText.contains('@') || !_emailText.contains('.')) {
          throw Exception('Enter your work email.');
        }
        await s.sendCode(_emailText);
        if (!mounted) return;
        setState(() {
          _codeStep = true;
          _code.clear();
        });
        _startCooldown();
      });

  Future<void> _verify() => _run((s) async {
        final input = _code.text.trim();
        if (input.contains('://')) {
          await s.verifyLink(input);
        } else {
          final code = input.replaceAll(RegExp(r'\s'), '');
          if (code.length < 6) throw Exception('Enter the 6-digit code from the email.');
          await s.verifyCode(_emailText, code);
        }
      });

  Widget _button(String label, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final error = _error?.replaceFirst('Exception: ', '');
    return AuthFrame(children: [
      if (!_codeStep) ...[
        Text('Sign in', style: condensed(34, color: c.ink)),
        const SizedBox(height: 8),
        Text('No password needed. We email you a 6-digit code.', style: TextStyle(fontSize: 16, color: c.ink2, height: 1.4)),
        const SizedBox(height: 24),
        const FieldLabel('Work email'),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(hintText: 'name@company.com'),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 16),
        _button('Email me a code', _send),
        const SizedBox(height: 20),
        Panel(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.group_add_outlined, color: c.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'New here? The same code creates your account. The Christman admin approves every new account '
                'and adds you to your projects.',
                style: TextStyle(fontSize: 14, color: c.ink2, height: 1.4),
              ),
            ),
          ]),
        ),
      ] else ...[
        Text('Check your email', style: condensed(34, color: c.ink)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(style: TextStyle(fontSize: 16, color: c.ink2, height: 1.4), children: [
            const TextSpan(text: 'We sent a 6-digit code to '),
            TextSpan(text: _emailText, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: '. Type it below, or tap the button in the email. Check your junk folder too.'),
          ]),
        ),
        const SizedBox(height: 24),
        const FieldLabel('Sign-in code'),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\n'))],
          textAlign: TextAlign.center,
          style: condensed(30, color: c.ink, letterSpacing: 8),
          decoration: const InputDecoration(hintText: '• • • • • •'),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 16),
        _button('Sign In', _verify),
        const SizedBox(height: 10),
        Row(children: [
          Text(_cooldown > 0 ? 'Resend code in 0:${_cooldown.toString().padLeft(2, '0')}' : '',
              style: TextStyle(color: c.muted, fontSize: 14)),
          const Spacer(),
          if (_cooldown == 0) TextButton(onPressed: _busy ? null : _send, child: const Text('Send a new code')),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _codeStep = false),
            child: const Text('Use another email'),
          ),
        ]),
      ],
      if (error != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.urgentBg, borderRadius: BorderRadius.circular(10)),
          child: Text(error, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}

/// First sign-in: name, company and phone.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _company.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name and company.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().updateMyDetails(name: _name.text, company: _company.text, phone: _phone.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return AuthFrame(
      trailing: TextButton(onPressed: () => context.read<AppState>().signOut(), child: const Text('Sign out')),
      children: [
        Text('Welcome', style: condensed(34, color: c.ink)),
        const SizedBox(height: 8),
        Text('Tell the team who you are. Your company shows next to your name.',
            style: TextStyle(fontSize: 16, color: c.ink2, height: 1.4)),
        const SizedBox(height: 24),
        const FieldLabel('Full name'),
        TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words),
        const SizedBox(height: 12),
        const FieldLabel('Company', hint: 'e.g. Hart Mechanical'),
        TextField(controller: _company, textCapitalization: TextCapitalization.words),
        const SizedBox(height: 12),
        const FieldLabel('Phone', hint: 'optional'),
        TextField(controller: _phone, keyboardType: TextInputType.phone, onSubmitted: (_) => _save()),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Continue'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: c.urgentText, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class WaitingScreen extends StatefulWidget {
  const WaitingScreen({super.key});

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final s = context.watch<AppState>();
    return AuthFrame(
      trailing: TextButton(onPressed: () => s.signOut(), child: const Text('Sign out')),
      children: [
        Icon(Icons.hourglass_top_rounded, size: 40, color: c.accentText),
        const SizedBox(height: 12),
        Text('Waiting for approval', style: condensed(34, color: c.ink)),
        const SizedBox(height: 8),
        Text(
          'Thanks, ${s.me?.name ?? ''}. The Christman admin has been told about your account. '
          'Once you are approved and added to a project, it opens here.',
          style: TextStyle(fontSize: 16, color: c.ink2, height: 1.45),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await s.refreshMe();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Check again'),
        ),
      ],
    );
  }
}

class RemovedScreen extends StatelessWidget {
  const RemovedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    return AuthFrame(children: [
      Text('Access removed', style: condensed(34, color: c.ink)),
      const SizedBox(height: 8),
      Text('This account no longer has access. Contact the Christman VDC team if this is a mistake.',
          style: TextStyle(fontSize: 16, color: c.ink2, height: 1.45)),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => context.read<AppState>().signOut(), child: const Text('Sign out')),
    ]);
  }
}

/// Approved, but not on any project yet. The admin can create the first project here.
class NoProjectScreen extends StatelessWidget {
  const NoProjectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = CwColors.of(context);
    final s = context.watch<AppState>();
    return AuthFrame(
      trailing: TextButton(onPressed: () => s.signOut(), child: const Text('Sign out')),
      children: s.isAdmin
          ? [
              Text('Create your first project', style: condensed(34, color: c.ink)),
              const SizedBox(height: 8),
              Text(
                'Give it a name and a short abbreviation. The abbreviation starts every item number, e.g. NMC-CL-001. '
                'Standard trades and item types are added for you; you can change them later.',
                style: TextStyle(fontSize: 16, color: c.ink2, height: 1.45),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showNewProjectDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('New project'),
              ),
            ]
          : [
              Text('No project yet', style: condensed(34, color: c.ink)),
              const SizedBox(height: 8),
              Text('Your account is approved, but you are not on a project yet. The Christman admin adds you to your projects.',
                  style: TextStyle(fontSize: 16, color: c.ink2, height: 1.45)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => s.refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            ],
    );
  }
}
