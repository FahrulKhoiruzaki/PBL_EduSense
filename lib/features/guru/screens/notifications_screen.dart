import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../core/theme.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsAsyncProvider);
    final notifications = ref.watch(notificationsProvider);

    return ScreenScaffold(
      title: 'Notifikasi',
      children: [
        if (async.isLoading && !async.hasValue)
          const LoadingList()
        else if (async.hasError && !async.hasValue)
          ErrorRetry(
            error: async.error!,
            onRetry: () => ref.invalidate(notificationsAsyncProvider),
          )
        else if (notifications.isEmpty)
          const EmptyState('Belum ada notifikasi.')
        else ...[
          CustomButton(
            label: 'Tandai semua sudah dibaca',
            variant: ButtonVariant.secondary,
            expanded: true,
            onPressed: () => ref.read(notificationsAsyncProvider.notifier).markAllRead(),
          ),
          for (final group in NotificationGroup.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Kick(group.label),
            ),
            CustomCard(
              child: _GroupRows(group: group, notifications: notifications),
            ),
          ],
        ],
      ],
    );
  }
}

class _GroupRows extends ConsumerWidget {
  const _GroupRows({required this.group, required this.notifications});

  final NotificationGroup group;
  final List<AppNotification> notifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [
      for (var i = 0; i < notifications.length; i++)
        if (notifications[i].group == group)
          NavRow(
            title: '${notifications[i].read ? '' : '● '}${notifications[i].title}',
            onTap: () {
              ref.read(notificationsAsyncProvider.notifier).markRead(notifications[i].id);
              pushPage(context, NotificationDetailScreen(index: i));
            },
          ),
    ];
    return rows.isEmpty
        ? const EmptyState('Belum ada notifikasi.')
        : RowList(children: rows);
  }
}

class NotificationDetailScreen extends ConsumerWidget {
  const NotificationDetailScreen({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final item = index < notifications.length ? notifications[index] : null;

    return ScreenScaffold(
      title: 'Detail Notifikasi',
      children: [
        if (item == null)
          const EmptyState('Notifikasi tidak ditemukan.')
        else
          CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: context.styleH2),
                const SizedBox(height: 8),
                Text(item.group.label, style: context.styleMuted),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'Buka halaman terkait',
                  onPressed: () => openTarget(context, item.target),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    final item = index < activities.length ? activities[index] : null;
    final session = ref.watch(sessionProvider);
    final cls = ref.watch(selectedClassProvider);

    return ScreenScaffold(
      title: 'Detail Aktivitas',
      children: [
        if (item == null)
          const EmptyState('Aktivitas tidak ditemukan.')
        else
          CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: context.styleH2),
                const SizedBox(height: 8),
                Text(
                  'Oleh ${session.displayName} · Kelas $cls · ${item.when}',
                  style: context.styleMuted,
                ),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'Buka halaman terkait',
                  onPressed: () => openTarget(context, item.target),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
