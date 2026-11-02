import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/value_state.dart';
import '../data/admin_models.dart';
import 'admin_data_provider.dart';

export 'admin_data_provider.dart';

enum AdminMenu {
  dashboard('Dashboard'),
  kelas('Struktur Kelas'),
  akun('Manajemen Akun'),
  log('Log Aktivitas'),
  pengaturan('Pengaturan', hidden: true),
  webTeks('Pengaturan Beranda & Teks', website: true),
  webBerita('Kelola Berita & Pengumuman', website: true),
  webFasilitas('Kelola Fasilitas & Kegiatan', website: true),
  webKelas('Informasi Kelas', website: true),
  webKalender('Kalender Akademik', website: true),
  webFaq('Kelola FAQ & Kontak', website: true);

  const AdminMenu(this.label, {this.website = false, this.hidden = false});
  final String label;

  /// Menu di grup "Kelola Website".
  final bool website;

  /// Layar yang tidak tampil di sidebar (dibuka dari bilah atas).
  final bool hidden;
}

enum StatusFilter {
  all('Semua status'),
  on('Aktif'),
  off('Nonaktif');

  const StatusFilter(this.label);
  final String label;
}

enum ClassFilter { all, noWali }

abstract final class AdminPageSize {
  static const accounts = 12;
  static const log = 12;
  static const students = 10;
}

final accountTabProvider = NotifierProvider<ValueState<AccountType>, AccountType>(
  () => ValueState(AccountType.guru),
);

final searchQueryProvider = NotifierProvider<ValueState<String>, String>(() => ValueState(''));

final filterStatusProvider = NotifierProvider<ValueState<StatusFilter>, StatusFilter>(
  () => ValueState(StatusFilter.all),
);

final classFilterProvider = NotifierProvider<ValueState<ClassFilter>, ClassFilter>(
  () => ValueState(ClassFilter.all),
);

final studentClassFilterProvider = NotifierProvider<ValueState<String>, String>(
  () => ValueState('all'),
);

final logTypeFilterProvider = NotifierProvider<ValueState<LogType?>, LogType?>(
  () => ValueState(null),
);

final paginationPageProvider = NotifierProvider<ValueState<int>, int>(() => ValueState(1));

final selectedClassCodeProvider = NotifierProvider<ValueState<String?>, String?>(
  () => ValueState(null),
);

class SelectedStudentsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id, bool selected) {
    state = selected ? {...state, id} : ({...state}..remove(id));
  }

  void setAll(Iterable<String> ids, bool selected) {
    state = selected ? {...state, ...ids} : state.difference(ids.toSet());
  }

  void clear() => state = <String>{};
}

final selectedStudentsProvider =
    NotifierProvider.autoDispose<SelectedStudentsNotifier, Set<String>>(
      SelectedStudentsNotifier.new,
    );

class AdminNavigator extends Notifier<AdminMenu> {
  @override
  AdminMenu build() => AdminMenu.dashboard;

  void resetView() {
    ref.invalidate(searchQueryProvider);
    ref.invalidate(filterStatusProvider);
    ref.invalidate(classFilterProvider);
    ref.invalidate(studentClassFilterProvider);
    ref.invalidate(logTypeFilterProvider);
    ref.invalidate(paginationPageProvider);
    ref.invalidate(selectedStudentsProvider);
    ref.invalidate(selectedClassCodeProvider);
  }

  void select(AdminMenu menu, {AccountType? tab, StatusFilter? status, ClassFilter? classFilter}) {
    resetView();
    if (tab != null) ref.read(accountTabProvider.notifier).set(tab);
    if (status != null) ref.read(filterStatusProvider.notifier).set(status);
    if (classFilter != null) ref.read(classFilterProvider.notifier).set(classFilter);
    state = menu;
  }

  void selectAccountTab(AccountType tab) {
    ref.invalidate(searchQueryProvider);
    ref.invalidate(filterStatusProvider);
    ref.invalidate(studentClassFilterProvider);
    ref.invalidate(paginationPageProvider);
    ref.read(accountTabProvider.notifier).set(tab);
  }

  void openClass(String code) => _showClass(code);

  void closeClass() => _showClass(null);

  void _showClass(String? code) {
    ref.invalidate(searchQueryProvider);
    ref.invalidate(paginationPageProvider);
    ref.invalidate(selectedStudentsProvider);
    ref.read(selectedClassCodeProvider.notifier).set(code);
  }
}

final activeMenuProvider = NotifierProvider<AdminNavigator, AdminMenu>(AdminNavigator.new);

final currentAdminProvider = Provider<AdminUser?>((ref) => ref.watch(adminProfileProvider).value);

final currentAdminEmailProvider = Provider<String?>(
  (ref) => ref.watch(currentAdminProvider)?.email,
);

typedef PageSlice<T> = ({List<T> items, int page, int totalPages, int total});

PageSlice<T> paginate<T>(List<T> all, int requestedPage, int size) {
  final totalPages = math.max(1, (all.length / size).ceil());
  final page = math.min(math.max(requestedPage, 1), totalPages);
  return (
    items: all.skip((page - 1) * size).take(size).toList(),
    page: page,
    totalPages: totalPages,
    total: all.length,
  );
}

final filteredClassesProvider = Provider.autoDispose<List<Kelas>>((ref) {
  final data = ref.watch(adminDatasetProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final filter = ref.watch(classFilterProvider);
  return [
    for (final code in data.classCodes)
      if ((filter == ClassFilter.all || data.classes[code]!.waliId == null) &&
          (code.toLowerCase().contains(query) ||
              (data.guruById(data.classes[code]!.waliId)?.name ?? '').toLowerCase().contains(
                query,
              )))
        data.classes[code]!,
  ];
});

final filteredAccountsProvider = Provider.autoDispose<List<AdminAccount>>((ref) {
  final data = ref.watch(adminDatasetProvider);
  final tab = ref.watch(accountTabProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final status = ref.watch(filterStatusProvider);
  final classCode = ref.watch(studentClassFilterProvider);

  final List<AdminAccount> source = switch (tab) {
    AccountType.guru => data.guru,
    AccountType.siswa => data.siswa,
    AccountType.adm => data.admins,
  };

  bool statusMatches(AdminAccount a) => switch (status) {
    StatusFilter.all => true,
    StatusFilter.on => a.active,
    StatusFilter.off => !a.active,
  };

  return [
    for (final a in source)
      if ('${a.name}${a.email}'.toLowerCase().contains(query) &&
          statusMatches(a) &&
          (tab != AccountType.siswa || classCode == 'all' || (a as Siswa).classCode == classCode))
        a,
  ];
});

final filteredLogProvider = Provider.autoDispose<List<LogAktivitas>>((ref) {
  final log = ref.watch(adminDatasetProvider.select((d) => d.log));
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final type = ref.watch(logTypeFilterProvider);
  return [
    for (final entry in log)
      if ((type == null || entry.type == type) && entry.message.toLowerCase().contains(query))
        entry,
  ];
});

final classStudentsProvider = Provider.autoDispose.family<List<Siswa>, String>((ref, code) {
  final siswa = ref.watch(adminDatasetProvider.select((d) => d.siswa));
  final query = ref.watch(searchQueryProvider).toLowerCase();
  return [
    for (final s in siswa)
      if (s.classCode == code && s.name.toLowerCase().contains(query)) s,
  ];
});

class DashboardStats {
  const DashboardStats({
    required this.students,
    required this.teachers,
    required this.classes,
    required this.activeAccounts,
    required this.inactiveAccounts,
    required this.classesWithoutWali,
    required this.unassignedTeachers,
  });

  final int students;
  final int teachers;
  final int classes;
  final int activeAccounts;
  final int inactiveAccounts;
  final int classesWithoutWali;
  final int unassignedTeachers;
}

final dashboardStatsProvider = Provider.autoDispose<DashboardStats>((ref) {
  final data = ref.watch(adminDatasetProvider);
  final accounts = data.allAccounts;
  final inactive = accounts.where((a) => !a.active).length;
  return DashboardStats(
    students: data.siswa.length,
    teachers: data.guru.length,
    classes: data.classes.length,
    activeAccounts: accounts.length - inactive,
    inactiveAccounts: inactive,
    classesWithoutWali: data.classes.values.where((k) => k.waliId == null).length,
    unassignedTeachers: data.guru.where((g) {
      final a = data.assignmentOf(g.id);
      return a.wali.isEmpty && a.mapel.isEmpty;
    }).length,
  );
});
