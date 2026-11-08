import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

class ParentHistoryScreen extends ConsumerWidget {
  const ParentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final entries = ref.watch(historyEntriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Riwayat Perkembangan'),
        const SizedBox(height: 14),
        FilterChips(
          options: [
            ('all', 'Semua'),
            for (final k in HistoryKind.values) (k.name, k.label),
          ],
          selected: filter?.name ?? 'all',
          onSelected: (v) => ref.read(historyFilterProvider.notifier).set(
                v == 'all' ? null : HistoryKind.values.firstWhere((k) => k.name == v),
              ),
        ),
        AsyncBody(
          value: ref.watch(historyAsyncProvider),
          onRetry: () => ref.invalidate(historyAsyncProvider),
          builder: (_) => entries.isEmpty
              ? const EmptyState('Belum ada riwayat perkembangan.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries)
                      TimelineItem(
                        date: '${formatDate(e.date)} · ${e.kind.label}',
                        title: e.title,
                        description: e.description,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
