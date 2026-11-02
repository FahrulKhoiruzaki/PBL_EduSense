import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/value_state.dart';
import '../../../models/app_models.dart';
import '../../../repositories/parent_repository.dart';
import '../data/parent_models.dart';

export '../data/parent_models.dart';

enum ParentTab {
  beranda('Beranda'),
  nilai('Nilai'),
  hadir('Hadir'),
  riwayat('Riwayat');

  const ParentTab(this.label);
  final String label;
}

enum ParentSubPage {
  profil('Profil Anak'),
  statistik('Statistik'),
  notifikasi('Notifikasi');

  const ParentSubPage(this.label);
  final String label;
}

enum StatsPeriod {
  semester('Semester ini', 9),
  bulan('Bulan ini', 3);

  const StatsPeriod(this.label, this.points);
  final String label;
  final int points;
}

List<int> lastPoints(List<int> values, int count) =>
    values.length > count ? values.sublist(values.length - count) : values;

final anakListProvider = FutureProvider<List<Anak>>(
  (ref) => ref.watch(parentRepositoryProvider).fetchChildren(),
);

class SelectedKidNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    state = index;
    ref.invalidate(attendanceMonthProvider);
    ref.invalidate(attendanceDayProvider);
  }
}

final selectedKidIndexProvider =
    NotifierProvider<SelectedKidNotifier, int>(SelectedKidNotifier.new);

/// Hanya boleh dibaca setelah [anakListProvider] berisi data (layar dibangun di dalam AsyncBody).
final selectedKidProvider = Provider<Anak>((ref) {
  final list = ref.watch(anakListProvider).requireValue;
  final index = ref.watch(selectedKidIndexProvider);
  return list[math.min(index, list.length - 1)];
});

final statsPeriodProvider = NotifierProvider<ValueState<StatsPeriod>, StatsPeriod>(
  () => ValueState(StatsPeriod.semester),
);

final attendanceMonthProvider =
    NotifierProvider<ValueState<DateTime?>, DateTime?>(() => ValueState(null));

final attendanceDayProvider =
    NotifierProvider<ValueState<int>, int>(() => ValueState(0));

final attendanceStatusFilterProvider =
    NotifierProvider<ValueState<AttendanceStatus?>, AttendanceStatus?>(
  () => ValueState(null),
);

final gradeCategoryFilterProvider =
    NotifierProvider<ValueState<SubjectCategory?>, SubjectCategory?>(
  () => ValueState(null),
);

final gradeQueryProvider =
    NotifierProvider<ValueState<String>, String>(() => ValueState(''));

final historyFilterProvider =
    NotifierProvider<ValueState<HistoryKind?>, HistoryKind?>(() => ValueState(null));

final subPageProvider =
    NotifierProvider<ValueState<ParentSubPage?>, ParentSubPage?>(() => ValueState(null));

final selectedGradeIdProvider =
    NotifierProvider<ValueState<int?>, int?>(() => ValueState(null));

class ParentNavigator extends Notifier<ParentTab> {
  @override
  ParentTab build() => ParentTab.beranda;

  void _resetView() {
    ref.invalidate(gradeCategoryFilterProvider);
    ref.invalidate(gradeQueryProvider);
    ref.invalidate(historyFilterProvider);
    ref.invalidate(attendanceDayProvider);
  }

  void openTab(ParentTab tab) {
    _resetView();
    ref.read(subPageProvider.notifier).set(null);
    ref.read(selectedGradeIdProvider.notifier).set(null);
    state = tab;
  }

  void openSubPage(ParentSubPage page) {
    _resetView();
    ref.read(selectedGradeIdProvider.notifier).set(null);
    ref.read(subPageProvider.notifier).set(page);
  }

  void openGrade(int id) {
    _resetView();
    ref.read(subPageProvider.notifier).set(null);
    ref.read(selectedGradeIdProvider.notifier).set(id);
    state = ParentTab.nilai;
  }

  bool back() {
    if (ref.read(subPageProvider) != null) {
      _resetView();
      ref.read(subPageProvider.notifier).set(null);
      return true;
    }
    if (ref.read(selectedGradeIdProvider) != null) {
      _resetView();
      ref.read(selectedGradeIdProvider.notifier).set(null);
      return true;
    }
    return false;
  }
}

final activeTabProvider =
    NotifierProvider<ParentNavigator, ParentTab>(ParentNavigator.new);

final canGoBackProvider = Provider<bool>(
  (ref) =>
      ref.watch(subPageProvider) != null || ref.watch(selectedGradeIdProvider) != null,
);

class ParentNotificationsNotifier extends AsyncNotifier<List<ParentNotification>> {
  ParentRepository get _repo => ref.read(parentRepositoryProvider);

  @override
  Future<List<ParentNotification>> build() =>
      ref.watch(parentRepositoryProvider).fetchNotifications();

  Future<void> markRead(int id) async {
    final previous = state.value;
    if (previous == null) return;
    state = AsyncData([for (final n in previous) n.id == id ? n.copyWith(read: true) : n]);
    try {
      await _repo.markNotificationRead(id);
    } catch (_) {
      state = AsyncData(previous);
    }
  }

  Future<void> markAllRead() async {
    final previous = state.value;
    if (previous == null) return;
    state = AsyncData([for (final n in previous) n.copyWith(read: true)]);
    try {
      await _repo.markAllNotificationsRead();
    } catch (_) {
      state = AsyncData(previous);
    }
  }
}

final parentNotificationsProvider =
    AsyncNotifierProvider<ParentNotificationsNotifier, List<ParentNotification>>(
  ParentNotificationsNotifier.new,
);

final hasUnreadProvider = Provider<bool>(
  (ref) => (ref.watch(parentNotificationsProvider).value ?? const []).any((n) => !n.read),
);

final filteredGradesProvider = Provider.autoDispose<List<NilaiUjian>>((ref) {
  final kid = ref.watch(selectedKidProvider);
  final category = ref.watch(gradeCategoryFilterProvider);
  final query = ref.watch(gradeQueryProvider).toLowerCase();
  return [
    for (final g in kid.nilai)
      if ((category == null || g.kategori == category) &&
          '${g.jenis}${g.kategori.label}'.toLowerCase().contains(query))
        g,
  ];
});

final attendanceRecordsProvider = FutureProvider.autoDispose<List<HariKehadiran>>((ref) {
  final kid = ref.watch(selectedKidProvider);
  return ref.watch(parentRepositoryProvider).fetchAttendance(kid.id);
});

final attendanceMonthsProvider = Provider.autoDispose<List<DateTime>>((ref) {
  final records = ref.watch(attendanceRecordsProvider).value ?? const [];
  return ({for (final r in records) r.bulan}.toList())..sort();
});

/// Bulan yang dipilih, atau bulan terbaru yang punya data bila belum dipilih.
final selectedMonthProvider = Provider.autoDispose<DateTime?>((ref) {
  final months = ref.watch(attendanceMonthsProvider);
  final chosen = ref.watch(attendanceMonthProvider);
  if (chosen != null && months.contains(chosen)) return chosen;
  return months.isEmpty ? null : months.last;
});

final schoolDaysProvider = Provider.autoDispose<List<HariKehadiran>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final records = ref.watch(attendanceRecordsProvider).value ?? const [];
  return [
    for (final r in records)
      if (r.bulan == month) r,
  ];
});

final monthlyAttendanceSummaryProvider = Provider.autoDispose<AttendanceSummary>((ref) {
  final days = ref.watch(schoolDaysProvider);
  final counts = {for (final s in AttendanceStatus.values) s: 0};
  for (final d in days) {
    counts[d.status] = counts[d.status]! + 1;
  }
  final present = counts[AttendanceStatus.hadir]! + counts[AttendanceStatus.terlambat]!;
  return AttendanceSummary(
    total: days.length,
    counts: counts,
    percent: days.isEmpty ? 0 : (present / days.length * 100).round(),
  );
});

final attendanceHistoryProvider = Provider.autoDispose<List<HariKehadiran>>((ref) {
  final filter = ref.watch(attendanceStatusFilterProvider);
  final days = ref.watch(schoolDaysProvider);
  return [
    for (final d in days.reversed)
      if (filter == null || d.status == filter) d,
  ];
});

final historyAsyncProvider = FutureProvider.autoDispose<List<HistoryItem>>((ref) {
  final kid = ref.watch(selectedKidProvider);
  return ref.watch(parentRepositoryProvider).fetchHistory(kid.id);
});

final historyEntriesProvider = Provider.autoDispose<List<HistoryItem>>((ref) {
  final filter = ref.watch(historyFilterProvider);
  final all = ref.watch(historyAsyncProvider).value ?? const [];
  return [
    for (final e in all)
      if (filter == null || e.kind == filter) e,
  ];
});
