import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import 'attendance_screen.dart';
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
    final distribution = ref.watch(distributionProvider);
    final data = ref.watch(currentClassDataProvider);

    return ScreenScaffold(
      title: 'Statistik Kelas',
      children: [
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
              DistributionBar(distribution),
            ],
          ),
        ),
        for (final (title, series) in [
          ('Tren nilai · Literasi', data.literasiTrend),
          ('Tren nilai · Numerasi', data.numerasiTrend),
          ('Tren kehadiran mingguan (%)', data.attendanceTrend),
        ])
          if (series.isNotEmpty)
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Kick(title),
                  Sparkline(series, height: 70),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Terbaru: '),
                        TextSpan(
                          text: '${series.last}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: context.styleCaption,
                  ),
                ],
              ),
            ),
        Text(
          'Klasifikasi adalah alat bantu, bukan penilaian akhir.',
          style: context.styleCaption,
        ),
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
        'Tren stabil dalam 6 pertemuan',
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
          child: Text(
            'Kondisi kelas saat ini · Diperbarui 07:45',
            style: context.styleMuted,
          ),
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
