import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/academic_models.dart';
import 'academic_charts.dart';
import 'axis_chart.dart';
import 'common_widgets.dart';
import 'custom_card.dart';
import 'status_badge.dart';

String reportScore(double? v) => v == null ? '—' : formatScore(v);

/// Isi rapor akademik satu siswa (backend `RaporOut`), dipakai aplikasi guru dan portal orang tua.
class StudentReportView extends StatelessWidget {
  const StudentReportView({
    super.key,
    required this.report,
    required this.subjectsTitle,
    required this.noSubjectsMessage,
  });

  final StudentReport report;
  final String subjectsTitle;
  final String noSubjectsMessage;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final a = r.attendance;
    final where = r.period?.label ?? 'semua data (periode belum ditetapkan)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TwoColumnGrid(
          children: [
            StatCard(label: 'Skor Literasi', value: reportScore(r.literasi)),
            StatCard(label: 'Skor Numerasi', value: reportScore(r.numerasi)),
            StatCard(
              label: 'Kehadiran',
              value: a.percent == null ? '—' : '${chartNumber(a.percent!)}%',
            ),
            StatCard(label: 'Terlambat', value: a.total == 0 ? '—' : '${a.terlambat}x'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            a.total == 0
                ? 'Belum ada catatan absensi pada $where.'
                : 'Dari ${a.total} hari tercatat pada $where: Hadir ${a.hadir}, Terlambat '
                      '${a.terlambat}, Izin ${a.izin}, Sakit ${a.sakit}, Alpa ${a.alpa}.',
            style: context.styleCaption,
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Klasifikasi'),
              StatusBadge.classification(r.classification),
              const SizedBox(height: 8),
              Text(
                r.note ??
                    'Dihitung dari skor Literasi dan Numerasi sesuai aturan klasifikasi periode yang '
                        'ditetapkan admin. Klasifikasi adalah alat bantu, bukan penilaian akhir.',
                style: context.styleCaption,
              ),
            ],
          ),
        ),
        ChartPanel(
          title: 'Perkembangan Literasi',
          description:
              'Rata-rata nilai Literasi ${r.name} per minggu pada $where. Sumbu X = minggu '
              'penilaian, sumbu Y = nilai 0–100.',
          points: weeklyChartPoints(r.trends.literasi),
          xTitle: 'Minggu (tanggal awal)',
          yTitle: 'Nilai rata-rata',
          countLabel: 'nilai',
          emptyMessage: 'Belum ada nilai Literasi pada periode ini.',
        ),
        ChartPanel(
          title: 'Perkembangan Numerasi',
          description:
              'Rata-rata nilai Numerasi ${r.name} per minggu pada $where. Sumbu X = minggu '
              'penilaian, sumbu Y = nilai 0–100.',
          points: weeklyChartPoints(r.trends.numerasi),
          xTitle: 'Minggu (tanggal awal)',
          yTitle: 'Nilai rata-rata',
          countLabel: 'nilai',
          emptyMessage: 'Belum ada nilai Numerasi pada periode ini.',
          tone: ChartTone.numerasi,
        ),
        ChartPanel(
          title: 'Kehadiran mingguan',
          description: 'Persentase hari Hadir/Terlambat dari hari tercatat per minggu pada $where.',
          points: weeklyChartPoints(r.trends.attendance),
          xTitle: 'Minggu (tanggal awal)',
          yTitle: 'Kehadiran (%)',
          unit: '%',
          countLabel: 'hari tercatat',
          tone: ChartTone.attendance,
          emptyMessage: 'Belum ada catatan absensi pada periode ini.',
        ),
        _SubjectsCard(report: r, title: subjectsTitle, noSubjectsMessage: noSubjectsMessage),
        _HistoryCard(report: r),
      ],
    );
  }
}

class _SubjectsCard extends StatelessWidget {
  const _SubjectsCard({required this.report, required this.title, required this.noSubjectsMessage});

  final StudentReport report;
  final String title;
  final String noSubjectsMessage;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final s = r.summary;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kick(title),
          if (r.period == null)
            EmptyState(r.note ?? 'Periode akademik aktif belum ditetapkan admin.')
          else if (r.subjects.isEmpty)
            EmptyState(noSubjectsMessage)
          else ...[
            Text(
              '${s.subjects} mapel · ${s.complete} lengkap · ${s.incomplete} belum lengkap · '
              '${s.notGraded} belum dinilai · ${s.noComponents} belum ada komponen',
              style: context.styleBold,
            ),
            Text(
              s.average == null
                  ? 'Rata-rata nilai akhir belum tersedia (belum ada mapel yang lengkap).'
                  : 'Rata-rata nilai akhir mapel yang lengkap: ${formatScore(s.average)}',
              style: context.styleCaption,
            ),
            if (r.legacyGrades > 0)
              Text(
                '${r.legacyGrades} nilai lama tanpa mata pelajaran tidak masuk rekap per mapel.',
                style: context.styleCaption,
              ),
            for (final m in r.subjects) _SubjectTile(m),
          ],
        ],
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile(this.subject);

  final ReportSubject subject;

  @override
  Widget build(BuildContext context) {
    final m = subject;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        m.type == SubjectType.muatanLokal ? '${m.name} (Muatan Lokal)' : m.name,
        style: context.styleBold,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            GradeStatusBadge(m.status, filled: m.filled, required: m.required),
            const SizedBox(width: 8),
            Text('Nilai akhir: ${reportScore(m.finalScore)}', style: context.styleBody),
          ],
        ),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.components.isEmpty)
          const EmptyState('Komponen penilaian belum ditetapkan admin.')
        else ...[
          for (final k in m.components)
            DetailRow(
              label: [
                k.component.name,
                if (k.component.weight != null) 'bobot ${formatScore(k.component.weight)}',
                if (k.component.category != null) k.component.category!.label,
                if (!k.component.active) 'nonaktif',
              ].join(' · '),
              labelWidth: 190,
              value: k.value == null
                  ? 'Belum dinilai'
                  : '${formatScore(k.value)} (${k.count} nilai)',
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              m.status == GradeStatus.lengkap
                  ? (m.weighted
                        ? 'Nilai akhir = rata-rata berbobot komponen.'
                        : 'Nilai akhir = rata-rata komponen.')
                  : 'Nilai akhir muncul setelah semua komponen aktif dinilai.',
              style: context.styleCaption,
            ),
          ),
        ],
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.report});

  final StudentReport report;

  @override
  Widget build(BuildContext context) {
    final history = report.history;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Kick('Riwayat nilai akhir per periode'),
          if (history.isEmpty)
            const EmptyState('Belum ada nilai pada periode mana pun.')
          else
            for (final h in history.reversed) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(h.period.label, style: context.styleBold)),
                    StatusBadge.classification(h.classification),
                  ],
                ),
              ),
              if (h.subjects.isEmpty)
                Text('Tidak ada nilai mapel yang dapat ditampilkan.', style: context.styleCaption)
              else
                for (final m in h.subjects)
                  DetailRow(
                    label: m.name,
                    labelWidth: 170,
                    value: m.finalScore == null ? m.status.label : formatScore(m.finalScore),
                  ),
            ],
        ],
      ),
    );
  }
}
