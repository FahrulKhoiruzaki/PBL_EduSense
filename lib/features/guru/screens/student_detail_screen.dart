import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../widgets/period_selector.dart';
import '../../../core/theme.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/report_sections.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import 'grades_screen.dart';
import 'history_screen.dart';

/// Detail akademik siswa. Semua angka berasal dari rapor backend pada periode terpilih; wali
/// kelas melihat seluruh mapel, guru mapel hanya mapel yang diampu (dibatasi backend).
class StudentDetailScreen extends ConsumerWidget {
  const StudentDetailScreen({super.key, required this.studentIndex});

  final int studentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final s = ref.watch(studentsProvider)[studentIndex];
    final isWali = ref.watch(isWaliProvider);
    final key = (cls, s.id);

    return ScreenScaffold(
      title: 'Detail Siswa',
      banner: ref.watch(waliBannerProvider),
      children: [
        CustomCard(
          child: Column(
            children: [
              Avatar(name: s.name, size: 72, fontSize: 22),
              const SizedBox(height: 8),
              Text(s.name, style: context.styleH2),
              Text('Kelas $cls', style: context.styleMuted),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  StatusBadge.classification(s.classification),
                  StatusBadge.attendance(s.status),
                ],
              ),
              Text('Kehadiran hari ini: ${s.status.label}${s.time.isEmpty ? '' : ' · ${s.time}'}',
                  style: context.styleCaption),
            ],
          ),
        ),
        const PeriodSelector(),
        ref.watch(studentReportProvider(key)).when(
              loading: () => const LoadingList(count: 3),
              error: (e, _) =>
                  ErrorRetry(error: e, onRetry: () => ref.invalidate(studentReportProvider(key))),
              data: (report) => StudentReportView(
                report: report,
                subjectsTitle:
                    isWali ? 'Nilai seluruh mata pelajaran' : 'Nilai mata pelajaran yang Anda ampu',
                noSubjectsMessage: isWali
                    ? 'Belum ada mata pelajaran yang berlaku pada periode ini.'
                    : 'Anda belum ditugaskan mengajar mata pelajaran di kelas ini.',
              ),
            ),
        Row(
          children: [
            if (!isWali) ...[
              Expanded(
                child: CustomButton(
                  label: 'Tambah Nilai',
                  variant: ButtonVariant.outline,
                  expanded: true,
                  onPressed: () => showGradeFormSheet(context, openGradesAfter: true),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: CustomButton(
                label: 'Riwayat Perkembangan',
                expanded: true,
                onPressed: () => pushPage(context, HistoryScreen(studentIndex: studentIndex)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
