import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/responsive_grid.dart';
import '../../../widgets/status_badge.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

const _weekdayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

class ParentAttendanceScreen extends ConsumerWidget {
  const ParentAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Kehadiran'),
        const SizedBox(height: 14),
        AsyncBody<List<HariKehadiran>>(
          value: ref.watch(attendanceRecordsProvider),
          onRetry: () => ref.invalidate(attendanceRecordsProvider),
          builder: (records) =>
              records.isEmpty ? const EmptyState('Belum ada data kehadiran.') : const _Content(),
        ),
      ],
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(attendanceMonthsProvider);
    final month = ref.watch(selectedMonthProvider)!;
    final summary = ref.watch(monthlyAttendanceSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChips(
          options: [
            for (final m in months) ('${m.year}-${m.month}', '${monthNameLong(m.month)} ${m.year}'),
          ],
          selected: '${month.year}-${month.month}',
          onSelected: (v) {
            ref.read(attendanceMonthProvider.notifier).set(months.firstWhere(
                  (m) => '${m.year}-${m.month}' == v,
                ));
            ref.read(attendanceDayProvider.notifier).set(0);
          },
        ),
        CustomCard(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryRow(summary: summary),
              ProgressBar(percent: summary.percent),
              const SizedBox(height: 6),
              Text(
                '${summary.percent}% kehadiran bulan ini',
                style: context.styleCaption.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        ResponsiveGrid(
          minItemWidth: 320,
          equalHeight: false,
          children: const [_CalendarCard(), _HistoryCard()],
        ),
        const SizedBox(height: 14),
        Text(
          'Kehadiran dicatat melalui pengenalan wajah atau input guru.',
          style: context.styleCaption.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in AttendanceStatus.values)
          Expanded(
            child: Column(
              children: [
                Text('${summary.countOf(s)}', style: context.styleNum.copyWith(fontSize: 24)),
                Text.rich(
                  TextSpan(
                    children: [
                      iconSpan(s.icon, c.st),
                      TextSpan(text: ' ${s.label}'),
                    ],
                  ),
                  style: context.styleCaption.copyWith(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarCard extends ConsumerWidget {
  const _CalendarCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final month = ref.watch(selectedMonthProvider)!;
    final selectedDay = ref.watch(attendanceDayProvider);
    final schoolDays = ref.watch(schoolDaysProvider);
    final byDay = {for (final d in schoolDays) d.hari: d.status};

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final selectedStatus = byDay[selectedDay];

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: context.styleBadge.copyWith(color: c.st, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingBlanks + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 48,
            ),
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = index - leadingBlanks + 1;
              final status = byDay[day];
              return _DayCell(
                day: day,
                status: status,
                selected: selectedDay == day,
                onTap: status == null
                    ? null
                    : () => ref.read(attendanceDayProvider.notifier).set(day),
              );
            },
          ),
          if (selectedStatus != null)
            InfoBanner(
              '',
              margin: const EdgeInsets.only(top: 10),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$selectedDay ${monthNameLong(month.month)} ${month.year}: '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: StatusBadge.attendance(selectedStatus),
                    ),
                    TextSpan(
                      text: switch (selectedStatus) {
                        AttendanceStatus.terlambat => ' · Datang setelah bel masuk',
                        AttendanceStatus.hadir => ' · Tercatat hadir',
                        _ => ' · Ada catatan dari guru',
                      },
                    ),
                  ],
                ),
                style: context.styleMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final AttendanceStatus? status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = status != null;

    return Semantics(
      button: enabled,
      label: enabled ? '$day ${status!.label}' : '$day',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: c.fo,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: selected ? Border.all(color: c.ink, width: 2) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day', style: context.styleBody.copyWith(fontSize: 13, height: 1.2)),
                  if (enabled)
                    Text(
                      statusGlyph(status!),
                      style: context.styleCaption.copyWith(fontSize: 11, color: c.sl, height: 1.2),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String statusGlyph(AttendanceStatus s) => switch (s) {
      AttendanceStatus.hadir => '✓',
      AttendanceStatus.terlambat => '◷',
      AttendanceStatus.izin => '✉',
      AttendanceStatus.sakit => '+',
      AttendanceStatus.alpa => '✕',
    };

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider)!;
    final filter = ref.watch(attendanceStatusFilterProvider);
    final history = ref.watch(attendanceHistoryProvider);
    final monthLabel = monthNameShort(month.month);

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Kick('Riwayat'),
          FilterChips(
            options: [
              ('all', 'Semua'),
              for (final s in AttendanceStatus.values) (s.name, s.label),
            ],
            selected: filter?.name ?? 'all',
            onSelected: (v) => ref.read(attendanceStatusFilterProvider.notifier).set(
                  v == 'all'
                      ? null
                      : AttendanceStatus.values.firstWhere((s) => s.name == v),
                ),
          ),
          if (history.isEmpty)
            const EmptyState('Tidak ada data pada status ini.')
          else
            RowList(
              children: [
                for (final d in history.take(8))
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text('${d.hari} $monthLabel', style: context.styleBold)),
                          StatusBadge.attendance(d.status),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
