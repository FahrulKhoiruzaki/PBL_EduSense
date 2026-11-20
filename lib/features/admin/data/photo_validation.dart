import 'dart:typed_data';

/// Batas yang sama dengan server (`MAX_MEDIA_BYTES`, bawaan 5 MB). Server tetap memeriksa ulang;
/// pemeriksaan di sini hanya agar pengguna tahu lebih cepat sebelum mengunggah.
const kMaxPhotoBytes = 5 * 1024 * 1024;

const kPhotoFormatsLabel = 'JPEG, PNG, atau WebP';

/// Jenis gambar dari isi berkas (bukan dari nama), sama seperti di server. Null bila bukan gambar.
String? detectPhotoFormat(Uint8List bytes) {
  bool starts(List<int> sig) =>
      bytes.length >= sig.length && [for (var i = 0; i < sig.length; i++) bytes[i] == sig[i]].every((b) => b);

  if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'png';
  if (bytes.length >= 12 &&
      starts(const [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

/// Pesan galat untuk pengguna, atau null bila berkas boleh diunggah.
String? validatePhoto(Uint8List bytes) {
  if (bytes.isEmpty) return 'Berkas kosong. Pilih foto lain.';
  if (bytes.length > kMaxPhotoBytes) {
    return 'Ukuran foto terlalu besar. Maksimal ${kMaxPhotoBytes ~/ (1024 * 1024)} MB.';
  }
  if (detectPhotoFormat(bytes) == null) {
    return 'Berkas harus berupa gambar $kPhotoFormatsLabel yang valid.';
  }
  return null;
}
