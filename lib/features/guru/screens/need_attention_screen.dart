import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import 'student_detail_screen.dart';

class NeedAttentionScreen extends ConsumerStatefulWidget {
  const NeedAttentionScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<NeedAttentionScreen> createState() => _NeedAttentionScreenState();
}

class _NeedAttentionScreenState extends ConsumerState<NeedAttentionScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final indexed = [for (var i = 0; i < students.length; i++) (index: i, student: students[i])];

    final absent = indexed.where((e) => !e.student.status.isPresent && e.student.status != AttendanceStatus.hadir).toList();
    final declining = indexed.where((e) => e.student.declining).toList();
    final needHelp =
        indexed.where((e) => e.student.classification == Classification.perlu).toList();

    final lists = [absent, declining, needHelp];
    final labels = ['Belum hadir', 'Nilai turun', 'Pendampingan'];
    final visible = lists[_tab];

    String subtitle(Student s) => switch (_tab) {
          0 => s.status.label,
          1 => s.name == 'Dimas Arya' ? 'Numerasi turun 12 poin' : 'Literasi turun 8 poin',
          _ => 'Perlu pendampingan',
        };

    return ScreenScaffold(
      title: 'Perlu Perhatian',
      children: [
        FilterChips(
          options: [
            for (var i = 0; i < labels.length; i++) ('$i', '${labels[i]} (${lists[i].length})'),
          ],
          selected: '$_tab',
          onSelected: (v) => setState(() => _tab = int.parse(v)),
        ),
        CustomCard(
          child: visible.isEmpty
              ? const EmptyState('Tidak ada siswa pada daftar ini.')
              : RowList(
                  children: [
                    for (final e in visible)
                      PersonRow(
                        name: e.student.name,
                        subtitle: subtitle(e.student),
                        trailing: StatusBadge.classification(e.student.classification),
                        onTap: () => pushPage(context, StudentDetailScreen(studentIndex: e.index)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
