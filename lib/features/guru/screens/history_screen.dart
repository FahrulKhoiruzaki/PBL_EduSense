import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/common_widgets.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, this.studentIndex});

  final int? studentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider(Scopes.history));
    final student = studentIndex == null ? null : ref.watch(studentsProvider)[studentIndex!];
    final summary = ref.watch(attendanceSummaryProvider);
    final distribution = ref.watch(distributionProvider);
    final avgLiterasi = ref.watch(averageProvider(SubjectCategory.literasi));
    final avgNumerasi = ref.watch(averageProvider(SubjectCategory.numerasi));

    final entries = <(String kind, String date, String text)>[
      (
        'Kehadiran',
        '8 Okt 2026',
        student != null
            ? student.status.label + (student.time.isEmpty ? '' : ' · ${student.time}')
            : 'Kehadiran kelas ${summary.percent}%',
      ),
      (
        'Nilai',
        '6 Okt 2026',
        student != null
            ? 'Literasi ${student.literasi} · Numerasi ${student.numerasi}'
            : 'Rata-rata Literasi $avgLiterasi · Numerasi $avgNumerasi',
      ),
      (
        'Klasifikasi',
        '1 Okt 2026',
        student != null
            ? student.classification.label
            : 'Mahir ${distribution.countOf(Classification.mahir)} · Cukup ${distribution.countOf(Classification.cukup)} · Perlu Pendampingan ${distribution.countOf(Classification.perlu)}',
      ),
      (
        'Nilai',
        '22 Sep 2026',
        student != null
            ? 'Literasi ${student.literasi - 3} · Numerasi ${student.numerasi - 2}'
            : 'Rata-rata Literasi 76 · Numerasi 72',
      ),
      (
        'Kehadiran',
        '19 Sep 2026',
        student != null ? 'Hadir 07:05' : 'Kehadiran kelas 91%',
      ),
    ];
    final visible = [
      for (final e in entries)
        if (filter == 'all' || e.$1 == filter) e,
    ];

    return ScreenScaffold(
      title: student != null ? 'Riwayat Perkembangan' : 'Riwayat Kelas',
      children: [
        if (student != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(student.name, style: context.styleMuted),
          ),
        FilterChips(
          options: const [
            ('all', 'Semua'),
            ('Nilai', 'Nilai'),
            ('Kehadiran', 'Kehadiran'),
            ('Klasifikasi', 'Klasifikasi'),
          ],
          selected: filter,
          onSelected: (v) => ref.read(filterProvider(Scopes.history).notifier).set(v),
        ),
        if (visible.isEmpty)
          const EmptyState('Belum ada riwayat perkembangan.')
        else
          for (final e in visible)
            TimelineEntry(date: e.$2, title: e.$1, description: e.$3),
      ],
    );
  }
}
