import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/classification_chart.dart';
import '../../../widgets/custom_card.dart';
import '../providers/academic_providers.dart';
import '../providers/admin_data_provider.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import 'grade_components_screen.dart';

class ClassificationAdminScreen extends ConsumerWidget {
  const ClassificationAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodId = ref.watch(effectivePeriodIdProvider);
    final classCode = ref.watch(classificationClassFilterProvider);
    final classCodes = ref.watch(adminDataProvider).value?.classes.keys.toList() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Klasifikasi Siswa'),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Hasil perhitungan berbasis aturan periode (bukan machine learning). Persentase '
            'dihitung dari siswa yang sudah terklasifikasi; siswa dengan data belum lengkap atau '
            'tanpa nilai ditampilkan terpisah. Klasifikasi adalah alat bantu, bukan penilaian akhir.',
            style: context.styleSoft,
          ),
        ),
        AsyncBody<List<AdminPeriod>>(
          value: ref.watch(adminPeriodsProvider),
          onRetry: () => ref.invalidate(adminPeriodsProvider),
          builder: (periods) {
            if (periods.isEmpty || periodId == null) {
              return const CmsEmpty(
                'Belum ada periode akademik. Buat periode di menu Periode Akademik terlebih dahulu.',
              );
            }
            final key = (periodId, classCode);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  children: [
                    AcademicPeriodPicker(periods: periods, selected: periodId),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SizedBox(
                        width: 200,
                        child: AdminDropdown<String>(
                          semanticLabel: 'Kelas',
                          value: classCode ?? '',
                          items: ['', ...classCodes, if (classCode != null && !classCodes.contains(classCode)) classCode],
                          itemLabel: (c) => c.isEmpty ? 'Semua kelas' : 'Kelas $c',
                          onChanged: (c) => ref
                              .read(classificationClassFilterProvider.notifier)
                              .set(c.isEmpty ? null : c),
                        ),
                      ),
                    ),
                  ],
                ),
                AsyncBody<ClassificationSummary>(
                  value: ref.watch(adminClassificationProvider(key)),
                  onRetry: () => ref.invalidate(adminClassificationProvider(key)),
                  builder: (summary) => CustomCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          classCode == null
                              ? 'Seluruh sekolah · ${summary.period?.label ?? ''}'
                              : 'Kelas $classCode · ${summary.period?.label ?? ''}',
                          style: context.styleH2,
                        ),
                        const SizedBox(height: 12),
                        ClassificationSummaryView(summary, showPerClass: classCode == null),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
