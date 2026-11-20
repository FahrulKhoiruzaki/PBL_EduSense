import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../web_auth/data/web_auth_models.dart';
import '../../web_auth/screens/web_login_screen.dart';
import 'login_screen.dart';

/// Entry point for the native app when no account is signed in.
///
/// The public website has its own selector and remains unchanged. This screen
/// deliberately exposes only the roles available in the native app entry.
class NativeRoleSelectionScreen extends StatelessWidget {
  const NativeRoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? c.fo : const Color(0xFFF3F4F6),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              // Center on tall screens; allow natural scrolling when the
              // viewport is short or accessibility text needs more room.
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 374),
                  child: TweenAnimationBuilder<double>(
                    key: const ValueKey('native-launcher-entrance'),
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (_, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _NativeLogo(),
                        const SizedBox(height: 24),
                        const _RoleCard(
                          icon: Icons.menu_book_outlined,
                          title: 'Guru Mapel',
                          description: 'Presensi, pembelajaran, penilaian, dan aktivitas mengajar.',
                          role: TeacherRole.guruMapel,
                        ),
                        const SizedBox(height: 10),
                        const _RoleCard(
                          icon: Icons.groups_outlined,
                          title: 'Wali Kelas',
                          description: 'Pantau kelas, kehadiran, dan perkembangan siswa.',
                          role: TeacherRole.waliKelas,
                        ),
                        const SizedBox(height: 10),
                        const _RoleCard(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Admin',
                          description: 'Kelola data sekolah, akun, dan konfigurasi sistem.',
                          webRole: WebRole.admin,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 12, color: c.st),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Akses Orang Tua tersedia melalui Website Sekolah.',
                                textAlign: TextAlign.center,
                                style: context.styleCaption.copyWith(
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeLogo extends StatelessWidget {
  const _NativeLogo();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '02',
            style: context.styleH2.copyWith(color: c.onPrimary, fontSize: 22),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'SDN 02 Pakunden',
          textAlign: TextAlign.center,
          style: context.styleH2.copyWith(fontSize: 21, height: 1.3),
        ),
        const SizedBox(height: 6),
        Text(
          'Pilih aplikasi yang ingin dibuka',
          textAlign: TextAlign.center,
          style: context.styleMuted.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    this.role,
    this.webRole,
  }) : assert((role == null) != (webRole == null));

  final IconData icon;
  final String title;
  final String description;
  final TeacherRole? role;
  final WebRole? webRole;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _open(BuildContext context) {
    final Widget destination;
    if (widget.webRole != null) {
      destination = WebLoginScreen(
        role: widget.webRole!,
        returnLabel: 'Kembali ke Pilihan Role',
      );
    } else {
      destination = LoginScreen(
        initialRole: widget.role!,
        allowRoleSwitch: false,
        onAuthenticated: () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 230),
        pageBuilder: (_, animation, _) => destination,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final entering = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: entering,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.035, 0),
                end: Offset.zero,
              ).animate(entering),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(18);
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: c.mi.withValues(alpha: 0.65)),
    );
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.description}',
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0629272D),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: isDark ? c.su : Colors.white,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              onHighlightChanged: _setPressed,
              customBorder: shape,
              hoverColor: c.ink.withValues(alpha: 0.025),
              highlightColor: c.primary.withValues(alpha: 0.06),
              splashColor: c.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.primarySoft,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(widget.icon, color: c.primary, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: context.styleH2.copyWith(
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.styleCaption.copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, color: c.st, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
