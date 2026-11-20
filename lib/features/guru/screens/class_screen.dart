import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../widgets/period_selector.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/axis_chart.dart';
import '../../../widgets/classification_chart.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import 'attendance_screen.dart';
import 'class_report_screen.dart';
import 'grades_screen.dart';
import 'history_screen.dart';
import 'need_attention_screen.dart';
import 'students_screen.dart';

class ClassScreen extends ConsumerWidget {
  const ClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(attendanceSummaryProvider);
    final avgL = ref.watch(averageProvider(SubjectCategory.literasi));
    final avgN = ref.watch(averageProvider(SubjectCategory.numerasi));

    final menu = <(String, String, Widget)>[
      ('Nilai', 'Literasi $avgL · Numerasi $avgN', const GradesScreen()),
      (
        'Rekap Semua Mapel',
        ref.watch(isWaliProvider) ? 'Nilai seluruh mapel per siswa' : 'Nilai mapel yang Anda ampu',
        const ClassReportScreen(),
      ),
      ('Statistik Kelas', '${summary.percent}% kehadiran', const StatsScreen()),
      ('Now Brief', 'Kondisi kelas saat ini', const NowBriefScreen()),
      ('Siswa', '${summary.total} siswa', const StudentsScreen()),
    ];

    return ScreenScaffold(
      children: [
        Text('Kelas', style: context.styleH1),
        const SizedBox(height: 12),
        const ClassPill(),
        TwoColumnGrid(
          children: [
            for (final (title, subtitle, page) in menu)
              CustomCard(
                margin: EdgeInsets.zero,
                onTap: () => pushPage(context, page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.styleH2),
                    const SizedBox(height: 6),
                    Text(subtitle, style: context.styleCaption),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(attendanceSummaryProvider);
    final data = ref.watch(currentClassDataProvider);
    final cls = ref.watch(selectedClassProvider);
    final classification = ref.watch(classClassificationProvider(cls));

    return ScreenScaffold(
      title: 'Statistik Kelas',
      children: [
        const PeriodSelector(),
        TwoColumnGrid(
          children: [
            StatCard(label: 'Total siswa', value: '${summary.total}'),
            StatCard(label: 'Kehadiran', value: '${summary.percent}%'),
            StatCard(
              label: 'Literasi',
              value: '${ref.watch(averageProvider(SubjectCategory.literasi))}',
            ),
            StatCard(
              label: 'Numerasi',
              value: '${ref.watch(averageProvider(SubjectCategory.numerasi))}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Klasifikasi'),
              classification.when(
                loading: () => const LoadingList(count: 1, height: 96),
                error: (e, _) => ErrorRetry(
                  error: e,
                  onRetry: () => ref.invalidate(classClassificationProvider(cls)),
                ),
                data: (s) => ClassificationSummaryView(s),
              ),
            ],
          ),
        ),
        ...classTrendCharts(data),
        Text('Klasifikasi adalah alat bantu, bukan penilaian akhir.', style: context.styleCaption),
      ],
    );
  }
}

class NowBriefScreen extends ConsumerWidget {
  const NowBriefScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(attendanceSummaryProvider);
    final distribution = ref.watch(distributionProvider);
    final declining = ref.watch(decliningCountProvider);
    final data = ref.watch(currentClassDataProvider);
    final activities = ref.watch(activitiesProvider);
    final avgL = ref.watch(averageProvider(SubjectCategory.literasi));
    final avgN = ref.watch(averageProvider(SubjectCategory.numerasi));

    final cards = <(String, String, String, Widget)>[
      (
        'Kondisi kehadiran',
        'Kehadiran hari ini ${summary.percent}%',
        '${summary.absent} siswa belum hadir',
        const AttendanceClassScreen(),
      ),
      (
        'Kondisi akademik',
        'Literasi $avgL · Numerasi $avgN',
        data.period == null ? 'Lihat tren mingguan di Statistik Kelas' : 'Periode: ${data.period!.label}',
        const StatsScreen(),
      ),
      (
        'Perlu perhatian',
        '$declining siswa mengalami penurunan nilai',
        '${distribution.countOf(Classification.perlu)} siswa perlu pendampingan',
        const NeedAttentionScreen(initialTab: 2),
      ),
      (
        'Perubahan terbaru',
        activities.isNotEmpty ? activities[0].title : 'Belum ada aktivitas terbaru.',
        activities.length > 1 ? activities[1].title : '',
        const HistoryScreen(),
      ),
    ];

    return ScreenScaffold(
      title: 'Now Brief',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Kondisi kelas saat ini (data terbaru dari server)', style: context.styleMuted),
        ),
        for (final (kick, headline, detail, page) in cards)
          CustomCard(
            onTap: () => pushPage(context, page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Kick(kick),
                Text(headline, style: context.styleBold),
                Text(detail, style: context.styleMuted),
              ],
            ),
          ),
      ],
    );
  }
}

/// Grafik tren kelas (rata-rata nilai Literasi/Numerasi dan persen hadir per minggu) pada periode
/// yang dipilih. Minggu tanpa data tidak digambar.
List<Widget> classTrendCharts(ClassData data) {
  final period = data.period?.label ?? 'semua data (periode belum ditetapkan)';
  return [
    ChartPanel(
      title: 'Tren nilai Literasi kelas',
      description:
          'Rata-rata nilai Literasi seluruh siswa per minggu pada $period. '
          'Sumbu X = minggu penilaian, sumbu Y = nilai 0–100. Satu indikator tidak '
          'menggambarkan kemampuan siswa secara menyeluruh.',
      points: weeklyChartPoints(data.trendPoints.literasi),
      xTitle: 'Minggu (tanggal awal)',
      yTitle: 'Nilai rata-rata',
      countLabel: 'nilai',
      emptyMessage: 'Belum ada nilai Literasi pada periode ini.',
    ),
    ChartPanel(
      title: 'Tren nilai Numerasi kelas',
      description:
          'Rata-rata nilai Numerasi seluruh siswa per minggu pada $period. '
          'Sumbu X = minggu penilaian, sumbu Y = nilai 0–100.',
      points: weeklyChartPoints(data.trendPoints.numerasi),
      xTitle: 'Minggu (tanggal awal)',
      yTitle: 'Nilai rata-rata',
      countLabel: 'nilai',
      emptyMessage: 'Belum ada nilai Numerasi pada periode ini.',
      tone: ChartTone.numerasi,
    ),
    ChartPanel(
      title: 'Kehadiran mingguan kelas',
      description:
          'Persentase catatan Hadir dan Terlambat dari seluruh catatan absensi per '
          'minggu pada $period. Sumbu Y = persentase (%).',
      points: weeklyChartPoints(data.trendPoints.attendance),
      xTitle: 'Minggu (tanggal awal)',
      yTitle: 'Kehadiran (%)',
      unit: '%',
      countLabel: 'catatan absensi',
      tone: ChartTone.attendance,
      emptyMessage: 'Belum ada catatan absensi pada periode ini.',
    ),
  ];
}
