import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../widgets/axis_chart.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/responsive_grid.dart';
import '../../../widgets/status_badge.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

class ParentStatsScreen extends ConsumerWidget {
  const ParentStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kid = ref.watch(selectedKidProvider);
    final period = ref.watch(statsPeriodProvider);
    final today = ref.watch(todayProvider);
    final where = kid.periode ?? 'semua data (periode belum ditetapkan sekolah)';
    List<ChartPoint> pts(List<TrendPoint> p) => weeklyChartPoints(pointsIn(p, period, today));
    final range = period == StatsPeriod.bulan ? 'bulan ini' : 'periode ini';

    final charts = [
      ChartPanel(
        title: 'Literasi',
        description:
            'Rata-rata nilai Literasi ${kid.nama} per minggu pada $where. Sumbu X = minggu '
            'penilaian, sumbu Y = nilai 0–100. Garis naik berarti nilai minggu itu lebih tinggi, '
            'bukan berarti seluruh kemampuan membaik.',
        points: pts(kid.trenTitik.literasi),
        xTitle: 'Minggu (tanggal awal)',
        yTitle: 'Nilai rata-rata',
        countLabel: 'nilai',
        emptyMessage: 'Belum ada nilai Literasi $range.',
        card: false,
      ),
      ChartPanel(
        title: 'Numerasi',
        description:
            'Rata-rata nilai Numerasi ${kid.nama} per minggu pada $where. Sumbu X = minggu '
            'penilaian, sumbu Y = nilai 0–100.',
        points: pts(kid.trenTitik.numerasi),
        xTitle: 'Minggu (tanggal awal)',
        yTitle: 'Nilai rata-rata',
        countLabel: 'nilai',
        emptyMessage: 'Belum ada nilai Numerasi $range.',
        tone: ChartTone.numerasi,
        card: false,
      ),
      ChartPanel(
        title: 'Kehadiran',
        description:
            'Persentase hari Hadir/Terlambat dari hari tercatat per minggu pada $where. '
            'Sumbu Y = persentase (%).',
        points: pts(kid.trenTitik.attendance),
        xTitle: 'Minggu (tanggal awal)',
        yTitle: 'Kehadiran (%)',
        unit: '%',
        countLabel: 'hari tercatat',
        tone: ChartTone.attendance,
        emptyMessage: 'Belum ada catatan kehadiran $range.',
        card: false,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Statistik'),
        const SizedBox(height: 14),
        FilterChips(
          options: [for (final p in StatsPeriod.values) (p.name, p.label)],
          selected: period.name,
          onSelected: (v) => ref
              .read(statsPeriodProvider.notifier)
              .set(StatsPeriod.values.firstWhere((p) => p.name == v)),
        ),
        ResponsiveGrid(
          minItemWidth: 320,
          equalHeight: false,
          children: [
            for (final chart in charts)
              CustomCard(margin: EdgeInsets.zero, padding: const EdgeInsets.all(18), child: chart),
            CustomCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Kick('Riwayat klasifikasi'),
                  RowList(
                    children: [
                      for (final r in kid.riwayatKlasifikasi)
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(child: Text(r.bulan, style: context.styleBold)),
                                StatusBadge.classification(r.klasifikasi),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
