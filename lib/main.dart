import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers/app_providers.dart';
import 'features/guru/screens/login_screen.dart';
import 'features/guru/screens/main_layout.dart';
import 'widgets/app_overlays.dart';

void main() {
  runApp(const ProviderScope(child: AplikasiGuruApp()));
}

class AplikasiGuruApp extends StatelessWidget {
  const AplikasiGuruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplikasi Guru · SDN 02 Pakunden',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: (context, child) => ColoredBox(
        color: context.colors.bg,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: child,
          ),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(sessionBootstrapProvider);
    final status = ref.watch(sessionProvider.select((s) => s.status));

    if (status == AuthStatus.signedOut && boot.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return switch (status) {
      AuthStatus.signedOut => const LoginScreen(),
      AuthStatus.mustChangePassword => const ChangePasswordScreen(),
      AuthStatus.signedIn => const MainLayout(),
    };
  }
}
