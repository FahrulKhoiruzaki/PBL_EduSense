import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

class ParentGradesScreen extends ConsumerWidget {
  const ParentGradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradeId = ref.watch(selectedGradeIdProvider);
    return gradeId == null ? const _GradeList() : _GradeDetail(gradeId: gradeId);
  }
}

class _GradeList extends ConsumerWidget {
  const _GradeList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades = ref.watch(filteredGradesProvider);
    final category = ref.watch(gradeCategoryFilterProvider);
    final query = ref.watch(gradeQueryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Nilai'),
        const SizedBox(height: 14),
        const ParentSearchField(hint: 'Cari jenis penilaian'),
        const SizedBox(height: 14),
        FilterChips(
          options: [
            ('all', 'Semua'),
            for (final k in SubjectCategory.values) (k.name, k.label),
          ],
          selected: category?.name ?? 'all',
          onSelected: (v) => ref.read(gradeCategoryFilterProvider.notifier).set(
                v == 'all' ? null : SubjectCategory.values.firstWhere((k) => k.name == v),
              ),
        ),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: grades.isEmpty
              ? EmptyState(query.isEmpty ? 'Belum ada data nilai.' : 'Nilai tidak ditemukan.')
              : RowList(
                  children: [
                    for (final g in grades)
                      InkWell(
                        onTap: () => ref.read(activeTabProvider.notifier).openGrade(g.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${g.kategori.label} · ${g.jenis}',
                                        style: context.styleBold,
                                      ),
                                      Text(
                                        formatDateLong(g.tanggal),
                                        style: context.styleCaption.copyWith(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  g.nilai >= g.sebelumnya ? '▲' : '▼',
                                  style: context.styleCaption.copyWith(fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                Text('${g.nilai}', style: context.styleNum.copyWith(fontSize: 24)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _GradeDetail extends ConsumerWidget {
  const _GradeDetail({required this.gradeId});

  final int gradeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeTabProvider.notifier);
    final grade = ref.watch(selectedKidProvider).nilaiById(gradeId);

    if (grade == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ParentBackLink('← Nilai', onTap: nav.back),
          const EmptyState('Nilai tidak ditemukan.'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParentBackLink('← Nilai', onTap: nav.back),
        const SizedBox(height: 4),
        const ParentTitle('Detail Nilai'),
        const SizedBox(height: 16),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Kick(grade.kategori.label),
              Text('${grade.nilai}', style: context.styleBig.copyWith(fontSize: 40, height: 44 / 40)),
              Text(
                '${grade.selisih >= 0 ? '▲' : '▼'} ${grade.selisih.abs()} dari sebelumnya (${grade.sebelumnya})',
                style: context.styleCaption.copyWith(fontSize: 13),
              ),
              RowList(
                children: [
                  InfoRow(label: 'Penilaian', value: Text(grade.jenis, style: context.styleBody)),
                  InfoRow(
                    label: 'Tanggal',
                    value: Text(formatDateLong(grade.tanggal), style: context.styleBody),
                  ),
                  InfoRow(label: 'Catatan guru', value: Text(grade.catatan, style: context.styleBody)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: CustomButton(
            label: 'Kembali ke Nilai',
            variant: ButtonVariant.outline,
            onPressed: nav.back,
          ),
        ),
      ],
    );
  }
}
