import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../features/orang_tua/data/parent_models.dart' show HistoryItem, HistoryKind;
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';

/// Riwayat aktual dari backend.
///
/// Dengan siswa: riwayat nilai, kehadiran (selain Hadir), dan klasifikasi siswa itu (guru mapel
/// hanya melihat nilai mapel yang diampunya). Tanpa siswa: aktivitas absensi dan nilai kelas 14
/// hari terakhir.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, this.studentIndex});

  final int? studentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider(Scopes.history));
    final student = studentIndex == null ? null : ref.watch(studentsProvider)[studentIndex!];
    final chips = FilterChips(
      options: [
        ('all', 'Semua'),
        (HistoryKind.nilai.label, HistoryKind.nilai.label),
        (HistoryKind.kehadiran.label, HistoryKind.kehadiran.label),
        if (student != null) (HistoryKind.klasifikasi.label, HistoryKind.klasifikasi.label),
      ],
      selected: filter,
      onSelected: (v) => ref.read(filterProvider(Scopes.history).notifier).set(v),
    );

    if (student == null) {
      return ScreenScaffold(
        title: 'Riwayat Kelas',
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Aktivitas absensi dan nilai kelas Anda dalam 14 hari terakhir.',
              style: context.styleMuted,
            ),
          ),
          chips,
          AsyncBody<List<ActivityItem>>(
            value: ref.watch(activitiesAsyncProvider),
            onRetry: () => ref.invalidate(activitiesAsyncProvider),
            builder: (items) {
              final visible = [
                for (final a in items)
                  if (filter == 'all' || _activityKind(a).label == filter) a,
              ];
              if (visible.isEmpty) return const EmptyState('Belum ada aktivitas dalam 14 hari terakhir.');
              return Column(
                children: [
                  for (final a in visible)
                    TimelineEntry(date: a.when, title: _activityKind(a).label, description: a.title),
                ],
              );
            },
          ),
        ],
      );
    }

    final key = (ref.watch(selectedClassProvider), student.id);
    return ScreenScaffold(
      title: 'Riwayat Perkembangan',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(student.name, style: context.styleMuted),
        ),
        chips,
        AsyncBody<List<HistoryItem>>(
          value: ref.watch(studentHistoryProvider(key)),
          onRetry: () => ref.invalidate(studentHistoryProvider(key)),
          builder: (items) {
            final visible = [
              for (final e in items)
                if (filter == 'all' || e.kind.label == filter) e,
            ];
            if (visible.isEmpty) return const EmptyState('Belum ada riwayat perkembangan.');
            return Column(
              children: [
                for (final e in visible)
                  TimelineEntry(
                    date: formatDate(e.date),
                    title: '${e.kind.label} · ${e.title}',
                    description: e.description.isEmpty ? '—' : e.description,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

HistoryKind _activityKind(ActivityItem a) =>
    a.target.route == AppRoute.attendanceClass ? HistoryKind.kehadiran : HistoryKind.nilai;
