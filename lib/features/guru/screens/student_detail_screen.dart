import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import 'grades_screen.dart';
import 'history_screen.dart';

class StudentDetailScreen extends ConsumerWidget {
  const StudentDetailScreen({super.key, required this.studentIndex});

  final int studentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final s = ref.watch(studentsProvider)[studentIndex];
    final isWali = ref.watch(isWaliProvider);

    return ScreenScaffold(
      title: 'Detail Siswa',
      children: [
        CustomCard(
          child: Column(
            children: [
              Avatar(name: s.name, size: 72, fontSize: 22),
              const SizedBox(height: 8),
              Text(s.name, style: context.styleH2),
              Text('Kelas $cls', style: context.styleMuted),
              const SizedBox(height: 8),
              StatusBadge.classification(s.classification),
            ],
          ),
        ),
        TwoColumnGrid(
          children: [
            StatCard(label: 'Literasi', value: '${s.literasi}'),
            StatCard(label: 'Numerasi', value: '${s.numerasi}'),
            StatCard(
              label: 'Kehadiran',
              value: '${s.status == AttendanceStatus.alpa ? 78 : 93}%',
            ),
            StatCard(
              label: 'Terlambat',
              value: '${s.status == AttendanceStatus.terlambat ? 2 : 1}x',
            ),
          ],
        ),
        const SizedBox(height: 12),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Perkembangan'),
              Sparkline(
                [
                  s.literasi - 6,
                  s.literasi - 4,
                  s.literasi - 5,
                  s.literasi - 2,
                  s.literasi,
                ],
                height: 60,
              ),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Kehadiran hari ini'),
              StatusBadge.attendance(s.status),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Klasifikasi'),
              StatusBadge.classification(s.classification),
              const SizedBox(height: 8),
              Text(
                'Dasar penilaian: rata-rata literasi, rata-rata numerasi, kehadiran, keterlambatan, tren nilai. Diperbarui: 8 Oktober 2026. Klasifikasi adalah alat bantu, bukan penilaian akhir.',
                style: context.styleCaption,
              ),
            ],
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
                onPressed: () =>
                    pushPage(context, HistoryScreen(studentIndex: studentIndex)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
