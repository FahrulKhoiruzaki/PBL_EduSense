import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../actions/account_actions.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_common.dart';
import '../../../core/theme.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final log = ref.watch(adminDatasetProvider.select((d) => d.log));
    final nav = ref.read(activeMenuProvider.notifier);

    final summary = <(String, int, VoidCallback)>[
      ('Siswa', stats.students, () => nav.select(AdminMenu.akun, tab: AccountType.siswa)),
      ('Guru', stats.teachers, () => nav.select(AdminMenu.akun, tab: AccountType.guru)),
      ('Kelas', stats.classes, () => nav.select(AdminMenu.kelas)),
      ('Akun aktif', stats.activeAccounts, () => nav.select(AdminMenu.akun)),
      (
        'Akun nonaktif',
        stats.inactiveAccounts,
        () => nav.select(AdminMenu.akun, status: StatusFilter.off),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Dashboard', style: context.styleH1.copyWith(fontSize: 30, height: 36 / 30)),
        ),
        ResponsiveGrid(
          minItemWidth: 190,
          children: [
            for (final (label, value, onTap) in summary)
              CustomCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(18),
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kick(label),
                    Text('$value', style: context.styleBig.copyWith(fontSize: 34, height: 38 / 34)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        ResponsiveGrid(
          minItemWidth: 300,
          children: [
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Kick('Perlu tindakan'),
                  RowList(
                    children: [
                      NavRow(
                        title: '${stats.classesWithoutWali} kelas belum punya wali kelas',
                        onTap: () => nav.select(AdminMenu.kelas, classFilter: ClassFilter.noWali),
                      ),
                      NavRow(
                        title: '${stats.inactiveAccounts} akun nonaktif',
                        onTap: () => nav.select(
                          AdminMenu.akun,
                          tab: AccountType.guru,
                          status: StatusFilter.off,
                        ),
                      ),
                      NavRow(
                        title: '${stats.unassignedTeachers} guru belum ditugaskan',
                        onTap: () => nav.select(AdminMenu.akun, tab: AccountType.guru),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Kick('Aksi cepat'),
                  CustomButton(
                    label: '+ Tambah Akun',
                    expanded: true,
                    onPressed: () {
                      nav.select(AdminMenu.akun, tab: AccountType.guru);
                      startAddAccount(context, AccountType.guru);
                    },
                  ),
                  const SizedBox(height: 8),
                  CustomButton(
                    label: 'Pindahkan Siswa / Atur Kelas',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => nav.select(AdminMenu.kelas),
                  ),
                  const SizedBox(height: 8),
                  CustomButton(
                    label: 'Kelola Akun Orang Tua',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => nav.select(AdminMenu.akun, tab: AccountType.siswa),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Kick('Aktivitas terbaru', bottom: 0),
                  LinkText('Lihat semua', onTap: () => nav.select(AdminMenu.log)),
                ],
              ),
              const SizedBox(height: 6),
              RowList(children: [for (final entry in log.take(6)) LogRow(entry)]),
            ],
          ),
        ),
      ],
    );
  }
}
