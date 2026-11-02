import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/sidebar_parts.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';
import '../widgets/parent_dialogs.dart';
import 'parent_attendance_screen.dart';
import 'parent_dashboard_screen.dart';
import 'parent_grades_screen.dart';
import 'parent_history_screen.dart';
import 'parent_notifications_screen.dart';
import 'parent_profile_screen.dart';
import 'parent_stats_screen.dart';

const _desktopBreakpoint = 900.0;

class ParentMainLayout extends ConsumerWidget {
  const ParentMainLayout({super.key, this.onLogout});

  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(activeTabProvider);
    final subPage = ref.watch(subPageProvider);
    final canGoBack = ref.watch(canGoBackProvider);
    final nav = ref.read(activeTabProvider.notifier);

    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) nav.back();
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth > _desktopBreakpoint;
          final content = _ParentContent(wide: wide, onLogout: onLogout);

          if (wide) {
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 248,
                    child: _ParentSidebar(tab: tab, subPage: subPage, onLogout: onLogout),
                  ),
                  Expanded(child: content),
                ],
              ),
            );
          }

          return Scaffold(
            body: SafeArea(bottom: false, child: content),
            bottomNavigationBar: _ParentBottomBar(
              tab: tab,
              highlightTab: subPage == null,
              onLogout: onLogout,
            ),
          );
        },
      ),
    );
  }
}

class _ParentBottomBar extends ConsumerWidget {
  const _ParentBottomBar({
    required this.tab,
    required this.highlightTab,
    required this.onLogout,
  });

  final ParentTab tab;
  final bool highlightTab;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    const icons = {
      ParentTab.beranda: (Icons.home_outlined, Icons.home),
      ParentTab.nilai: (Icons.grade_outlined, Icons.grade),
      ParentTab.hadir: (Icons.event_available_outlined, Icons.event_available),
      ParentTab.riwayat: (Icons.history, Icons.history),
    };

    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.mi))),
      child: BottomNavigationBar(
        currentIndex: tab.index,
        selectedItemColor: highlightTab ? c.ink : c.st,
        selectedLabelStyle: highlightTab ? null : Theme.of(context).bottomNavigationBarTheme.unselectedLabelStyle,
        onTap: (i) {
          if (i == ParentTab.values.length) {
            showParentMoreSheet(context, onLogout: onLogout);
            return;
          }
          ref.read(activeTabProvider.notifier).openTab(ParentTab.values[i]);
        },
        items: [
          for (final t in ParentTab.values)
            BottomNavigationBarItem(
              icon: Icon(icons[t]!.$1),
              activeIcon: Icon(icons[t]!.$2),
              label: t.label,
            ),
          const BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Lainnya'),
        ],
      ),
    );
  }
}

class _ParentSidebar extends ConsumerWidget {
  const _ParentSidebar({required this.tab, required this.subPage, required this.onLogout});

  final ParentTab tab;
  final ParentSubPage? subPage;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeTabProvider.notifier);

    final items = <(String, bool, VoidCallback)>[
      ('Dashboard', subPage == null && tab == ParentTab.beranda, () => nav.openTab(ParentTab.beranda)),
      ('Profil Anak', subPage == ParentSubPage.profil, () => nav.openSubPage(ParentSubPage.profil)),
      ('Statistik', subPage == ParentSubPage.statistik, () => nav.openSubPage(ParentSubPage.statistik)),
      ('Nilai', subPage == null && tab == ParentTab.nilai, () => nav.openTab(ParentTab.nilai)),
      ('Kehadiran', subPage == null && tab == ParentTab.hadir, () => nav.openTab(ParentTab.hadir)),
      ('Riwayat', subPage == null && tab == ParentTab.riwayat, () => nav.openTab(ParentTab.riwayat)),
    ];

    return SidebarPanel(
      logo: const SidebarLogo(title: 'Portal Orang Tua'),
      top: [
        for (final (label, selected, onTap) in items)
          SidebarItem(label: label, selected: selected, onTap: onTap),
      ],
      bottom: [
        SidebarItem(
          label: 'Notifikasi',
          selected: subPage == ParentSubPage.notifikasi,
          onTap: () => nav.openSubPage(ParentSubPage.notifikasi),
        ),
        SidebarItem(
          label: 'Keluar',
          selected: false,
          onTap: () => showParentLogoutConfirm(context, onLogout: onLogout),
        ),
      ],
    );
  }
}

class _ParentContent extends ConsumerWidget {
  const _ParentContent({required this.wide, required this.onLogout});

  final bool wide;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(activeTabProvider);
    final subPage = ref.watch(subPageProvider);
    final gradeId = ref.watch(selectedGradeIdProvider);

    final Widget body = switch (subPage) {
      ParentSubPage.profil => const ParentProfileScreen(),
      ParentSubPage.statistik => const ParentStatsScreen(),
      ParentSubPage.notifikasi => const ParentNotificationsScreen(),
      null => switch (tab) {
          ParentTab.beranda => const ParentDashboardScreen(),
          ParentTab.nilai => const ParentGradesScreen(),
          ParentTab.hadir => const ParentAttendanceScreen(),
          ParentTab.riwayat => const ParentHistoryScreen(),
        },
    };

    return SingleChildScrollView(
      key: ValueKey('$tab-$subPage-$gradeId'),
      padding: wide
          ? const EdgeInsets.fromLTRB(32, 24, 32, 40)
          : const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(wide: wide, onLogout: onLogout),
              if (subPage == ParentSubPage.notifikasi)
                body
              else
                AsyncBody<List<Anak>>(
                  value: ref.watch(anakListProvider),
                  onRetry: () => ref.invalidate(anakListProvider),
                  loading: Column(
                    children: [for (var i = 0; i < 3; i++) const SkeletonBlock()],
                  ),
                  builder: (kids) => kids.isEmpty
                      ? const EmptyState('Belum ada data anak yang terhubung dengan akun ini.')
                      : body,
                ),
              const _PrivacyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.wide, required this.onLogout});

  final bool wide;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hasUnread = ref.watch(hasUnreadProvider);

    final bell = IconButton(
      tooltip: 'Notifikasi',
      style: IconButton.styleFrom(
        backgroundColor: c.su,
        shape: CircleBorder(side: BorderSide(color: c.si)),
      ),
      onPressed: () => ref.read(activeTabProvider.notifier).openSubPage(ParentSubPage.notifikasi),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none, size: 22),
          if (hasUnread)
            Positioned(
              top: 0,
              right: 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          if (wide)
            SizedBox(
              width: 220,
              child: Text(formatFullDate(ref.watch(todayProvider)), style: context.styleCaption.copyWith(fontSize: 13)),
            )
          else
            Text(formatFullDate(ref.watch(todayProvider)), style: context.styleCaption.copyWith(fontSize: 13)),
          const KidSelector(),
          bell,
          if (wide)
            _PillButton(
              label: 'Keluar',
              onTap: () => showParentLogoutConfirm(context, onLogout: onLogout),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.su,
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: c.si)),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: context.styleBold.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.mi)),
        ),
        child: Text(
          'Data hanya ditampilkan untuk anak Anda. Klasifikasi adalah alat bantu, bukan penilaian akhir.',
          style: context.styleCaption.copyWith(fontSize: 13),
        ),
      ),
    );
  }
}
