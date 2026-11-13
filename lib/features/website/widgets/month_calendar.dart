import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../data/calendar_math.dart';
import '../data/website_models.dart';
import 'website_common.dart';

String calendarRange(CalendarEvent e) {
  final end = e.selesai;
  if (end == null || dateOnly(end) == dateOnly(e.mulai)) return formatDateLong(e.mulai);
  return '${formatDateLong(e.mulai)} – ${formatDateLong(end)}';
}

/// Kalender bulanan: grid tanggal, navigasi bulan, indikator kegiatan, dan daftar kegiatan
/// untuk tanggal yang dipilih (atau seluruh kegiatan bulan itu bila belum ada tanggal dipilih).
class MonthCalendar extends ConsumerStatefulWidget {
  const MonthCalendar({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  ConsumerState<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends ConsumerState<MonthCalendar> {
  late DateTime _month = monthOf(ref.read(todayProvider));
  DateTime? _selected;

  DateTime get _today => dateOnly(ref.read(todayProvider));

  DateTime get _currentMonth => monthOf(_today);

  bool get _canGoBack => monthsBetween(_currentMonth, _month) > -kCalendarMonthsRange;

  bool get _canGoForward => monthsBetween(_currentMonth, _month) < kCalendarMonthsRange;

  void _go(int delta) => setState(() {
    _month = addMonths(_month, delta);
    // Pilihan tanggal milik bulan sebelumnya tidak ikut terbawa.
    _selected = null;
  });

  void _goToday() => setState(() {
    _month = _currentMonth;
    _selected = _today;
  });

  void _select(DateTime day) => setState(() {
    _selected = _selected != null && dateOnly(_selected!) == day ? null : day;
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final narrow = isNarrow(context);
    final cells = monthCells(_month);
    final busy = busyDays(widget.events, _month);
    final selected = _selected;
    final listed = selected == null
        ? eventsInMonth(widget.events, _month)
        : eventsOn(widget.events, selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(narrow ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                month: _month,
                canGoBack: _canGoBack,
                canGoForward: _canGoForward,
                isCurrent: _month == _currentMonth && (_selected == null || _selected == _today),
                onBack: () => _go(-1),
                onForward: () => _go(1),
                onToday: _goToday,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final label in kWeekdayLabels)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: context.webCap.copyWith(
                            fontWeight: FontWeight.w700,
                            color: label == 'Min' ? c.sl : c.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (var row = 0; row < cells.length ~/ 7; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _DayCell(
                          day: cells[row * 7 + col],
                          today: _today,
                          selected: selected,
                          hasEvents:
                              cells[row * 7 + col] != null && busy.contains(cells[row * 7 + col]!.day),
                          compact: narrow,
                          onTap: _select,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          selected == null
              ? 'Kegiatan ${monthNameLong(_month.month)} ${_month.year}'
              : 'Kegiatan ${formatDateLong(selected)}',
          style: context.webH3,
        ),
        const SizedBox(height: 8),
        if (listed.isEmpty)
          CustomCard(
            margin: EdgeInsets.zero,
            child: Text(
              selected == null
                  ? 'Tidak ada kegiatan pada bulan ini.'
                  : 'Tidak ada kegiatan pada tanggal ini.',
              style: context.webMuted,
            ),
          )
        else
          for (final e in listed) _EventTile(event: e),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.canGoBack,
    required this.canGoForward,
    required this.isCurrent,
    required this.onBack,
    required this.onForward,
    required this.onToday,
  });

  final DateTime month;
  final bool canGoBack;
  final bool canGoForward;
  final bool isCurrent;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      spacing: 8,
      children: [
        Text('${monthNameLong(month.month)} ${month.year}', style: context.webH3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Bulan sebelumnya',
              icon: const Icon(Icons.chevron_left),
              onPressed: canGoBack ? onBack : null,
            ),
            CustomButton(
              label: 'Hari Ini',
              variant: ButtonVariant.outline,
              compact: true,
              onPressed: isCurrent ? null : onToday,
            ),
            IconButton(
              tooltip: 'Bulan berikutnya',
              icon: const Icon(Icons.chevron_right),
              onPressed: canGoForward ? onForward : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.selected,
    required this.hasEvents,
    required this.compact,
    required this.onTap,
  });

  final DateTime? day;
  final DateTime today;
  final DateTime? selected;
  final bool hasEvents;
  final bool compact;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final d = day;
    final height = compact ? 44.0 : 60.0;
    if (d == null) return SizedBox(height: height);

    final c = context.colors;
    final isSelected = selected != null && dateOnly(selected!) == d;
    final isToday = d == today;
    final foreground = isSelected ? c.su : c.ink;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${formatDateLong(d)}${hasEvents ? ', ada kegiatan' : ''}${isToday ? ', hari ini' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isSelected ? c.ink : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isToday && !isSelected ? BorderSide(color: c.ink, width: 1.5) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('day-${d.year}-${d.month}-${d.day}'),
            onTap: () => onTap(d),
            child: SizedBox(
              height: height - 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${d.day}',
                    style: context.webBody.copyWith(
                      color: foreground,
                      fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Ruang indikator selalu ada agar tinggi sel tidak berubah-ubah.
                  Container(
                    key: hasEvents ? ValueKey('dot-${d.year}-${d.month}-${d.day}') : null,
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasEvents ? (isSelected ? c.su : c.ink) : Colors.transparent,
                    ),
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

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(event.judul, style: context.webBody.copyWith(fontWeight: FontWeight.w600)),
              TagLabel(event.kategori),
            ],
          ),
          Text(calendarRange(event), style: context.webCap),
          if (event.deskripsi.isNotEmpty) Text(event.deskripsi, style: context.webMuted),
        ],
      ),
    );
  }
}
