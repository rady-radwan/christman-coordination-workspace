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
    final look = context.select<AppState, Appearance>((s) => s.appearance);
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, look),
      darkTheme: buildTheme(Brightness.dark, look),
      themeMode: look.mode,
      // Each person's text size, on top of the size set in Windows / on the phone.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final system = mq.textScaler.scale(1).clamp(0.8, 1.6).toDouble();
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(system * look.textScale)), child: child!);
      },
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
        theme: buildTheme(Brightness.light, const Appearance()),
        home: Scaffold(
          body: EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not start', body: message),
        ),
      );
}
