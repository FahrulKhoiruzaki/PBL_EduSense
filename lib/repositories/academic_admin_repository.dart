import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/network/api_client.dart';
import '../models/academic_models.dart';

/// Data akademik panel admin: periode, mata pelajaran, komponen penilaian, aturan dan ringkasan
/// klasifikasi. Endpoint: `/admin/academic/*` (backend `app/api/routers/admin_academic.py`).
abstract interface class AcademicAdminRepository {
  Future<List<AdminPeriod>> fetchPeriods();

  Future<void> createPeriod(PeriodInput input);

  Future<void> updatePeriod(int id, PeriodInput input);

  Future<void> activatePeriod(int id);

  Future<void> deletePeriod(int id);

  Future<ClassificationRule?> fetchRule(int periodId);

  Future<void> saveRule(int periodId, ClassificationRule rule);

  /// Mengembalikan (jumlah siswa dihitung, jumlah terklasifikasi).
  Future<(int, int)> recompute(int periodId);

  Future<List<Subject>> fetchSubjects();

  Future<void> createSubject(SubjectInput input);

  Future<void> updateSubject(int id, SubjectInput input);

  Future<void> setSubjectActive(int id, {required bool active});

  Future<void> deleteSubject(int id);

  Future<List<AdminComponent>> fetchComponents({required int periodId});

  Future<void> createComponent(ComponentInput input);

  Future<void> updateComponent(int id, ComponentInput input);

  Future<void> setComponentActive(int id, {required bool active});

  Future<void> deleteComponent(int id);

  /// Mengembalikan (jumlah disalin, jumlah dilewati karena sudah ada).
  Future<(int, int)> copyComponents({required int fromPeriodId, required int toPeriodId});

  Future<ClassificationSummary> fetchClassification({int? periodId, String? classCode});
}

class PeriodInput {
  const PeriodInput({
    required this.academicYear,
    required this.semester,
    required this.start,
    required this.end,
  });

  final String academicYear;
  final int semester;
  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson() => {
        'tahun_ajaran': academicYear,
        'semester': semester,
        'tanggal_mulai': isoDate(start),
        'tanggal_selesai': isoDate(end),
      };
}

abstract final class AcademicAdminPaths {
  static const _base = '/admin/academic';
  static const periods = '$_base/periods';
  static String period(int id) => '$periods/$id';
  static String activate(int id) => '$periods/$id/activate';
  static String rule(int id) => '$periods/$id/rule';
  static String recompute(int id) => '$periods/$id/recompute';
  static const subjects = '$_base/subjects';
  static String subject(int id) => '$subjects/$id';
  static String subjectActive(int id) => '$subjects/$id/active';
  static const components = '$_base/components';
  static const copyComponents = '$components/copy';
  static String component(int id) => '$components/$id';
  static String componentActive(int id) => '$components/$id/active';
  static const classification = '$_base/classification';
}

class ApiAcademicAdminRepository implements AcademicAdminRepository {
  ApiAcademicAdminRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<AdminPeriod>> fetchPeriods() async => [
        for (final r in await _api.getList(AcademicAdminPaths.periods)) AdminPeriod.fromJson(r),
      ];

  @override
  Future<void> createPeriod(PeriodInput input) =>
      _api.post(AcademicAdminPaths.periods, body: input.toJson());

  @override
  Future<void> updatePeriod(int id, PeriodInput input) =>
      _api.put(AcademicAdminPaths.period(id), body: input.toJson());

  @override
  Future<void> activatePeriod(int id) => _api.post(AcademicAdminPaths.activate(id));

  @override
  Future<void> deletePeriod(int id) => _api.delete(AcademicAdminPaths.period(id));

  @override
  Future<ClassificationRule?> fetchRule(int periodId) async {
    final json = await _api.get(AcademicAdminPaths.rule(periodId));
    return json is Map<String, dynamic> ? ClassificationRule.fromJson(json) : null;
  }

  @override
  Future<void> saveRule(int periodId, ClassificationRule rule) =>
      _api.put(AcademicAdminPaths.rule(periodId), body: rule.toJson());

  @override
  Future<(int, int)> recompute(int periodId) async {
    final json = await _api.postObject(AcademicAdminPaths.recompute(periodId));
    return ((json['dihitung'] as num).toInt(), (json['terklasifikasi'] as num).toInt());
  }

  @override
  Future<List<Subject>> fetchSubjects() async => [
        for (final r in await _api.getList(AcademicAdminPaths.subjects)) Subject.fromJson(r),
      ];

  @override
  Future<void> createSubject(SubjectInput input) =>
      _api.post(AcademicAdminPaths.subjects, body: input.toJson());

  @override
  Future<void> updateSubject(int id, SubjectInput input) =>
      _api.put(AcademicAdminPaths.subject(id), body: input.toJson());

  @override
  Future<void> setSubjectActive(int id, {required bool active}) =>
      _api.put(AcademicAdminPaths.subjectActive(id), body: {'aktif': active});

  @override
  Future<void> deleteSubject(int id) => _api.delete(AcademicAdminPaths.subject(id));

  @override
  Future<List<AdminComponent>> fetchComponents({required int periodId}) async => [
        for (final r in await _api.getList(
          AcademicAdminPaths.components,
          query: {'periode_id': periodId},
        ))
          AdminComponent.fromJson(r),
      ];

  @override
  Future<void> createComponent(ComponentInput input) =>
      _api.post(AcademicAdminPaths.components, body: input.toJson());

  @override
  Future<void> updateComponent(int id, ComponentInput input) =>
      _api.put(AcademicAdminPaths.component(id), body: input.toJson());

  @override
  Future<void> setComponentActive(int id, {required bool active}) =>
      _api.put(AcademicAdminPaths.componentActive(id), body: {'aktif': active});

  @override
  Future<void> deleteComponent(int id) => _api.delete(AcademicAdminPaths.component(id));

  @override
  Future<(int, int)> copyComponents({required int fromPeriodId, required int toPeriodId}) async {
    final json = await _api.postObject(
      AcademicAdminPaths.copyComponents,
      body: {'dari_periode_id': fromPeriodId, 'ke_periode_id': toPeriodId},
    );
    return ((json['disalin'] as num).toInt(), (json['dilewati'] as num).toInt());
  }

  @override
  Future<ClassificationSummary> fetchClassification({int? periodId, String? classCode}) async =>
      ClassificationSummary.fromJson(await _api.getObject(
        AcademicAdminPaths.classification,
        query: {
          'periode_id': ?periodId,
          'kelas': ?classCode,
        },
      ));
}

final academicAdminRepositoryProvider = Provider<AcademicAdminRepository>(
  (ref) => ApiAcademicAdminRepository(ref.watch(apiClientProvider)),
);
