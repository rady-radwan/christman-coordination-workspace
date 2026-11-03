import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/update_check.dart';
import 'common.dart';

/// Downloads and installs the new version (Windows), or opens the download link (phones).
Future<void> installUpdate(BuildContext context, AppRelease r) async {
  final url = r.url;
  if (url == null) {
    showInfo(context, 'There is no download for this device yet.');
    return;
  }
  if (!Platform.isWindows) {
    final ok = await openDownloadLink(url);
    if (!ok && context.mounted) showInfo(context, 'Could not open the link. Copy it from the update message instead.');
    return;
  }
  final progress = ValueNotifier<double>(0);
  var failed = false;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('Downloading version ${r.version}'),
      content: SizedBox(
        width: 380,
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LinearProgressIndicator(value: v > 0 ? v : null),
            const SizedBox(height: 10),
            Text(v >= 1 ? 'Starting the installer… the app will close.' : '${(v * 100).round()}%'),
          ]),
        ),
      ),
    ),
  ));
  try {
    await downloadAndStartInstaller(url, (v) => progress.value = v);
  } catch (e) {
    failed = true;
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showError(context, e);
      await openDownloadLink(url);
    }
  }
  if (!failed) {
    progress.value = 1;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    exit(0);
  }
}

/// The "new version is ready" message with what's new and the download button.
Future<void> showUpdateDialog(BuildContext context, AppRelease r) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final c = CwColors.of(ctx);
      final url = r.url;
      return AlertDialog(
        icon: Icon(Icons.system_update_alt, color: c.accent, size: 36),
        title: Text('Version ${r.version} is ready'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('You have version $appVersion.', textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
              if (r.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text("WHAT'S NEW", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.accentText)),
                const SizedBox(height: 6),
                for (final n in r.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 6, color: c.accent)),
                      Expanded(child: Text(n, style: const TextStyle(fontSize: 14, height: 1.35))),
                    ]),
                  ),
              ],
              if (url != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: SelectableText(url, style: TextStyle(fontSize: 11.5, color: c.muted))),
                  IconButton(
                    tooltip: 'Copy link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      showInfo(ctx, 'Download link copied');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ]),
              ],
              if (Platform.isAndroid && r.androidOlderUrl != null)
                Text('Older phone? If the app does not install, use the "older phones" download from the same page.', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          if (url != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                installUpdate(context, r);
              },
              icon: const Icon(Icons.download, size: 18),
              label: Text(Platform.isWindows ? 'Update now' : 'Download'),
            ),
        ],
      );
    },
  );
}

/// A strip at the top of the app while a newer version is available.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.update;
    if (r == null || s.updateHidden) return const SizedBox.shrink();
    final c = CwColors.of(context);
    return Material(
      color: c.accent,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(children: [
            Icon(Icons.system_update_alt, color: c.accentInk, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => showUpdateDialog(context, r),
                child: Text(
                  'A new version ($appVersion → ${r.version}) is ready.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.accentInk, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (isWide(context))
              TextButton(
              onPressed: () => showUpdateDialog(context, r),
              style: TextButton.styleFrom(foregroundColor: c.accentInk),
              child: const Text("What's new"),
            ),
            FilledButton(
              onPressed: () => installUpdate(context, r),
              style: FilledButton.styleFrom(backgroundColor: c.accentInk, foregroundColor: c.accent),
              child: Text(Platform.isWindows ? 'Update now' : 'Download'),
            ),
            IconButton(tooltip: 'Later', onPressed: s.hideUpdate, icon: Icon(Icons.close, color: c.accentInk, size: 20)),
          ]),
      ),
    );
  }
}

/// Shows the update message once per new version, as soon as it is found.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({super.key, required this.child});
  final Widget child;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<AppState>();
    final r = s.update;
    if (r == null || r.version == _asked || s.settings.updateShown == r.version) return;
    _asked = r.version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(s.settings.setUpdateShown(r.version));
      showUpdateDialog(context, r);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The update, pinned at the top of the Notifications list.
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final r = s.update;
    if (r == null) return const SizedBox.shrink();
    final c = CwColors.of(context);
    return Material(
      color: c.accentSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.accent)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showUpdateDialog(context, r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.system_update_alt, color: c.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New version ${r.version} is ready', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.ink)),
                Text(r.notes.isEmpty ? 'Tap to see what is new and download it.' : r.notes.take(2).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink2)),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => installUpdate(context, r), child: Text(Platform.isWindows ? 'Update now' : 'Download')),
          ]),
        ),
      ),
    );
  }
}
