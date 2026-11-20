import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import 'student_detail_screen.dart';

class StudentsScreen extends ConsumerWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final filter = ref.watch(filterProvider(Scopes.students));
    final list = ref.watch(studentListProvider);

    return ScreenScaffold(
      title: 'Siswa · Kelas $cls',
      children: [
        const SearchField(scope: Scopes.students, hint: 'Cari siswa'),
        FilterChips(
          options: [
            ('all', 'Semua'),
            for (final k in Classification.values) (k.code, k.label),
          ],
          selected: filter,
          onSelected: (v) => ref.read(filterProvider(Scopes.students).notifier).set(v),
        ),
        CustomCard(
          child: list.isEmpty
              ? const EmptyState('Siswa tidak ditemukan.')
              : RowList(
                  children: [
                    for (final e in list)
                      PersonRow(
                        name: e.student.name,
                        subtitle:
                            'Kelas $cls · Kehadiran ${e.student.status == AttendanceStatus.alpa ? 78 : 88 + e.index % 12}%',
                        trailing: StatusBadge.classification(e.student.classification),
                        onTap: () => pushPage(
                          context,
                          StudentDetailScreen(studentIndex: e.index),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
