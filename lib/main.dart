import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers/app_providers.dart';
import 'features/admin/screens/admin_main_layout.dart';
import 'features/guru/screens/login_screen.dart';
import 'features/guru/screens/main_layout.dart';
import 'features/guru/screens/native_role_selection_screen.dart';
import 'features/web_auth/providers/web_session_provider.dart';
import 'features/web_auth/screens/web_change_password_screen.dart';
import 'features/web_auth/data/web_auth_models.dart';
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
    final webSession = ref.watch(webSessionProvider);

    void signOutTeacher() {
      ref.read(sessionProvider.notifier).signOut();
    }

    void signOutWeb() {
      ref.read(webSessionProvider.notifier).signOut();
    }

    // Keep the existing teacher flow authoritative when both session families
    // observe the shared token storage, as WebShell does for the website.
    if (status == AuthStatus.mustChangePassword) {
      return ChangePasswordScreen(onSignOut: signOutTeacher);
    }
    if (status == AuthStatus.signedIn) return const MainLayout();

    if (webSession.status == WebAuthStatus.mustChangePassword) {
      return const WebChangePasswordScreen();
    }
    if (webSession.status == WebAuthStatus.signedIn &&
        webSession.role == WebRole.admin) {
      return AdminMainLayout(onLogout: signOutWeb);
    }

    if (status == AuthStatus.signedOut && boot.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const NativeRoleSelectionScreen();
  }
}
