import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/sidebar_parts.dart';
import '../../guru/screens/login_screen.dart';
import '../../website/screens/website_main_layout.dart';
import '../../website/widgets/website_common.dart';
import '../data/web_auth_models.dart';
import '../navigation/web_auth_navigation.dart';

class WebRoleSelectionScreen extends StatelessWidget {
  const WebRoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrow(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: narrow ? 28 : 56),
          child: WebContainer(
            maxWidth: 1080,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SidebarLogo(
                  title: 'SDN 02 Pakunden',
                  subtitle: 'Sistem informasi sekolah',
                ),
                SizedBox(height: narrow ? 36 : 64),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        Text(
                          'Pilih aplikasi',
                          textAlign: TextAlign.center,
                          style: context.webH1,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Pilih akses yang ingin Anda buka untuk melanjutkan.',
                          textAlign: TextAlign.center,
                          style: context.webBody.copyWith(
                            color: context.colors.sl,
                          ),
                        ),
                        SizedBox(height: narrow ? 28 : 36),
                        _RoleGrid(),
                        const SizedBox(height: 28),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WebsiteMainLayout(),
                            ),
                          ),
                          icon: const Icon(Icons.public_outlined, size: 18),
                          label: const Text('Website Sekolah'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleGrid extends StatelessWidget {
  const _RoleGrid();

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 250,
      gap: 14,
      children: const [
        _RoleCard(
          icon: Icons.menu_book_outlined,
          title: 'Guru Mapel',
          description:
              'Kelola pembelajaran, penilaian, dan aktivitas mengajar.',
          role: TeacherRole.guruMapel,
        ),
        _RoleCard(
          icon: Icons.groups_outlined,
          title: 'Wali Kelas',
          description: 'Pantau kelas dan perkembangan siswa yang diampu.',
          role: TeacherRole.waliKelas,
        ),
        _RoleCard(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin',
          description: 'Kelola data sekolah, akun, dan konfigurasi sistem.',
          webRole: WebRole.admin,
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
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

  void _open(BuildContext context) {
    if (webRole != null) {
      openWebLogin(context, webRole!, returnLabel: 'Kembali ke Pilihan Role');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          initialRole: role!,
          allowRoleSwitch: false,
          onAuthenticated: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomCard(
      margin: EdgeInsets.zero,
      onTap: () => _open(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: c.primary, size: 24),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: Text(title, style: context.styleH2)),
              Icon(Icons.arrow_forward_rounded, color: c.primary, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: context.webSmallMuted),
        ],
      ),
    );
  }
}
