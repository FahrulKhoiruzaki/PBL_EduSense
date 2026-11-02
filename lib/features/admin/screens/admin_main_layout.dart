import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/status_badge.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_dialogs.dart';
import 'account_management_screen.dart';
import 'activity_log_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_settings_screen.dart';
import 'class_management_screen.dart';
import 'cms_faq_contact_screen.dart';
import 'cms_facilities_activities_screen.dart';
import 'cms_home_text_screen.dart';
import 'cms_posts_screen.dart';
import 'calendar_admin_screen.dart';
import 'class_info_admin_screen.dart';

const _desktopBreakpoint = 900.0;

/// Lebar maksimum konten halaman admin; konten di dalamnya rata kiri.
const adminContentMaxWidth = 1100.0;

class AdminMainLayout extends ConsumerWidget {
  const AdminMainLayout({super.key, this.onLogout});

  final VoidCallback? onLogout;

  void _confirmLogout(BuildContext context) {
    showAdminConfirm(
      adminDialogContext(context),
      title: 'Apakah Anda yakin ingin keluar?',
      description: 'Anda perlu masuk kembali untuk membuka panel admin.',
      confirmLabel: 'Keluar',
      onConfirm: () {
        AppToast.show('Anda telah keluar');
        onLogout?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(activeMenuProvider);

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > _desktopBreakpoint;

        Widget sidebar({required bool inDrawer}) => AdminSidebar(
          active: menu,
          onSelect: (m) {
            if (inDrawer) Navigator.of(context).pop();
            ref.read(activeMenuProvider.notifier).select(m);
          },
          onLogout: () {
            if (inDrawer) Navigator.of(context).pop();
            _confirmLogout(context);
          },
        );

        return Scaffold(
          drawer: wide ? null : Drawer(width: 270, child: SafeArea(child: sidebar(inDrawer: true))),
          body: wide
              ? Row(
                  // Tanpa stretch, Row memusatkan konten secara vertikal (bawaannya center).
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 240, child: sidebar(inDrawer: false)),
                    const Expanded(child: _AdminContent(wide: true)),
                  ],
                )
              : const SafeArea(
                  child: Column(
                    children: [
                      _NarrowBar(),
                      Expanded(child: _AdminContent(wide: false)),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class AdminSidebar extends StatefulWidget {
  const AdminSidebar({
    super.key,
    required this.active,
    required this.onSelect,
    required this.onLogout,
  });

  final AdminMenu active;
  final ValueChanged<AdminMenu> onSelect;
  final VoidCallback onLogout;

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  late bool _websiteOpen = widget.active.website;

  @override
  void didUpdateWidget(AdminSidebar old) {
    super.didUpdateWidget(old);
    // Berpindah ke layar website dari mana pun (mis. lewat tautan) membuka grupnya.
    if (widget.active.website && !old.active.website) _websiteOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = widget.active;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.su,
        border: Border(right: BorderSide(color: c.mi)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 16), child: _Logo()),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in AdminMenu.values.where((m) => !m.website && !m.hidden))
                      _SidebarItem(
                        label: m.label,
                        icon: m.icon,
                        selected: m == active,
                        onTap: () => widget.onSelect(m),
                      ),
                    const SizedBox(height: 6),
                    _SidebarGroup(
                      label: 'Kelola Website',
                      expanded: _websiteOpen,
                      containsActive: active.website,
                      onToggle: () => setState(() => _websiteOpen = !_websiteOpen),
                      children: [
                        for (final m in AdminMenu.values.where((m) => m.website))
                          _SidebarItem(
                            label: m.label,
                            icon: m.icon,
                            selected: m == active,
                            indent: 12,
                            iconSize: 18,
                            onTap: () => widget.onSelect(m),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SidebarItem(
              label: 'Keluar',
              icon: Icons.logout,
              selected: false,
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

/// Item menu yang membuka/menutup daftar sub-menu di bawahnya.
class _SidebarGroup extends StatelessWidget {
  const _SidebarGroup({
    required this.label,
    required this.expanded,
    required this.containsActive,
    required this.onToggle,
    required this.children,
  });

  final String label;
  final bool expanded;

  /// Sub-menu yang aktif sedang tersembunyi: header diberi penanda agar posisi tetap terbaca.
  final bool containsActive;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final marked = containsActive && !expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Semantics(
            button: true,
            expanded: expanded,
            label: label,
            child: Material(
              color: marked ? c.mi : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.language, size: 20, color: containsActive ? c.ink : c.sl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: context.styleMedium.copyWith(
                              color: containsActive ? c.ink : c.sl,
                              fontWeight: containsActive ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.keyboard_arrow_down, size: 20, color: c.sl),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment(-0.34, -0.94),
              end: Alignment(0.34, 0.94),
              colors: [AppColors.darkCardStart, AppColors.darkCardEnd],
            ),
          ),
          child: Text(
            '02',
            style: context.styleBadge.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.onDarkCard,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Panel Admin', style: context.styleBold),
              Text('SDN 02 Pakunden', style: context.styleCaption),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.indent = 0,
    this.iconSize = 20,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Geser ke kanan untuk sub-menu.
  final double indent;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = selected ? c.su : c.sl;
    return Padding(
      padding: EdgeInsets.only(bottom: 2, left: indent),
      child: Material(
        color: selected ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: iconSize, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: context.styleMedium.copyWith(color: foreground)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NarrowBar extends ConsumerWidget {
  const _NarrowBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final menu = ref.watch(activeMenuProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.su,
        border: Border(bottom: BorderSide(color: c.mi)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Buka menu',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            Expanded(child: Text(menu.label, style: context.styleBold)),
            IconButton(
              tooltip: 'Pengaturan',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => ref.read(activeMenuProvider.notifier).select(AdminMenu.pengaturan),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminContent extends ConsumerWidget {
  const _AdminContent({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(activeMenuProvider);
    final classCode = ref.watch(selectedClassCodeProvider);

    // Layar Kelola Website memuat datanya sendiri; tidak ikut gagal bila dataset akun gagal dimuat.
    final website = switch (menu) {
      AdminMenu.webTeks => const CmsHomeTextScreen(),
      AdminMenu.webBerita => const CmsPostsScreen(),
      AdminMenu.webFasilitas => const CmsFacilitiesActivitiesScreen(),
      AdminMenu.webKelas => const ClassInfoAdminScreen(),
      AdminMenu.webKalender => const CalendarAdminScreen(),
      AdminMenu.webFaq => const CmsFaqContactScreen(),
      _ => null,
    };

    final body = switch (menu) {
      AdminMenu.dashboard => const AdminDashboardScreen(),
      AdminMenu.kelas => const ClassManagementScreen(),
      AdminMenu.akun => const AccountManagementScreen(),
      AdminMenu.log => const ActivityLogScreen(),
      AdminMenu.pengaturan => const AdminSettingsScreen(),
      _ => const SizedBox.shrink(),
    };

    return SingleChildScrollView(
      key: ValueKey('$menu-$classCode'),
      padding: wide
          ? const EdgeInsets.fromLTRB(32, 24, 32, 48)
          : const EdgeInsets.fromLTRB(14, 16, 14, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: adminContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) const _TopBar(),
              website ??
                  AsyncBody<AdminDataset>(
                    value: ref.watch(adminDataProvider),
                    onRetry: () => ref.invalidate(adminDataProvider),
                    loading: Column(children: [for (var i = 0; i < 3; i++) const SkeletonBlock()]),
                    builder: (_) => body,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentAdminProvider)?.name ?? 'Admin';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatFullDate(ref.watch(todayProvider)),
              style: context.styleCaption.copyWith(fontSize: 13),
            ),
          ),
          StatusBadge(label: name),
          const SizedBox(width: 8),
          Avatar(name: name),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: () => ref.read(activeMenuProvider.notifier).select(AdminMenu.pengaturan),
          ),
        ],
      ),
    );
  }
}

/// Ikon menu dipisah dari enum agar lapisan state tidak bergantung pada widget.
extension AdminMenuIcon on AdminMenu {
  IconData get icon => switch (this) {
    AdminMenu.dashboard => Icons.dashboard_outlined,
    AdminMenu.kelas => Icons.school_outlined,
    AdminMenu.akun => Icons.people_outline,
    AdminMenu.log => Icons.history,
    AdminMenu.pengaturan => Icons.settings_outlined,
    AdminMenu.webTeks => Icons.edit_note_outlined,
    AdminMenu.webBerita => Icons.newspaper_outlined,
    AdminMenu.webFasilitas => Icons.photo_library_outlined,
    AdminMenu.webKelas => Icons.class_outlined,
    AdminMenu.webKalender => Icons.calendar_month_outlined,
    AdminMenu.webFaq => Icons.help_outline,
  };
}
