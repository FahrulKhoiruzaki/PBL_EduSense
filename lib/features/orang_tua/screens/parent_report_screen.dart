import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/report_sections.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

/// Rapor akademik anak yang sedang dipilih: semua mapel (umum dan muatan lokal), komponen,
/// status kelengkapan, Literasi/Numerasi, klasifikasi, kehadiran, tren, dan riwayat per periode.
/// Data dibatasi backend ke anak milik akun ini.
class ParentReportScreen extends ConsumerWidget {
  const ParentReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Rapor Akademik'),
        const SizedBox(height: 12),
        const _PeriodPicker(),
        AsyncBody<StudentReport>(
          value: ref.watch(childReportProvider),
          onRetry: () => ref.invalidate(childReportProvider),
          builder: (report) => StudentReportView(
            report: report,
            subjectsTitle: 'Nilai seluruh mata pelajaran',
            noSubjectsMessage: 'Belum ada mata pelajaran yang tercatat untuk periode ini.',
          ),
        ),
      ],
    );
  }
}

class _PeriodPicker extends ConsumerWidget {
  const _PeriodPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reportPeriodProvider);
    return ref.watch(parentPeriodsProvider).when(
          loading: () => const SizedBox(height: 56),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(parentPeriodsProvider)),
          data: (periods) {
            if (periods.isEmpty) {
              return const InfoBanner('Sekolah belum menetapkan periode akademik.');
            }
            final active = periods.where((p) => p.active).firstOrNull;
            final value = periods.any((p) => p.id == selected) ? selected : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: 360,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('rapor-$value'),
                  initialValue: value,
                  isExpanded: true,
                  style: context.styleBody,
                  decoration: const InputDecoration(labelText: 'Tahun ajaran & semester'),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(active == null ? 'Periode aktif (belum ditetapkan)' : '${active.label} (aktif)'),
                    ),
                    for (final p in periods)
                      if (!p.active) DropdownMenuItem<int?>(value: p.id, child: Text(p.label)),
                  ],
                  onChanged: (v) => ref.read(reportPeriodProvider.notifier).set(v),
                ),
              ),
            );
          },
        );
  }
}
