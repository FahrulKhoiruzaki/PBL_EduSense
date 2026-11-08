import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

class ParentNotificationsScreen extends ConsumerWidget {
  const ParentNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeTabProvider.notifier);
    final notifier = ref.read(parentNotificationsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParentBackLink('← Beranda', onTap: nav.back),
        const ParentTitle('Notifikasi'),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: CustomButton(
            label: 'Tandai semua sudah dibaca',
            variant: ButtonVariant.secondary,
            onPressed: notifier.markAllRead,
          ),
        ),
        const SizedBox(height: 14),
        AsyncBody<List<ParentNotification>>(
          value: ref.watch(parentNotificationsProvider),
          onRetry: () => ref.invalidate(parentNotificationsProvider),
          builder: (items) => CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(18),
            child: items.isEmpty
                ? const EmptyState('Belum ada notifikasi.')
                : RowList(
                    children: [
                      for (final item in items)
                        InkWell(
                          onTap: () {
                            notifier.markRead(item.id);
                            if (item.gradeId != null) {
                              nav.openGrade(item.gradeId!);
                            } else if (item.tab != null) {
                              nav.openTab(ParentTab.values[item.tab!]);
                            }
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 52),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.read ? '' : '● '}${item.title}',
                                      style: context.styleBody.copyWith(
                                        fontWeight: item.read ? FontWeight.w500 : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, size: 20, color: context.colors.ink),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
