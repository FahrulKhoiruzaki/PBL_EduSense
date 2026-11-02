import 'website_models.dart';

/// Hitungan kalender bulanan (murni, tanpa Flutter). Minggu dimulai hari Senin.
const kWeekdayLabels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Jarak navigasi dari bulan berjalan, ke belakang dan ke depan.
const kCalendarMonthsRange = 12;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime monthOf(DateTime d) => DateTime(d.year, d.month);

/// Menggeser bulan; kelebihan/kekurangan bulan otomatis memindahkan tahun (Des + 1 = Jan tahun depan).
DateTime addMonths(DateTime month, int delta) => DateTime(month.year, month.month + delta);

/// Selisih bulan `b - a` (mis. Jan 2027 - Des 2026 = 1).
int monthsBetween(DateTime a, DateTime b) => (b.year - a.year) * 12 + (b.month - a.month);

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Sel grid satu bulan: kolom pertama Senin. Sel kosong (null) di awal dan akhir melengkapi minggu,
/// sehingga panjangnya selalu kelipatan 7 dan tanggal 1 jatuh di kolom hari yang benar.
List<DateTime?> monthCells(DateTime month) {
  final first = DateTime(month.year, month.month);
  final leading = first.weekday - DateTime.monday;
  final days = daysInMonth(first);
  final cells = <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= days; d++) DateTime(first.year, first.month, d),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// Apakah kegiatan berlangsung pada [day] (tanggal mulai sampai selesai, keduanya termasuk).
bool eventCoversDay(CalendarEvent e, DateTime day) {
  final d = dateOnly(day);
  final start = dateOnly(e.mulai);
  final end = e.selesai == null ? start : dateOnly(e.selesai!);
  return !d.isBefore(start) && !d.isAfter(end);
}

List<CalendarEvent> eventsOn(Iterable<CalendarEvent> events, DateTime day) => [
  for (final e in events)
    if (eventCoversDay(e, day)) e,
];

/// Kegiatan yang beririsan dengan bulan [month], urut dari tanggal mulai.
List<CalendarEvent> eventsInMonth(Iterable<CalendarEvent> events, DateTime month) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month, daysInMonth(first));
  final result = [
    for (final e in events)
      if (!dateOnly(e.mulai).isAfter(last) &&
          !dateOnly(e.selesai ?? e.mulai).isBefore(first))
        e,
  ]..sort((a, b) {
      final byStart = a.mulai.compareTo(b.mulai);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
  return result;
}

/// Tanggal-tanggal pada [month] yang punya kegiatan (untuk indikator).
Set<int> busyDays(Iterable<CalendarEvent> events, DateTime month) {
  final first = DateTime(month.year, month.month);
  final days = daysInMonth(first);
  return {
    for (var d = 1; d <= days; d++)
      if (events.any((e) => eventCoversDay(e, DateTime(first.year, first.month, d)))) d,
  };
}
