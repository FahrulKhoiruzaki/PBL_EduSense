import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/value_state.dart';
import '../../../models/academic_models.dart';
import '../../../repositories/academic_admin_repository.dart';
import 'admin_data_provider.dart';

/// Daftar periode akademik; setiap perubahan memuat ulang daftar dan data turunannya
/// (komponen, ringkasan klasifikasi, pengaturan tahun ajaran di dataset admin).
class AdminPeriodsNotifier extends AsyncNotifier<List<AdminPeriod>> {
  AcademicAdminRepository get _repo => ref.read(academicAdminRepositoryProvider);

  @override
  Future<List<AdminPeriod>> build() => ref.watch(academicAdminRepositoryProvider).fetchPeriods();

  Future<void> _after(Future<void> Function() action) async {
    await action();
    ref.invalidate(adminComponentsProvider);
    ref.invalidate(adminClassificationProvider);
    ref.invalidate(adminRuleProvider);
    try {
      state = AsyncData(await _repo.fetchPeriods());
    } on Exception {
      ref.invalidateSelf();
    }
  }

  Future<void> create(PeriodInput input) => _after(() => _repo.createPeriod(input));

  Future<void> edit(int id, PeriodInput input) => _after(() => _repo.updatePeriod(id, input));

  Future<void> activate(int id) => _after(() async {
        await _repo.activatePeriod(id);
        // Tahun ajaran di pengaturan sekolah mengikuti periode aktif.
        ref.invalidate(adminDataProvider);
      });

  Future<void> delete(int id) => _after(() => _repo.deletePeriod(id));

  Future<void> saveRule(int id, ClassificationRule rule) => _after(() => _repo.saveRule(id, rule));

  Future<(int, int)> recompute(int id) async {
    late (int, int) result;
    await _after(() async => result = await _repo.recompute(id));
    return result;
  }
}

final adminPeriodsProvider =
    AsyncNotifierProvider<AdminPeriodsNotifier, List<AdminPeriod>>(AdminPeriodsNotifier.new);

final adminRuleProvider = FutureProvider.family<ClassificationRule?, int>(
  (ref, periodId) => ref.watch(academicAdminRepositoryProvider).fetchRule(periodId),
);

class AdminSubjectsNotifier extends AsyncNotifier<List<Subject>> {
  AcademicAdminRepository get _repo => ref.read(academicAdminRepositoryProvider);

  @override
  Future<List<Subject>> build() => ref.watch(academicAdminRepositoryProvider).fetchSubjects();

  Future<void> _after(Future<void> Function() action) async {
    await action();
    ref.invalidate(adminComponentsProvider);
    try {
      state = AsyncData(await _repo.fetchSubjects());
    } on Exception {
      ref.invalidateSelf();
    }
  }

  Future<void> create(SubjectInput input) => _after(() => _repo.createSubject(input));

  Future<void> edit(int id, SubjectInput input) => _after(() => _repo.updateSubject(id, input));

  Future<void> setActive(int id, {required bool active}) =>
      _after(() => _repo.setSubjectActive(id, active: active));

  Future<void> delete(int id) => _after(() => _repo.deleteSubject(id));
}

final adminSubjectsProvider =
    AsyncNotifierProvider<AdminSubjectsNotifier, List<Subject>>(AdminSubjectsNotifier.new);

/// Periode yang dipilih di layar komponen dan klasifikasi; null = periode aktif.
final academicPeriodFilterProvider =
    NotifierProvider<ValueState<int?>, int?>(() => ValueState<int?>(null));

final classificationClassFilterProvider =
    NotifierProvider<ValueState<String?>, String?>(() => ValueState<String?>(null));

/// Id periode yang benar-benar dipakai: pilihan admin, atau periode aktif bila belum memilih.
final effectivePeriodIdProvider = Provider<int?>((ref) {
  final periods = ref.watch(adminPeriodsProvider).value ?? const <AdminPeriod>[];
  final chosen = ref.watch(academicPeriodFilterProvider);
  if (chosen != null && periods.any((p) => p.id == chosen)) return chosen;
  return periods.where((p) => p.active).firstOrNull?.id ??
      (periods.isEmpty ? null : periods.first.id);
});

final adminComponentsProvider = FutureProvider.family<List<AdminComponent>, int>(
  (ref, periodId) => ref.watch(academicAdminRepositoryProvider).fetchComponents(periodId: periodId),
);

class AdminComponentsActions {
  AdminComponentsActions(this._ref);

  final Ref _ref;

  AcademicAdminRepository get _repo => _ref.read(academicAdminRepositoryProvider);

  Future<void> _after(Future<void> Function() action) async {
    await action();
    _ref.invalidate(adminComponentsProvider);
    _ref.invalidate(adminPeriodsProvider);
    _ref.invalidate(adminClassificationProvider);
  }

  Future<void> create(ComponentInput input) => _after(() => _repo.createComponent(input));

  Future<void> edit(int id, ComponentInput input) => _after(() => _repo.updateComponent(id, input));

  Future<void> setActive(int id, {required bool active}) =>
      _after(() => _repo.setComponentActive(id, active: active));

  Future<void> delete(int id) => _after(() => _repo.deleteComponent(id));

  Future<(int, int)> copy({required int from, required int to}) async {
    late (int, int) result;
    await _after(() async => result = await _repo.copyComponents(fromPeriodId: from, toPeriodId: to));
    return result;
  }
}

final adminComponentsActionsProvider = Provider<AdminComponentsActions>(AdminComponentsActions.new);

final adminClassificationProvider =
    FutureProvider.family<ClassificationSummary, (int?, String?)>((ref, key) {
  final (periodId, classCode) = key;
  return ref
      .watch(academicAdminRepositoryProvider)
      .fetchClassification(periodId: periodId, classCode: classCode);
});
