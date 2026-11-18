import 'package:flutter/foundation.dart';

import 'app_models.dart';

/// Data akademik dari backend: periode, mata pelajaran, komponen penilaian, dan ringkasan
/// klasifikasi. Dipakai aplikasi guru dan panel admin, sehingga parsing JSON-nya ada di sini
/// (satu tempat) dan diuji bersama.

DateTime _date(Object? v) => DateTime.parse(v as String);

double? _double(Object? v) => (v as num?)?.toDouble();

SubjectCategory? subjectCategoryFromLabel(Object? label) => switch (label) {
      'Literasi' => SubjectCategory.literasi,
      'Numerasi' => SubjectCategory.numerasi,
      _ => null,
    };

Classification? classificationFromLabel(Object? label) =>
    Classification.values.where((c) => c.label == label).firstOrNull;

@immutable
class AcademicPeriod {
  const AcademicPeriod({
    required this.id,
    required this.academicYear,
    required this.semester,
    required this.semesterLabel,
    required this.label,
    required this.start,
    required this.end,
    required this.active,
  });

  factory AcademicPeriod.fromJson(Map<String, dynamic> json) => AcademicPeriod(
        id: (json['id'] as num).toInt(),
        academicYear: json['tahun_ajaran'] as String,
        semester: (json['semester'] as num).toInt(),
        semesterLabel: json['semester_label'] as String,
        label: json['label'] as String,
        start: _date(json['tanggal_mulai']),
        end: _date(json['tanggal_selesai']),
        active: json['aktif'] as bool? ?? false,
      );

  final int id;
  final String academicYear;
  final int semester;
  final String semesterLabel;
  final String label;
  final DateTime start;
  final DateTime end;
  final bool active;

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// Periode untuk panel admin, dengan penanda penggunaan data.
@immutable
class AdminPeriod extends AcademicPeriod {
  const AdminPeriod({
    required super.id,
    required super.academicYear,
    required super.semester,
    required super.semesterLabel,
    required super.label,
    required super.start,
    required super.end,
    required super.active,
    required this.gradeCount,
    required this.componentCount,
    required this.hasRule,
    required this.deletable,
  });

  factory AdminPeriod.fromJson(Map<String, dynamic> json) {
    final p = AcademicPeriod.fromJson(json);
    return AdminPeriod(
      id: p.id,
      academicYear: p.academicYear,
      semester: p.semester,
      semesterLabel: p.semesterLabel,
      label: p.label,
      start: p.start,
      end: p.end,
      active: p.active,
      gradeCount: (json['jumlah_nilai'] as num?)?.toInt() ?? 0,
      componentCount: (json['jumlah_komponen'] as num?)?.toInt() ?? 0,
      hasRule: json['punya_aturan'] as bool? ?? false,
      deletable: json['dapat_dihapus'] as bool? ?? false,
    );
  }

  final int gradeCount;
  final int componentCount;
  final bool hasRule;
  final bool deletable;
}

enum SubjectType {
  umum('umum', 'Umum'),
  muatanLokal('muatan_lokal', 'Muatan Lokal');

  const SubjectType(this.code, this.label);
  final String code;
  final String label;

  static SubjectType fromCode(Object? code) =>
      code == 'muatan_lokal' ? SubjectType.muatanLokal : SubjectType.umum;
}

@immutable
class Subject {
  const Subject({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.type,
    required this.levels,
    required this.active,
    required this.order,
    required this.used,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: (json['id'] as num).toInt(),
        code: json['kode'] as String,
        name: json['nama'] as String,
        description: json['deskripsi'] as String? ?? '',
        type: SubjectType.fromCode(json['jenis']),
        levels: [for (final v in json['tingkat'] as List<dynamic>? ?? const []) (v as num).toInt()],
        active: json['aktif'] as bool? ?? true,
        order: (json['urutan'] as num?)?.toInt() ?? 0,
        used: json['dipakai'] as bool? ?? false,
      );

  final int id;
  final String code;
  final String name;
  final String description;
  final SubjectType type;
  final List<int> levels;
  final bool active;
  final int order;
  final bool used;

  String get levelsLabel => levels.length == 6 ? 'Kelas 1–6' : 'Kelas ${levels.join(', ')}';
}

@immutable
class SubjectInput {
  const SubjectInput({
    required this.code,
    required this.name,
    required this.description,
    required this.type,
    required this.levels,
  });

  final String code;
  final String name;
  final String description;
  final SubjectType type;
  final List<int> levels;

  Map<String, dynamic> toJson() => {
        'kode': code,
        'nama': name,
        'deskripsi': description,
        'jenis': type.code,
        'tingkat': levels,
      };
}

@immutable
class GradeComponent {
  const GradeComponent({
    required this.id,
    required this.name,
    required this.category,
    required this.weight,
    required this.active,
  });

  factory GradeComponent.fromJson(Map<String, dynamic> json) => GradeComponent(
        id: (json['id'] as num).toInt(),
        name: json['nama'] as String,
        category: subjectCategoryFromLabel(json['kategori']),
        weight: _double(json['bobot']),
        active: json['aktif'] as bool? ?? true,
      );

  final int id;
  final String name;

  /// Literasi/Numerasi bila nilai komponen ini dipakai untuk klasifikasi; null bila tidak.
  final SubjectCategory? category;
  final double? weight;
  final bool active;
}

/// Komponen penilaian di panel admin (dengan mapel dan jumlah nilai).
@immutable
class AdminComponent extends GradeComponent {
  const AdminComponent({
    required super.id,
    required super.name,
    required super.category,
    required super.weight,
    required super.active,
    required this.periodId,
    required this.subjectId,
    required this.subjectName,
    required this.subjectCode,
    required this.description,
    required this.order,
    required this.gradeCount,
  });

  factory AdminComponent.fromJson(Map<String, dynamic> json) {
    final c = GradeComponent.fromJson(json);
    return AdminComponent(
      id: c.id,
      name: c.name,
      category: c.category,
      weight: c.weight,
      active: c.active,
      periodId: (json['periode_id'] as num).toInt(),
      subjectId: (json['mapel_id'] as num).toInt(),
      subjectName: json['mapel'] as String,
      subjectCode: json['mapel_kode'] as String,
      description: json['deskripsi'] as String? ?? '',
      order: (json['urutan'] as num?)?.toInt() ?? 0,
      gradeCount: (json['jumlah_nilai'] as num?)?.toInt() ?? 0,
    );
  }

  final int periodId;
  final int subjectId;
  final String subjectName;
  final String subjectCode;
  final String description;
  final int order;
  final int gradeCount;
}

@immutable
class ComponentInput {
  const ComponentInput({
    required this.periodId,
    required this.subjectId,
    required this.name,
    required this.category,
    required this.weight,
    this.description = '',
  });

  final int periodId;
  final int subjectId;
  final String name;
  final SubjectCategory? category;
  final double? weight;
  final String description;

  Map<String, dynamic> toJson() => {
        'periode_id': periodId,
        'mapel_id': subjectId,
        'nama': name,
        'kategori': category?.label,
        'bobot': weight,
        'deskripsi': description,
      };
}

/// Mapel yang berlaku untuk satu kelas (sudut pandang guru).
@immutable
class ClassSubject {
  const ClassSubject({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.canInput,
    required this.components,
  });

  factory ClassSubject.fromJson(Map<String, dynamic> json) => ClassSubject(
        id: (json['mapel_id'] as num).toInt(),
        code: json['kode'] as String,
        name: json['nama'] as String,
        type: SubjectType.fromCode(json['jenis']),
        canInput: json['boleh_input'] as bool? ?? false,
        components: [
          for (final c in json['komponen'] as List<dynamic>? ?? const [])
            GradeComponent.fromJson(c as Map<String, dynamic>),
        ],
      );

  final int id;
  final String code;
  final String name;
  final SubjectType type;

  /// True bila guru ditugaskan mengajar mapel ini di kelas tersebut (dan mapel aktif).
  final bool canInput;
  final List<GradeComponent> components;

  List<GradeComponent> get activeComponents => [
        for (final c in components)
          if (c.active) c,
      ];
}

enum ClassificationMethod {
  average('rata_rata', 'Rata-rata Literasi dan Numerasi'),
  lowest('terendah', 'Skor terendah dari Literasi dan Numerasi');

  const ClassificationMethod(this.code, this.label);
  final String code;
  final String label;

  static ClassificationMethod fromCode(Object? code) =>
      code == 'terendah' ? ClassificationMethod.lowest : ClassificationMethod.average;
}

@immutable
class ClassificationRule {
  const ClassificationRule({
    required this.method,
    required this.mahirMin,
    required this.cukupMin,
  });

  factory ClassificationRule.fromJson(Map<String, dynamic> json) => ClassificationRule(
        method: ClassificationMethod.fromCode(json['metode']),
        mahirMin: (json['batas_mahir'] as num).toDouble(),
        cukupMin: (json['batas_cukup'] as num).toDouble(),
      );

  final ClassificationMethod method;
  final double mahirMin;
  final double cukupMin;

  Map<String, dynamic> toJson() => {
        'metode': method.code,
        'batas_mahir': mahirMin,
        'batas_cukup': cukupMin,
      };
}

@immutable
class CategoryCount {
  const CategoryCount({required this.classification, required this.count, required this.percent});

  final Classification classification;
  final int count;

  /// Persen dari siswa yang terklasifikasi (bukan dari seluruh siswa).
  final double percent;
}

@immutable
class Distribution {
  const Distribution({
    required this.total,
    required this.classified,
    required this.incomplete,
    required this.withoutGrades,
    required this.categories,
    this.className,
  });

  factory Distribution.fromJson(Map<String, dynamic> json) => Distribution(
        total: (json['total_siswa'] as num?)?.toInt() ?? 0,
        classified: (json['terklasifikasi'] as num?)?.toInt() ?? 0,
        incomplete: (json['belum_lengkap'] as num?)?.toInt() ?? 0,
        withoutGrades: (json['tanpa_nilai'] as num?)?.toInt() ?? 0,
        className: json['kelas'] as String?,
        categories: [
          for (final k in json['kategori'] as List<dynamic>? ?? const [])
            if (classificationFromLabel((k as Map<String, dynamic>)['klasifikasi'])
                case final label?)
              CategoryCount(
                classification: label,
                count: (k['jumlah'] as num).toInt(),
                percent: (k['persen'] as num).toDouble(),
              ),
        ],
      );

  static const empty = Distribution(
    total: 0,
    classified: 0,
    incomplete: 0,
    withoutGrades: 0,
    categories: [],
  );

  final int total;
  final int classified;
  final int incomplete;
  final int withoutGrades;
  final List<CategoryCount> categories;
  final String? className;

  CategoryCount countOf(Classification k) =>
      categories.where((c) => c.classification == k).firstOrNull ??
      CategoryCount(classification: k, count: 0, percent: 0);
}

@immutable
class PeriodComparison {
  const PeriodComparison({
    required this.period,
    required this.before,
    required this.now,
    required this.compared,
    required this.up,
    required this.down,
    required this.same,
  });

  factory PeriodComparison.fromJson(Map<String, dynamic> json) => PeriodComparison(
        period: AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
        before: Distribution.fromJson(json['sebelumnya'] as Map<String, dynamic>),
        now: Distribution.fromJson(json['sekarang'] as Map<String, dynamic>),
        compared: (json['dibandingkan'] as num).toInt(),
        up: (json['naik'] as num).toInt(),
        down: (json['turun'] as num).toInt(),
        same: (json['tetap'] as num).toInt(),
      );

  final AcademicPeriod period;
  final Distribution before;
  final Distribution now;
  final int compared;
  final int up;
  final int down;
  final int same;
}

@immutable
class ClassificationSummary {
  const ClassificationSummary({
    required this.period,
    required this.rule,
    required this.overall,
    required this.perClass,
    required this.comparison,
    required this.note,
  });

  factory ClassificationSummary.fromJson(Map<String, dynamic> json) => ClassificationSummary(
        period: json['periode'] == null
            ? null
            : AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
        rule: json['aturan'] == null
            ? null
            : ClassificationRule.fromJson(json['aturan'] as Map<String, dynamic>),
        overall: Distribution.fromJson(json['ringkasan'] as Map<String, dynamic>),
        perClass: [
          for (final k in json['per_kelas'] as List<dynamic>? ?? const [])
            Distribution.fromJson(k as Map<String, dynamic>),
        ],
        comparison: json['perbandingan'] == null
            ? null
            : PeriodComparison.fromJson(json['perbandingan'] as Map<String, dynamic>),
        note: json['catatan'] as String?,
      );

  final AcademicPeriod? period;
  final ClassificationRule? rule;
  final Distribution overall;
  final List<Distribution> perClass;
  final PeriodComparison? comparison;
  final String? note;
}

/// Status kelengkapan penilaian satu mapel untuk satu siswa (dari backend). Nilai akhir hanya
/// ada bila [lengkap].
enum GradeStatus {
  lengkap('lengkap', 'Lengkap', 'L'),
  belumLengkap('belum_lengkap', 'Belum lengkap', 'BL'),
  belumDinilai('belum_dinilai', 'Belum dinilai', 'BD'),
  belumAdaKomponen('belum_ada_komponen', 'Belum ada komponen', 'BK');

  const GradeStatus(this.code, this.label, this.short);
  final String code;
  final String label;

  /// Singkatan untuk sel tabel padat (dijelaskan di legenda).
  final String short;

  static GradeStatus fromCode(Object? code) =>
      GradeStatus.values.where((s) => s.code == code).firstOrNull ?? GradeStatus.belumDinilai;
}

@immutable
class RecapRow {
  const RecapRow({
    required this.studentId,
    required this.name,
    required this.componentScores,
    required this.finalScore,
    this.status = GradeStatus.belumDinilai,
    this.filled = 0,
    this.required = 0,
  });

  final int studentId;
  final String name;

  /// Rata-rata per komponen, urut sama dengan [SubjectRecap.components]; null = belum dinilai.
  final List<double?> componentScores;

  /// Hanya ada bila [status] lengkap.
  final double? finalScore;
  final GradeStatus status;
  final int filled;
  final int required;
}

/// Rata-rata nilai akhir kelas (siswa berstatus lengkap) untuk satu mapel di satu periode.
@immutable
class SubjectProgress {
  const SubjectProgress({
    required this.period,
    required this.average,
    required this.complete,
    required this.students,
  });

  final AcademicPeriod period;
  final double? average;
  final int complete;
  final int students;
}

@immutable
class SubjectRecap {
  const SubjectRecap({
    required this.period,
    required this.subjectName,
    required this.components,
    required this.weighted,
    required this.rows,
    this.progress = const [],
  });

  factory SubjectRecap.fromJson(Map<String, dynamic> json) => SubjectRecap(
        period: AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
        subjectName: (json['mapel'] as Map<String, dynamic>)['nama'] as String,
        components: [
          for (final c in json['komponen'] as List<dynamic>? ?? const [])
            GradeComponent.fromJson(c as Map<String, dynamic>),
        ],
        weighted: json['metode'] == 'berbobot',
        rows: [
          for (final r in json['siswa'] as List<dynamic>? ?? const [])
            RecapRow(
              studentId: ((r as Map<String, dynamic>)['siswa_id'] as num).toInt(),
              name: r['nama'] as String,
              componentScores: [
                for (final v in r['nilai_komponen'] as List<dynamic>? ?? const []) _double(v),
              ],
              finalScore: _double(r['nilai_akhir']),
              status: GradeStatus.fromCode(r['status']),
              filled: (r['komponen_terisi'] as num?)?.toInt() ?? 0,
              required: (r['komponen_wajib'] as num?)?.toInt() ?? 0,
            ),
        ],
        progress: [
          for (final p in json['perkembangan'] as List<dynamic>? ?? const [])
            SubjectProgress(
              period: AcademicPeriod.fromJson((p as Map<String, dynamic>)['periode'] as Map<String, dynamic>),
              average: _double(p['rata_rata']),
              complete: (p['jumlah_lengkap'] as num?)?.toInt() ?? 0,
              students: (p['jumlah_siswa'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final AcademicPeriod period;
  final String subjectName;
  final List<GradeComponent> components;
  final bool weighted;
  final List<RecapRow> rows;
  final List<SubjectProgress> progress;
}

/// Hasil satu mapel untuk satu siswa di rekap kelas.
@immutable
class SubjectCell {
  const SubjectCell({
    required this.subjectId,
    required this.status,
    required this.filled,
    required this.required,
    required this.finalScore,
  });

  factory SubjectCell.fromJson(Map<String, dynamic> json) => SubjectCell(
        subjectId: (json['mapel_id'] as num).toInt(),
        status: GradeStatus.fromCode(json['status']),
        filled: (json['komponen_terisi'] as num?)?.toInt() ?? 0,
        required: (json['komponen_wajib'] as num?)?.toInt() ?? 0,
        finalScore: _double(json['nilai_akhir']),
      );

  final int subjectId;
  final GradeStatus status;
  final int filled;
  final int required;
  final double? finalScore;
}

@immutable
class ClassReportSubject {
  const ClassReportSubject({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.complete,
    required this.incomplete,
    required this.notGraded,
    required this.average,
  });

  final int id;
  final String code;
  final String name;
  final SubjectType type;
  final int complete;
  final int incomplete;

  /// Belum dinilai atau belum ada komponen.
  final int notGraded;

  /// Rata-rata nilai akhir siswa berstatus lengkap; null bila belum ada.
  final double? average;
}

@immutable
class ClassReportStudent {
  const ClassReportStudent({required this.id, required this.name, required this.cells});

  final int id;
  final String name;

  /// Urut sama dengan [ClassReport.subjects].
  final List<SubjectCell> cells;
}

/// Rekap kelas: semua siswa x semua mapel yang boleh dilihat (wali: semua; guru mapel: mapelnya).
@immutable
class ClassReport {
  const ClassReport({
    required this.period,
    required this.subjects,
    required this.students,
    required this.note,
  });

  factory ClassReport.fromJson(Map<String, dynamic> json) => ClassReport(
        period: json['periode'] == null
            ? null
            : AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
        subjects: [
          for (final m in json['mapel'] as List<dynamic>? ?? const [])
            ClassReportSubject(
              id: ((m as Map<String, dynamic>)['id'] as num).toInt(),
              code: m['kode'] as String,
              name: m['nama'] as String,
              type: SubjectType.fromCode(m['jenis']),
              complete: (m['lengkap'] as num?)?.toInt() ?? 0,
              incomplete: (m['belum_lengkap'] as num?)?.toInt() ?? 0,
              notGraded: (m['belum_dinilai'] as num?)?.toInt() ?? 0,
              average: _double(m['rata_rata']),
            ),
        ],
        students: [
          for (final s in json['siswa'] as List<dynamic>? ?? const [])
            ClassReportStudent(
              id: ((s as Map<String, dynamic>)['siswa_id'] as num).toInt(),
              name: s['nama'] as String,
              cells: [
                for (final c in s['nilai'] as List<dynamic>? ?? const [])
                  SubjectCell.fromJson(c as Map<String, dynamic>),
              ],
            ),
        ],
        note: json['catatan'] as String?,
      );

  final AcademicPeriod? period;
  final List<ClassReportSubject> subjects;
  final List<ClassReportStudent> students;
  final String? note;
}

@immutable
class ReportComponent {
  const ReportComponent({required this.component, required this.value, required this.count});

  final GradeComponent component;

  /// Rata-rata nilai siswa pada komponen ini; null = belum dinilai.
  final double? value;
  final int count;
}

@immutable
class ReportSubject {
  const ReportSubject({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.filled,
    required this.required,
    required this.finalScore,
    required this.weighted,
    required this.components,
  });

  factory ReportSubject.fromJson(Map<String, dynamic> json) => ReportSubject(
        id: (json['mapel_id'] as num).toInt(),
        code: json['kode'] as String,
        name: json['nama'] as String,
        type: SubjectType.fromCode(json['jenis']),
        status: GradeStatus.fromCode(json['status']),
        filled: (json['komponen_terisi'] as num?)?.toInt() ?? 0,
        required: (json['komponen_wajib'] as num?)?.toInt() ?? 0,
        finalScore: _double(json['nilai_akhir']),
        weighted: json['metode'] == 'berbobot',
        components: [
          for (final k in json['komponen'] as List<dynamic>? ?? const [])
            ReportComponent(
              component: GradeComponent.fromJson(k as Map<String, dynamic>),
              value: _double(k['nilai']),
              count: (k['jumlah_nilai'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final int id;
  final String code;
  final String name;
  final SubjectType type;
  final GradeStatus status;
  final int filled;
  final int required;

  /// Hanya ada bila [status] lengkap.
  final double? finalScore;
  final bool weighted;
  final List<ReportComponent> components;
}

@immutable
class ReportSummary {
  const ReportSummary({
    required this.subjects,
    required this.complete,
    required this.incomplete,
    required this.notGraded,
    required this.noComponents,
    required this.average,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
        subjects: (json['jumlah_mapel'] as num?)?.toInt() ?? 0,
        complete: (json['lengkap'] as num?)?.toInt() ?? 0,
        incomplete: (json['belum_lengkap'] as num?)?.toInt() ?? 0,
        notGraded: (json['belum_dinilai'] as num?)?.toInt() ?? 0,
        noComponents: (json['belum_ada_komponen'] as num?)?.toInt() ?? 0,
        average: _double(json['rata_rata_nilai_akhir']),
      );

  final int subjects;
  final int complete;
  final int incomplete;
  final int notGraded;
  final int noComponents;

  /// Rata-rata nilai akhir mapel berstatus lengkap pada periode itu saja; null bila belum ada.
  final double? average;
}

@immutable
class ReportHistoryPeriod {
  const ReportHistoryPeriod({required this.period, required this.classification, required this.subjects});

  final AcademicPeriod period;
  final Classification? classification;
  final List<({int id, String name, GradeStatus status, double? finalScore})> subjects;
}

@immutable
class AttendanceTally {
  const AttendanceTally({
    required this.total,
    required this.hadir,
    required this.terlambat,
    required this.izin,
    required this.sakit,
    required this.alpa,
    required this.percent,
  });

  factory AttendanceTally.fromJson(Object? json) {
    final j = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return AttendanceTally(
      total: n('total'),
      hadir: n('hadir'),
      terlambat: n('terlambat'),
      izin: n('izin'),
      sakit: n('sakit'),
      alpa: n('alpa'),
      percent: _double(j['persen_hadir']),
    );
  }

  final int total;
  final int hadir;
  final int terlambat;
  final int izin;
  final int sakit;
  final int alpa;

  /// null = belum ada catatan absensi (bukan 0%).
  final double? percent;
}

/// Rapor akademik satu siswa pada satu periode (backend `RaporOut`).
@immutable
class StudentReport {
  const StudentReport({
    required this.studentId,
    required this.name,
    required this.nis,
    required this.className,
    required this.period,
    required this.literasi,
    required this.numerasi,
    required this.classification,
    required this.summary,
    required this.subjects,
    required this.history,
    required this.legacyGrades,
    required this.attendance,
    required this.trends,
    required this.note,
  });

  factory StudentReport.fromJson(Map<String, dynamic> json) {
    final siswa = json['siswa'] as Map<String, dynamic>;
    return StudentReport(
      studentId: (siswa['id'] as num).toInt(),
      name: siswa['nama'] as String,
      nis: siswa['nis'] as String?,
      className: siswa['kelas'] as String,
      period: json['periode'] == null
          ? null
          : AcademicPeriod.fromJson(json['periode'] as Map<String, dynamic>),
      literasi: _double(json['skor_literasi']),
      numerasi: _double(json['skor_numerasi']),
      classification: classificationFromLabel(json['klasifikasi']),
      summary: ReportSummary.fromJson(json['ringkasan'] as Map<String, dynamic>? ?? const {}),
      subjects: [
        for (final m in json['mapel'] as List<dynamic>? ?? const [])
          ReportSubject.fromJson(m as Map<String, dynamic>),
      ],
      history: [
        for (final h in json['riwayat'] as List<dynamic>? ?? const [])
          ReportHistoryPeriod(
            period: AcademicPeriod.fromJson((h as Map<String, dynamic>)['periode'] as Map<String, dynamic>),
            classification: classificationFromLabel(h['klasifikasi']),
            subjects: [
              for (final m in h['mapel'] as List<dynamic>? ?? const [])
                (
                  id: ((m as Map<String, dynamic>)['mapel_id'] as num).toInt(),
                  name: m['nama'] as String,
                  status: GradeStatus.fromCode(m['status']),
                  finalScore: _double(m['nilai_akhir']),
                ),
            ],
          ),
      ],
      legacyGrades: (json['nilai_tanpa_mapel'] as num?)?.toInt() ?? 0,
      attendance: AttendanceTally.fromJson(json['kehadiran']),
      trends: TrendSet.fromJson(json['tren']),
      note: json['catatan'] as String?,
    );
  }

  final int studentId;
  final String name;
  final String? nis;
  final String className;
  final AcademicPeriod? period;
  final double? literasi;
  final double? numerasi;
  final Classification? classification;
  final ReportSummary summary;
  final List<ReportSubject> subjects;

  /// Periode yang punya nilai siswa ini, terlama dulu.
  final List<ReportHistoryPeriod> history;
  final int legacyGrades;
  final AttendanceTally attendance;
  final TrendSet trends;
  final String? note;
}

String formatScore(double? value) {
  if (value == null) return '—';
  return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

/// Satu titik tren mingguan dari backend (`tren.titik`). [weekStart] = Senin awal minggu.
/// Minggu tanpa data tidak dikirim (bukan nol).
@immutable
class TrendPoint {
  const TrendPoint({required this.weekStart, required this.value, required this.count});

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        weekStart: _date(json['tanggal']),
        value: (json['nilai'] as num).toDouble(),
        count: (json['jumlah'] as num?)?.toInt() ?? 0,
      );

  final DateTime weekStart;

  /// Rata-rata nilai minggu itu, atau persen hadir untuk kehadiran.
  final double value;

  /// Jumlah nilai (atau catatan absensi) yang membentuk titik ini.
  final int count;

  DateTime get weekEnd => weekStart.add(const Duration(days: 6));
}

@immutable
class TrendSet {
  const TrendSet({this.literasi = const [], this.numerasi = const [], this.attendance = const []});

  /// `json` = objek `titik`; kosong/tidak ada (backend lama) -> tanpa titik.
  factory TrendSet.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const TrendSet();
    List<TrendPoint> list(String key) => [
          for (final p in json[key] as List<dynamic>? ?? const [])
            TrendPoint.fromJson(p as Map<String, dynamic>),
        ];
    return TrendSet(literasi: list('literasi'), numerasi: list('numerasi'), attendance: list('kehadiran'));
  }

  static const empty = TrendSet();

  final List<TrendPoint> literasi;
  final List<TrendPoint> numerasi;
  final List<TrendPoint> attendance;
}
