import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_common.dart';

class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(logTypeFilterProvider);
    final entries = ref.watch(filteredLogProvider);
    final page = paginate(entries, ref.watch(paginationPageProvider), AdminPageSize.log);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Log Aktivitas'),
        const AdminToolbar(search: AdminSearchField(hint: 'Cari aktivitas')),
        AdminChipBar<LogType?>(
          options: [(null, 'Semua'), for (final t in LogType.values) (t, t.label)],
          selected: type,
          onSelected: (v) {
            ref.read(logTypeFilterProvider.notifier).set(v);
            ref.read(paginationPageProvider.notifier).set(1);
          },
        ),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: entries.isEmpty
              ? const EmptyState('Belum ada aktivitas.')
              : Column(
                  children: [
                    RowList(children: [for (final e in page.items) LogRow(e)]),
                    PaginationBar(page: page.page, totalPages: page.totalPages, total: page.total),
                  ],
                ),
        ),
      ],
    );
  }
}
