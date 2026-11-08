const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const _longMonths = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String monthNameShort(int month) => _shortMonths[month - 1];

String monthNameLong(int month) => _longMonths[month - 1];

String formatDate(DateTime d) => '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';

String formatDateLong(DateTime d) => '${d.day} ${_longMonths[d.month - 1]} ${d.year}';

const _weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

String formatFullDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${formatDateLong(d)}';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String relativeTime(DateTime now, DateTime then) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  return formatDate(then);
}

String initials(String name) => name
    .split(' ')
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0])
    .join();

String nameFromEmail(String email) => email
    .split('@')
    .first
    .split('.')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
