import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
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

    final charts = <(String, List<int>, String)>[
      ('Literasi', kid.trenLiterasi, 'Garis naik berarti nilai membaik.'),
      ('Numerasi', kid.trenNumerasi, 'Garis datar berarti nilai stabil.'),
      ('Kehadiran (%)', kid.trenKehadiran, 'Semakin tinggi, semakin sering hadir.'),
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
            for (final (title, values, hint) in charts)
              CustomCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kick(title),
                    ParentLineChart(lastPoints(values, period.points)),
                    const SizedBox(height: 6),
                    Text(hint, style: context.styleCaption.copyWith(fontSize: 13)),
                  ],
                ),
              ),
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
