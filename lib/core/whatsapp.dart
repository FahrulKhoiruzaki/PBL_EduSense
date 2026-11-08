/// Membuat tautan wa.me. Nomor dinormalisasi ke format internasional tanpa tanda baca;
/// awalan 0 dianggap nomor Indonesia (0812… → 62812…). Tanpa nomor, WhatsApp
/// menampilkan pemilih kontak.
Uri whatsAppUri({String? number, required String message}) {
  var digits = (number ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '62${digits.substring(1)}';

  return Uri(
    scheme: 'https',
    host: 'wa.me',
    path: digits.isEmpty ? '/' : '/$digits',
    queryParameters: {'text': message},
  );
}
