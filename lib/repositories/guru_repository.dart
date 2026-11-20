import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/network/api_client.dart';
import '../features/orang_tua/data/parent_models.dart' show HistoryItem;
import '../models/academic_models.dart';
import '../models/app_models.dart';
import 'parent_repository.dart' show historyItemFromJson;

class GradeInput {
  const GradeInput({
    required this.studentId,
    required this.componentId,
    required this.assessment,
    required this.value,
    required this.date,
    required this.note,
  });

  final int studentId;

  /// Komponen penilaian dari admin; menentukan mapel, kategori, dan periode nilai.
  final int componentId;

  /// Keterangan penilaian (mis. "Tugas Bab 2"); kosong = nama komponen.
  final String assessment;
  final int value;
  final DateTime date;
  final String note;
}

abstract interface class GuruRepository {
  Future<List<ClassInfo>> fetchClassSummaries();

  /// [periodId] null = periode aktif.
  Future<ClassData> fetchClassData(String classCode, {int? periodId});

  Future<List<AcademicPeriod>> fetchPeriods();

  Future<List<ClassSubject>> fetchClassSubjects(String classCode, {int? periodId});

  Future<SubjectRecap> fetchRecap(String classCode, {required int subjectId, int? periodId});

  Future<ClassificationSummary> fetchClassification(String classCode, {int? periodId});

  /// Rekap semua siswa x mapel yang boleh dilihat guru ini (wali: semua mapel; guru mapel:
  /// mapel yang ditugaskan). Dibatasi oleh backend.
  Future<ClassReport> fetchClassReport(String classCode, {int? periodId});

  /// Rapor satu siswa (wali: semua mapel; guru mapel: mapel yang diampu). Dibatasi backend.
  Future<StudentReport> fetchStudentReport(String classCode, int studentId, {int? periodId});

  /// Riwayat nilai, kehadiran, dan klasifikasi siswa (terbaru dulu).
  Future<List<HistoryItem>> fetchStudentHistory(String classCode, int studentId);

  Future<void> setAttendance({
    required String classCode,
    required int studentId,
    required AttendanceStatus status,
    String note = '',
  });

  Future<FaceScanResult> recognizeFace({
    required String classCode,
    required Uint8List image,
  });

  Future<void> finishAttendance(String classCode);

  Future<void> createGrade(String classCode, GradeInput input);

  Future<void> updateGrade(int gradeId, GradeInput input);

  Future<void> deleteGrade(int gradeId);

  Future<List<AppNotification>> fetchNotifications();

  Future<void> markNotificationRead(int id);

  Future<void> markAllNotificationsRead();

  Future<List<ActivityItem>> fetchActivities();
}

abstract final class GuruPaths {
  static const classes = '/guru/classes';
  static String classDetail(String code) => '/guru/classes/$code';
  static String attendance(String code, int studentId) =>
      '/guru/classes/$code/attendance/$studentId';
  static String faceScan(String code) => '/guru/classes/$code/attendance/face';
  static String finishAttendance(String code) => '/guru/classes/$code/attendance/finish';
  static String createGrade(String code) => '/guru/classes/$code/grades';
  static String grade(int id) => '/guru/grades/$id';
  static const notifications = '/guru/notifications';
  static String notificationRead(int id) => '/guru/notifications/$id/read';
  static const notificationsReadAll = '/guru/notifications/read-all';
  static const activities = '/guru/activities';
  static const periods = '/guru/periods';
  static String subjects(String code) => '/guru/classes/$code/subjects';
  static String recap(String code) => '/guru/classes/$code/recap';
  static String classification(String code) => '/guru/classes/$code/classification';
  static String classReport(String code) => '/guru/classes/$code/report';
  static String studentReport(String code, int id) => '/guru/classes/$code/students/$id/report';
  static String studentHistory(String code, int id) => '/guru/classes/$code/students/$id/history';
}

Map<String, dynamic>? periodQuery(int? periodId) =>
    periodId == null ? null : {'periode_id': periodId};

class ApiGuruRepository implements GuruRepository {
  ApiGuruRepository(this._api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final DateTime Function() _clock;

  @override
  Future<List<ClassInfo>> fetchClassSummaries() async {
    final rows = await _api.getList(GuruPaths.classes);
    return [
      for (final r in rows)
        ClassInfo(
          code: r['kelas'] as String,
          studentCount: (r['jumlah_siswa'] as num).toInt(),
          attendancePercent: (r['persen_hadir'] as num?)?.round() ?? 0,
        ),
    ];
  }

  @override
  Future<ClassData> fetchClassData(String classCode, {int? periodId}) async {
    final json =
        await _api.getObject(GuruPaths.classDetail(classCode), query: periodQuery(periodId));
    final trend = (json['tren'] as Map<String, dynamic>?) ?? const {};
    List<int> series(String key) =>
        [for (final v in (trend[key] as List<dynamic>? ?? const [])) (v as num).round()];

    return ClassData(
      students: [for (final s in json['siswa'] as List<dynamic>) _student(s as Map<String, dynamic>)],
      grades: [for (final g in json['nilai'] as List<dynamic>) _grade(g as Map<String, dynamic>)],
      averageLiterasi: (json['rata_literasi'] as num?)?.round() ?? 0,
      averageNumerasi: (json['rata_numerasi'] as num?)?.round() ?? 0,
      literasiTrend: series('literasi'),
      numerasiTrend: series('numerasi'),
      attendanceTrend: series('kehadiran'),
      trendPoints: TrendSet.fromJson(trend['titik']),
      period: json['periode'] == null
          ? null
          : AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
    );
  }

  @override
  Future<List<AcademicPeriod>> fetchPeriods() async => [
        for (final r in await _api.getList(GuruPaths.periods)) AcademicPeriod.fromJson(r),
      ];

  @override
  Future<List<ClassSubject>> fetchClassSubjects(String classCode, {int? periodId}) async => [
        for (final r in await _api.getList(GuruPaths.subjects(classCode), query: periodQuery(periodId)))
          ClassSubject.fromJson(r),
      ];

  @override
  Future<SubjectRecap> fetchRecap(String classCode, {required int subjectId, int? periodId}) async =>
      SubjectRecap.fromJson(await _api.getObject(
        GuruPaths.recap(classCode),
        query: {'mapel_id': subjectId, ...?periodQuery(periodId)},
      ));

  @override
  Future<ClassReport> fetchClassReport(String classCode, {int? periodId}) async =>
      ClassReport.fromJson(await _api.getObject(
        GuruPaths.classReport(classCode),
        query: periodQuery(periodId),
      ));

  @override
  Future<StudentReport> fetchStudentReport(String classCode, int studentId, {int? periodId}) async =>
      StudentReport.fromJson(await _api.getObject(
        GuruPaths.studentReport(classCode, studentId),
        query: periodQuery(periodId),
      ));

  @override
  Future<List<HistoryItem>> fetchStudentHistory(String classCode, int studentId) async => [
        for (final r in await _api.getList(GuruPaths.studentHistory(classCode, studentId)))
          historyItemFromJson(r),
      ];

  @override
  Future<ClassificationSummary> fetchClassification(String classCode, {int? periodId}) async =>
      ClassificationSummary.fromJson(await _api.getObject(
        GuruPaths.classification(classCode),
        query: periodQuery(periodId),
      ));

  @override
  Future<void> setAttendance({
    required String classCode,
    required int studentId,
    required AttendanceStatus status,
    String note = '',
  }) async {
    await _api.put(
      GuruPaths.attendance(classCode, studentId),
      body: {'status': status.code, 'metode_input': 'manual', 'catatan': note},
    );
  }

  @override
  Future<FaceScanResult> recognizeFace({
    required String classCode,
    required Uint8List image,
  }) async {
    final json = await _api.postObject(
      GuruPaths.faceScan(classCode),
      body: FormData.fromMap({
        'foto': MultipartFile.fromBytes(image, filename: 'scan.jpg'),
      }),
    );
    return switch (json['hasil']) {
      'cocok' => FaceMatched(
          studentId: (json['siswa_id'] as num).toInt(),
          studentName: json['nama'] as String,
          time: _time(json['waktu']),
        ),
      'duplikat' => FaceDuplicate(
          studentName: json['nama'] as String,
          time: _time(json['waktu']),
        ),
      'kelas_lain' => const FaceOtherClass(),
      _ => const FaceNotRecognized(),
    };
  }

  @override
  Future<void> finishAttendance(String classCode) async {
    await _api.post(GuruPaths.finishAttendance(classCode));
  }

  @override
  Future<void> createGrade(String classCode, GradeInput input) async {
    await _api.post(GuruPaths.createGrade(classCode), body: _gradeBody(input));
  }

  @override
  Future<void> updateGrade(int gradeId, GradeInput input) async {
    await _api.put(GuruPaths.grade(gradeId), body: _gradeBody(input));
  }

  @override
  Future<void> deleteGrade(int gradeId) async {
    await _api.delete(GuruPaths.grade(gradeId));
  }

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    final rows = await _api.getList(GuruPaths.notifications);
    return [
      for (final r in rows)
        if (_target(r['target'] as String?, (r['target_id'] as num?)?.toInt()) case final target?)
          AppNotification(
            id: (r['id'] as num).toInt(),
            title: r['judul'] as String,
            group: r['kelompok'] == 'sebelumnya'
                ? NotificationGroup.earlier
                : NotificationGroup.today,
            target: target,
            read: r['dibaca'] as bool? ?? false,
          ),
    ];
  }

  @override
  Future<void> markNotificationRead(int id) async {
    await _api.post(GuruPaths.notificationRead(id));
  }

  @override
  Future<void> markAllNotificationsRead() async {
    await _api.post(GuruPaths.notificationsReadAll);
  }

  @override
  Future<List<ActivityItem>> fetchActivities() async {
    final rows = await _api.getList(GuruPaths.activities);
    final now = _clock();
    return [
      for (final r in rows)
        if (_target(r['target'] as String?, (r['target_id'] as num?)?.toInt()) case final target?)
          ActivityItem(
            title: r['judul'] as String,
            when: relativeTime(now, DateTime.parse(r['created_at'] as String).toLocal()),
            target: target,
          ),
    ];
  }

  Map<String, dynamic> _gradeBody(GradeInput input) => {
        'siswa_id': input.studentId,
        'komponen_id': input.componentId,
        'jenis_ujian': input.assessment,
        'nilai': input.value,
        'tanggal': isoDate(input.date),
        'catatan_guru': input.note,
      };

  Student _student(Map<String, dynamic> json) => Student(
        id: (json['id'] as num).toInt(),
        name: json['nama'] as String,
        classification: classificationFromLabel(json['klasifikasi']),
        status: _status(json['status'] as String?),
        time: _time(json['waktu']),
        literasi: (json['literasi'] as num?)?.round() ?? 0,
        numerasi: (json['numerasi'] as num?)?.round() ?? 0,
        declining: json['menurun'] as bool? ?? false,
      );

  GradeEntry _grade(Map<String, dynamic> json) {
    final value = (json['nilai'] as num).round();
    return GradeEntry(
      id: (json['id'] as num).toInt(),
      studentId: (json['siswa_id'] as num).toInt(),
      studentName: json['siswa'] as String,
      category: subjectCategoryFromLabel(json['kategori']),
      assessment: json['jenis_ujian'] as String,
      value: value,
      previous: (json['nilai_sebelumnya'] as num?)?.round() ?? value,
      date: DateTime.parse(json['tanggal'] as String),
      note: json['catatan_guru'] as String? ?? '',
      periodId: (json['periode_id'] as num?)?.toInt(),
      subjectId: (json['mapel_id'] as num?)?.toInt(),
      subjectName: json['mapel'] as String?,
      componentId: (json['komponen_id'] as num?)?.toInt(),
      componentName: json['komponen'] as String?,
    );
  }

  AttendanceStatus _status(String? code) => AttendanceStatus.values.firstWhere(
        (s) => s.code == code,
        orElse: () => AttendanceStatus.alpa,
      );

  String _time(Object? value) {
    final text = value as String?;
    return text == null || text.length < 5 ? '' : text.substring(0, 5);
  }

  NavTarget? _target(String? name, int? id) => switch (name) {
        'absensi' => const NavTarget(AppRoute.attendanceClass),
        'nilai' when id != null => NavTarget(AppRoute.gradeDetail, arg: id),
        'daftar_nilai' => const NavTarget(AppRoute.grades),
        'perlu_perhatian' => NavTarget(AppRoute.needAttention, arg: id ?? 0),
        'statistik' => const NavTarget(AppRoute.stats),
        _ => null,
      };
}

final guruRepositoryProvider = Provider<GuruRepository>(
  (ref) => ApiGuruRepository(ref.watch(apiClientProvider)),
);
