import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../../../widgets/app_overlays.dart';
import '../../admin/providers/admin_providers.dart' as admin;
import '../../admin/screens/admin_main_layout.dart';
import '../../guru/screens/login_screen.dart';
import '../../guru/screens/main_layout.dart';
import '../../orang_tua/providers/parent_providers.dart' as parent;
import '../../orang_tua/screens/parent_main_layout.dart';
import '../data/web_auth_models.dart';
import '../providers/web_session_provider.dart';
import 'web_change_password_screen.dart';
import 'web_role_selection_screen.dart';

/// Memastikan data milik pengguna sebelumnya tidak terbawa ke sesi berikutnya.
void _resetUserScopedState(WidgetRef ref) {
  ref.invalidate(parent.anakListProvider);
  ref.invalidate(parent.parentNotificationsProvider);
  ref.invalidate(parent.selectedKidIndexProvider);
  ref.invalidate(parent.activeTabProvider);
  ref.invalidate(parent.subPageProvider);
  ref.invalidate(parent.selectedGradeIdProvider);
  ref.invalidate(parent.statsPeriodProvider);
  ref.invalidate(parent.attendanceMonthProvider);
  ref.invalidate(parent.attendanceDayProvider);
  ref.invalidate(parent.attendanceStatusFilterProvider);
  ref.invalidate(parent.gradeCategoryFilterProvider);
  ref.invalidate(parent.gradeQueryProvider);
  ref.invalidate(parent.historyFilterProvider);

  ref.invalidate(admin.adminDataProvider);
  ref.invalidate(admin.adminProfileProvider);
  ref.invalidate(admin.activeMenuProvider);
  ref.invalidate(admin.accountTabProvider);
  ref.read(admin.activeMenuProvider.notifier).resetView();
}

class WebShell extends ConsumerWidget {
  const WebShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(webSessionProvider.select((s) => s.user?.id), (previous, next) {
      if (previous == next) return;
      if (next != null) {
        _resetUserScopedState(ref);
      } else {
        // Layout pengguna lama masih menonton provider; reset setelah ia dilepas
        // agar tidak memicu request baru tanpa token.
        WidgetsBinding.instance.addPostFrameCallback((_) => _resetUserScopedState(ref));
      }
    });
    ref.listen(webSessionProvider.select((s) => s.notice), (_, notice) {
      if (notice != null) AppToast.show(notice);
    });
    ref.listen(sessionProvider.select((s) => s.user?.id), (previous, next) {
      if (previous == next) return;
      if (next != null) {
        _resetUserScopedState(ref);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _resetUserScopedState(ref));
      }
    });
    ref.listen(sessionProvider.select((s) => s.notice), (_, notice) {
      if (notice != null) AppToast.show(notice);
    });

    final session = ref.watch(webSessionProvider);
    final teacherSession = ref.watch(sessionProvider);
    void logout() {
      ref.read(webSessionProvider.notifier).signOut();
    }
    void teacherLogout() {
      ref.read(sessionProvider.notifier).signOut();
    }

    // Teacher authentication is intentionally checked first. The selector only
    // allows one provider flow at a time, and this deterministic precedence also
    // prevents a stale web layout from remaining visible after teacher sign-in.
    if (teacherSession.status == AuthStatus.mustChangePassword) {
      return ChangePasswordScreen(onSignOut: teacherLogout);
    }
    if (teacherSession.status == AuthStatus.signedIn) {
      return const MainLayout();
    }

    return switch (session.status) {
      WebAuthStatus.signedOut => const WebRoleSelectionScreen(),
      WebAuthStatus.mustChangePassword => const WebChangePasswordScreen(),
      WebAuthStatus.signedIn => session.role == WebRole.admin
          ? AdminMainLayout(onLogout: logout)
          : ParentMainLayout(onLogout: logout),
    };
  }
}
