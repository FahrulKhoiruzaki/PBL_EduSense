import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../core/formatters.dart';
import '../navigation/tab_navigation.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import 'grades_screen.dart';
import 'history_screen.dart';
import 'need_attention_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'students_screen.dart';
import 'class_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(classDataAsyncProvider(cls)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              AsyncBody<ClassData>(
                value: ref.watch(currentClassAsyncProvider),
                onRetry: () => ref.invalidate(classDataAsyncProvider(cls)),
                loading: Column(
                  children: [for (var i = 0; i < 5; i++) const SkeletonBlock()],
                ),
                builder: (_) => const _HomeContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final cls = ref.watch(selectedClassProvider);
    final data = ref.watch(currentClassDataProvider);
    final today = ref.watch(todayProvider);
    final summary = ref.watch(attendanceSummaryProvider);
    final distribution = ref.watch(distributionProvider);
    final declining = ref.watch(decliningCountProvider);
    final activities = ref.watch(activitiesProvider);
    final hasUnread = ref.watch(hasUnreadNotificationsProvider);
    final isWali = session.isWali;
    final c = context.colors;

    final quickActions = <(String, VoidCallback)>[
      if (isWali) ...[
        ('Daftar Hadir', () => goTab(ref, 1)),
        ('Lihat Nilai', () => pushPage(context, const GradesScreen())),
      ] else ...[
        ('Absen', () => goTab(ref, 1)),
        ('Tambah Nilai', () => showGradeFormSheet(context, openGradesAfter: true)),
      ],
      ('Daftar Siswa', () => pushPage(context, const StudentsScreen())),
      ('Statistik', () => pushPage(context, const StatsScreen())),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Avatar(
                name: session.displayName,
                onTap: () => pushPage(context, const ProfileScreen()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatFullDate(today)} · ${isWali ? 'Wali Kelas $cls' : 'Guru Mapel'}',
                      style: context.styleCaption,
                    ),
                    Text('Selamat pagi, ${session.displayName}', style: context.styleH2),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Notifikasi',
                onPressed: () => pushPage(context, const NotificationsScreen()),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none, size: 24),
                    if (hasUnread)
                      Positioned(
                        top: 0,
                        right: 1,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c.ink,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.fo, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Kick('Kelas aktif'),
        const ClassPill(),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(child: Kick('Ringkasan hari ini', bottom: 0)),
                  const SizedBox(width: 8),
                  _ClassChip(label: 'Kelas $cls', onTap: () => showClassPicker(context)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${summary.percent}%', style: context.styleBig),
              Text(
                'kehadiran · ${summary.present} dari ${summary.total} siswa',
                style: context.styleMuted,
              ),
              ProgressBar(percent: summary.percent),
              FiveStats(summary),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Perkembangan kelas'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _TrendBlock(
                      label: 'Rata-rata Literasi',
                      value: ref.watch(averageProvider(SubjectCategory.literasi)),
                      series: data.literasiTrend,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TrendBlock(
                      label: 'Rata-rata Numerasi',
                      value: ref.watch(averageProvider(SubjectCategory.numerasi)),
                      series: data.numerasiTrend,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DistributionBar(distribution),
              const SizedBox(height: 12),
              CustomButton(
                label: 'Lihat Statistik',
                variant: ButtonVariant.secondary,
                expanded: true,
                onPressed: () => pushPage(context, const StatsScreen()),
              ),
            ],
          ),
        ),
        const Kick('Aksi cepat'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TwoColumnGrid(
            children: [
              for (final (label, onTap) in quickActions)
                CustomButton(
                  label: label,
                  variant: ButtonVariant.outline,
                  surfaceFill: true,
                  expanded: true,
                  onPressed: onTap,
                ),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Perlu perhatian'),
              RowList(
                children: [
                  NavRow(
                    title: '${summary.absent} siswa belum hadir',
                    subtitle: 'Izin, sakit, atau alpa',
                    onTap: () => pushPage(context, const NeedAttentionScreen(initialTab: 0)),
                  ),
                  NavRow(
                    title: '$declining siswa mengalami penurunan nilai',
                    onTap: () => pushPage(context, const NeedAttentionScreen(initialTab: 1)),
                  ),
                  NavRow(
                    title: '${distribution.countOf(Classification.perlu)} siswa perlu pendampingan',
                    onTap: () => pushPage(context, const NeedAttentionScreen(initialTab: 2)),
                  ),
                ],
              ),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Aktivitas terbaru'),
              if (activities.isEmpty)
                const EmptyState('Belum ada aktivitas terbaru.')
              else
                RowList(
                  children: [
                    for (var i = 0; i < activities.length && i < 4; i++)
                      NavRow(
                        title: activities[i].title,
                        subtitle: activities[i].when,
                        onTap: () => pushPage(context, ActivityDetailScreen(index: i)),
                      ),
                  ],
                ),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Perkembangan minggu ini'),
              for (final (label, series) in [
                ('Kehadiran', data.attendanceTrend),
                ('Literasi', data.literasiTrend),
                ('Numerasi', data.numerasiTrend),
              ])
                if (series.isNotEmpty)
                Row(
                  children: [
                    SizedBox(width: 76, child: Text(label, style: context.styleBody)),
                    const SizedBox(width: 12),
                    Expanded(child: Sparkline(series, height: 32)),
                    const SizedBox(width: 12),
                    Text('${series.last}', style: context.styleBold),
                  ],
                ),
              const SizedBox(height: 8),
              CustomButton(
                label: 'Lihat Riwayat',
                variant: ButtonVariant.secondary,
                expanded: true,
                onPressed: () => pushPage(context, const HistoryScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendBlock extends StatelessWidget {
  const _TrendBlock({required this.label, required this.value, required this.series});

  final String label;
  final int value;
  final List<int> series;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.styleCaption),
        Text('$value', style: context.styleNum),
        Sparkline(series, height: 36),
      ],
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.mi,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: context.styleBadge),
              const Icon(Icons.keyboard_arrow_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
