import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/academic_models.dart';
import 'axis_chart.dart';
import 'status_badge.dart';

/// Status kelengkapan penilaian dengan ikon + teks (tidak hanya warna).
class GradeStatusBadge extends StatelessWidget {
  const GradeStatusBadge(this.status, {super.key, this.filled, this.required});

  final GradeStatus status;
  final int? filled;
  final int? required;

  @override
  Widget build(BuildContext context) {
    final progress = status == GradeStatus.belumLengkap && filled != null && required != null
        ? ' $filled/$required'
        : '';
    return StatusBadge(
      label: '${status.label}$progress',
      icon: status.icon,
      variant: status == GradeStatus.lengkap ? BadgeVariant.cukup : BadgeVariant.plain,
    );
  }
}

extension GradeStatusIcon on GradeStatus {
  IconData get icon => switch (this) {
    GradeStatus.lengkap => Icons.check_circle_outline,
    GradeStatus.belumLengkap => Icons.timelapse,
    GradeStatus.belumDinilai => Icons.remove_circle_outline,
    GradeStatus.belumAdaKomponen => Icons.help_outline,
  };
}

const gradeStatusLegend =
    'L = lengkap · BL = belum lengkap (komponen terisi/wajib) · BD = belum dinilai · '
    'BK = komponen belum ditetapkan admin. Nilai akhir hanya ada bila semua komponen aktif sudah '
    'dinilai.';

/// Skala Y untuk jumlah siswa: kelipatan bulat agar garis bantu jatuh di angka utuh.
(double, double) countScale(int maxCount) {
  final step = math.max(1, (maxCount / 4).ceil()).toDouble();
  return (step * 4, step);
}

/// Rentang tampilan untuk grafik distribusi (bukan aturan sekolah; hanya pengelompokan visual).
const _bins = [
  (0.0, 59.99, '< 60'),
  (60.0, 69.99, '60–69'),
  (70.0, 79.99, '70–79'),
  (80.0, 89.99, '80–89'),
  (90.0, 100.0, '90–100'),
];

/// Distribusi nilai akhir siswa berstatus lengkap (siswa lain tidak dihitung, bukan nol).
Widget gradeDistributionPanel({
  required List<double> finals,
  required int students,
  required String context,
}) {
  final counts = [for (final (lo, hi, _) in _bins) finals.where((v) => v >= lo && v <= hi).length];
  final (yMax, yStep) = countScale(counts.fold(0, math.max));
  return ChartPanel(
    title: 'Distribusi nilai akhir',
    description:
        'Jumlah siswa per rentang nilai akhir $context. Hanya ${finals.length} dari '
        '$students siswa yang penilaiannya sudah lengkap ikut dihitung. Sumbu X = rentang nilai '
        '(kategori, bukan waktu), sumbu Y = jumlah siswa.',
    points: finals.isEmpty
        ? const []
        : [
            for (var i = 0; i < _bins.length; i++)
              ChartPoint(
                label: _bins[i].$3,
                detail: 'Nilai ${_bins[i].$3}',
                value: counts[i].toDouble(),
              ),
          ],
    kind: ChartKind.bar,
    xTitle: 'Rentang nilai akhir',
    yTitle: 'Jumlah siswa',
    tone: ChartTone.subject,
    yMax: yMax,
    yStep: yStep,
    emptyMessage:
        'Belum ada siswa dengan penilaian lengkap, jadi distribusi belum dapat ditampilkan.',
  );
}

/// Rata-rata nilai akhir kelas per periode (hanya periode yang sudah punya nilai akhir).
Widget subjectProgressPanel(String subject, List<SubjectProgress> progress) {
  final withScore = [
    for (final p in progress)
      if (p.average != null) p,
  ];
  return ChartPanel(
    title: 'Perkembangan nilai akhir $subject',
    description:
        'Rata-rata nilai akhir siswa berstatus lengkap di kelas ini pada setiap periode '
        'akademik. Sumbu X = periode, sumbu Y = nilai 0–100.',
    points: [
      for (final p in withScore)
        ChartPoint(
          label: '${p.period.semesterLabel} ${_shortYear(p.period.academicYear)}',
          detail: p.period.label,
          value: p.average!,
          date: p.period.start,
          count: p.complete,
        ),
    ],
    xTitle: 'Periode akademik',
    yTitle: 'Rata-rata nilai akhir',
    tone: ChartTone.subject,
    countLabel: 'siswa lengkap',
    emptyMessage: 'Belum ada periode dengan nilai akhir lengkap untuk mapel ini.',
  );
}

String _shortYear(String academicYear) => academicYear.length == 9
    ? '${academicYear.substring(2, 4)}/${academicYear.substring(7)}'
    : academicYear;

/// Perbandingan rata-rata nilai akhir antarmapel. Mapel tanpa nilai akhir tidak digambar (bukan
/// nol); namanya disebut di keterangan.
Widget subjectComparisonPanel(ClassReport report) {
  final scored = [
    for (final s in report.subjects)
      if (s.average != null) s,
  ];
  final missing = [
    for (final s in report.subjects)
      if (s.average == null) s.code,
  ];
  return ChartPanel(
    title: 'Perbandingan rata-rata nilai antarmapel',
    description:
        'Rata-rata nilai akhir siswa berstatus lengkap per mata pelajaran pada '
        '${report.period?.label ?? 'periode ini'}. Sumbu X = mata pelajaran (kategori), sumbu Y = '
        'nilai 0–100.${missing.isEmpty ? '' : ' Belum ada nilai akhir: ${missing.join(', ')}.'}',
    points: [
      for (final s in scored)
        ChartPoint(label: s.code, detail: s.name, value: s.average!, count: s.complete),
    ],
    kind: ChartKind.bar,
    xTitle: 'Mata pelajaran',
    yTitle: 'Rata-rata nilai akhir',
    tone: ChartTone.subject,
    countLabel: 'siswa lengkap',
    emptyMessage: 'Belum ada mata pelajaran dengan nilai akhir lengkap pada periode ini.',
  );
}
