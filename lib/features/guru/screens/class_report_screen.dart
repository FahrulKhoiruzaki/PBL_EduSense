import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/period_selector.dart';
import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/academic_charts.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';

/// Rekap nilai akhir dan status kelengkapan semua siswa x semua mapel kelas pada periode terpilih.
///
/// Wali kelas melihat seluruh mapel kelasnya (hanya lihat, tanpa hak input). Guru mapel hanya
/// melihat mapel yang ditugaskan kepadanya. Pembatasan dilakukan backend.
class ClassReportScreen extends ConsumerWidget {
  const ClassReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final isWali = ref.watch(isWaliProvider);
    return ScreenScaffold(
      title: 'Rekap Semua Mapel',
      banner: ref.watch(waliBannerProvider),
      children: [
        const PeriodSelector(),
        ref.watch(classReportProvider(cls)).when(
              loading: () => const LoadingList(count: 3),
              error: (e, _) =>
                  ErrorRetry(error: e, onRetry: () => ref.invalidate(classReportProvider(cls))),
              data: (report) => _ReportBody(report: report, classCode: cls, isWali: isWali),
            ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.classCode, required this.isWali});

  final ClassReport report;
  final String classCode;
  final bool isWali;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r.period == null) {
      return EmptyState(r.note ?? 'Periode akademik aktif belum ditetapkan admin.');
    }
    if (r.subjects.isEmpty) {
      return EmptyState(
        isWali
            ? 'Belum ada mata pelajaran yang berlaku untuk kelas $classCode pada ${r.period!.label}.'
            : 'Anda belum ditugaskan mengajar mata pelajaran di kelas $classCode.',
      );
    }
    if (r.students.isEmpty) return const EmptyState('Belum ada siswa di kelas ini.');

    final students = r.students.length;
    final allComplete = r.subjects.where((s) => s.complete == students).length;
    final notStarted = r.subjects.where((s) => s.notGraded == students).length;
    final partial = r.subjects.length - allComplete - notStarted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TwoColumnGrid(
          children: [
            StatCard(label: 'Siswa', value: '$students'),
            StatCard(label: 'Mata pelajaran', value: '${r.subjects.length}'),
            StatCard(label: 'Mapel lengkap semua siswa', value: '$allComplete'),
            StatCard(label: 'Mapel belum lengkap', value: '$partial'),
          ],
        ),
        if (notStarted > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$notStarted mata pelajaran belum dinilai sama sekali atau belum punya komponen.',
              style: context.styleCaption,
            ),
          ),
        const SizedBox(height: 12),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kick('Nilai akhir per mata pelajaran · ${r.period!.label}'),
              Text(
                'Baris = siswa, kolom = mata pelajaran (umum dan muatan lokal). Ketuk judul kolom '
                'untuk nama lengkap mapel.',
                style: context.styleCaption,
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  columns: [
                    const DataColumn(label: Text('Siswa')),
                    for (final s in r.subjects)
                      DataColumn(
                        tooltip: s.type == SubjectType.muatanLokal ? '${s.name} (Muatan Lokal)' : s.name,
                        label: Text(s.code),
                      ),
                  ],
                  rows: [
                    for (final st in r.students)
                      DataRow(cells: [
                        DataCell(Text(st.name)),
                        for (final cell in st.cells) DataCell(_Cell(cell)),
                      ]),
                  ],
                ),
              ),
              Text(gradeStatusLegend, style: context.styleCaption),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Status per mata pelajaran'),
              RowList(
                children: [
                  for (final s in r.subjects)
                    DetailRow(
                      label: s.name,
                      labelWidth: 150,
                      value: '${s.complete} lengkap · ${s.incomplete} belum lengkap · '
                          '${s.notGraded} belum dinilai · rata-rata '
                          '${s.average == null ? '—' : formatScore(s.average)}',
                    ),
                ],
              ),
            ],
          ),
        ),
        subjectComparisonPanel(r),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.cell);

  final SubjectCell cell;

  @override
  Widget build(BuildContext context) {
    final c = cell;
    if (c.finalScore != null) {
      return Semantics(
        label: 'Nilai akhir ${formatScore(c.finalScore)}, lengkap',
        child: Text(formatScore(c.finalScore), style: context.styleBold),
      );
    }
    final text = c.status == GradeStatus.belumLengkap
        ? '${c.status.short} ${c.filled}/${c.required}'
        : c.status.short;
    return Tooltip(
      message: c.status == GradeStatus.belumLengkap
          ? '${c.status.label}: ${c.filled} dari ${c.required} komponen'
          : c.status.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.status.icon, size: 14, color: context.colors.st),
          const SizedBox(width: 4),
          Text(text, style: context.styleMuted),
        ],
      ),
    );
  }
}
