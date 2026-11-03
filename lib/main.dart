import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/api.dart';
import 'screens/shell.dart';
import 'screens/sign_in_screen.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  Api? api;
  String? error;
  try {
    api = await Api.connect();
  } catch (e) {
    error = 'Could not start the connection to the server: $e';
  }
  if (api == null) {
    runApp(_StartupError(error ?? 'Unknown error'));
    return;
  }
  final state = AppState(api, settings);
  runApp(ChangeNotifierProvider.value(value: state..init(), child: const CoordinationApp()));
}

class CoordinationApp extends StatelessWidget {
  const CoordinationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    final font = context.select<AppState, String>((s) => s.fontChoice);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, font: font),
      darkTheme: buildTheme(Brightness.dark, font: font),
      themeMode: mode,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.booting) {
      return const Scaffold(body: Center(child: BrandLogo(full: true, height: 44)));
    }
    final me = state.me;
    if (me == null) return const SignInScreen();
    if (me.needsDetails) return const DetailsScreen();
    if (me.isPending) return const WaitingScreen();
    if (me.isRemoved) return const RemovedScreen();
    if (state.projects.isEmpty) return const NoProjectScreen();
    return const Shell();
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not start', body: message),
        ),
      );
}
