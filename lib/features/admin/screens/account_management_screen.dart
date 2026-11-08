import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../actions/account_actions.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_common.dart';

class AccountManagementScreen extends ConsumerWidget {
  const AccountManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(accountTabProvider);
    final data = ref.watch(adminDatasetProvider);
    final status = ref.watch(filterStatusProvider);
    final classFilter = ref.watch(studentClassFilterProvider);
    final accounts = ref.watch(filteredAccountsProvider);
    final page = paginate(accounts, ref.watch(paginationPageProvider), AdminPageSize.accounts);

    void resetPage() => ref.read(paginationPageProvider.notifier).set(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Manajemen Akun',
          action: CustomButton(
            label: '+ Tambah Akun',
            onPressed: () => startAddAccount(context, tab),
          ),
        ),
        AdminChipBar<AccountType>(
          options: [
            (AccountType.guru, 'Guru (${data.guru.length})'),
            (AccountType.siswa, 'Siswa & Orang Tua (${data.siswa.length})'),
            (AccountType.adm, 'Admin (${data.admins.length})'),
          ],
          selected: tab,
          onSelected: ref.read(activeMenuProvider.notifier).selectAccountTab,
        ),
        AdminToolbar(
          search: const AdminSearchField(hint: 'Cari nama atau email'),
          filters: [
            AdminDropdown<StatusFilter>(
              semanticLabel: 'Filter status',
              value: status,
              items: StatusFilter.values,
              itemLabel: (s) => s.label,
              onChanged: (v) {
                ref.read(filterStatusProvider.notifier).set(v);
                resetPage();
              },
            ),
            if (tab == AccountType.siswa)
              AdminDropdown<String>(
                semanticLabel: 'Filter kelas',
                value: classFilter,
                items: ['all', ...data.classCodes],
                itemLabel: (c) => c == 'all' ? 'Semua kelas' : c,
                onChanged: (v) {
                  ref.read(studentClassFilterProvider.notifier).set(v);
                  resetPage();
                },
              ),
          ],
        ),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: accounts.isEmpty
              ? const EmptyState('Akun tidak ditemukan.')
              : Column(
                  children: [
                    _AccountTable(tab: tab, accounts: page.items, data: data),
                    PaginationBar(page: page.page, totalPages: page.totalPages, total: page.total),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AccountTable extends ConsumerWidget {
  const _AccountTable({required this.tab, required this.accounts, required this.data});

  final AccountType tab;
  final List<AdminAccount> accounts;
  final AdminDataset data;

  String _assignmentLabel(Guru g) {
    final a = data.assignmentOf(g.id);
    final mapel = 'Mapel ${a.mapel.length} kelas';
    if (a.wali.isNotEmpty) {
      return 'Wali ${a.wali.join(', ')}${a.mapel.isNotEmpty ? ' · $mapel' : ''}';
    }
    return a.mapel.isNotEmpty ? mapel : 'Belum ditugaskan';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentEmail = ref.watch(currentAdminEmailProvider);
    final isSiswa = tab == AccountType.siswa;

    final columns = [
      AdminColumn(isSiswa ? 'Siswa' : 'Nama', flex: 3),
      if (!isSiswa) const AdminColumn('Email', flex: 3),
      AdminColumn(
        isSiswa
            ? 'Kelas · Orang tua'
            : tab == AccountType.guru
            ? 'Penugasan'
            : 'Peran',
        flex: 3,
      ),
      const AdminColumn('Status', flex: 3),
      const AdminColumn('Aksi', width: 330),
    ];

    List<Widget> row(AdminAccount a) {
      final isSelf = a.email == currentEmail;
      final detail = switch (a) {
        Siswa s => 'Kelas ${s.classCode} · ${s.parentName}',
        Guru g => _assignmentLabel(g),
        _ => 'Administrator',
      };

      return [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.name, style: context.styleBold),
            if (isSiswa) Text(a.email, style: context.styleAdminCaption),
          ],
        ),
        if (!isSiswa) Text(a.email, style: context.styleBody),
        Text(detail, style: context.styleBody),
        AccountStatusBadges(a),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            CustomButton(
              label: 'Edit',
              variant: ButtonVariant.outline,
              compact: true,
              onPressed: () => startEditAccount(context, tab, a.id),
            ),
            CustomButton(
              label: 'Reset',
              variant: ButtonVariant.outline,
              compact: true,
              onPressed: () => startResetPassword(context, tab, a.id),
            ),
            Tooltip(
              message: isSelf ? 'Tidak bisa menonaktifkan akun sendiri' : '',
              child: CustomButton(
                label: a.active ? 'Nonaktifkan' : 'Aktifkan',
                variant: ButtonVariant.outline,
                compact: true,
                onPressed: isSelf ? null : () => startToggleActive(context, tab, a.id),
              ),
            ),
            Tooltip(
              message: isSelf ? 'Tidak bisa menghapus akun sendiri' : '',
              child: CustomButton(
                label: 'Hapus',
                variant: ButtonVariant.danger,
                compact: true,
                onPressed: isSelf ? null : () => startDeleteAccount(context, tab, a.id),
              ),
            ),
          ],
        ),
      ];
    }

    return AdminDataTable(
      columns: columns,
      rows: [for (final a in accounts) row(a)],
      minFlexWidth: 560,
    );
  }
}
