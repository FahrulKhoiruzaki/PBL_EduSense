import 'package:flutter/foundation.dart';

enum WebsiteNav {
  beranda('Beranda'),
  profil('Profil Sekolah'),
  akademik('Akademik'),
  informasi('Informasi'),
  kegiatan('Kegiatan'),
  fasilitas('Fasilitas'),
  ppdb('PPDB'),
  faq('FAQ'),
  kontak('Kontak');

  const WebsiteNav(this.label);
  final String label;
}

enum ProfilSection {
  tentang('Tentang Sekolah', 'tentang'),
  sejarah('Sejarah', 'sejarah'),
  visi('Visi', 'visi'),
  misi('Misi', 'misi'),
  tujuan('Tujuan', 'tujuan'),
  identitas('Identitas Sekolah', 'identitas'),
  kepalaSekolah('Kepala Sekolah', 'kepala-sekolah'),
  guru('Guru dan Tenaga Kependidikan', 'guru');

  const ProfilSection(this.label, this.pageKey);
  final String label;
  final String pageKey;

  ProfilSection get next => values[(index + 1) % values.length];
  ProfilSection get previous => values[(index + values.length - 1) % values.length];
}

enum BeritaKategori {
  pengumuman('Pengumuman'),
  berita('Berita'),
  akademik('Akademik'),
  ppdb('PPDB'),
  kegiatan('Kegiatan');

  const BeritaKategori(this.label);
  final String label;
}

enum KegiatanKategori {
  akademik('Akademik'),
  ekstrakurikuler('Ekstrakurikuler'),
  upacara('Upacara'),
  kegiatanSiswa('Kegiatan Siswa'),
  sosial('Sosial'),
  acaraSekolah('Acara Sekolah');

  const KegiatanKategori(this.label);
  final String label;
}

enum FaqKategori {
  umum('Umum'),
  ppdb('PPDB'),
  keuangan('Keuangan'),
  akademik('Akademik'),
  kegiatan('Kegiatan');

  const FaqKategori(this.label);
  final String label;
}

enum NewsOrder {
  terbaru('Terbaru'),
  terlama('Terlama');

  const NewsOrder(this.label);
  final String label;
}

enum WhatsAppTopic {
  umum('Halo Admin, saya ingin bertanya tentang sekolah.'),
  ppdb('Halo Admin, saya ingin bertanya tentang PPDB.'),
  pengaduan('Halo Admin, saya ingin menyampaikan pengaduan. Nama: … Perihal: … Uraian: …');

  const WhatsAppTopic(this.message);
  final String message;
}

@immutable
class Berita {
  const Berita({
    required this.slug,
    required this.kategori,
    required this.tanggal,
    required this.judul,
    required this.ringkasan,
    this.isi = '',
    this.imageUrl,
  });

  final String slug;
  final BeritaKategori kategori;
  final DateTime tanggal;
  final String judul;
  final String ringkasan;
  final String isi;
  final String? imageUrl;
}

@immutable
class Kegiatan {
  const Kegiatan({
    required this.slug,
    required this.kategori,
    required this.tanggal,
    required this.judul,
    this.deskripsi = '',
    this.imageUrl,
    this.fotoUrls = const [],
  });

  final String slug;
  final KegiatanKategori kategori;
  final DateTime tanggal;
  final String judul;
  final String deskripsi;
  final String? imageUrl;
  final List<String> fotoUrls;
}

@immutable
class Faq {
  const Faq({required this.kategori, required this.pertanyaan, required this.jawaban});

  final FaqKategori kategori;
  final String pertanyaan;
  final String jawaban;
}

@immutable
class Fasilitas {
  const Fasilitas({
    required this.id,
    required this.nama,
    this.deskripsi = '',
    this.imageUrl,
  });

  final int id;
  final String nama;
  final String deskripsi;
  final String? imageUrl;
}

@immutable
class StaffMember {
  const StaffMember({required this.nama, required this.jabatan, this.fotoUrl});

  final String nama;
  final String jabatan;
  final String? fotoUrl;
}

@immutable
class SchoolInfo {
  const SchoolInfo({
    this.nama = 'SDN 02 Pakunden',
    this.kota = 'Blitar',
    this.npsn,
    this.alamat,
    this.akreditasi,
    this.telepon,
    this.email,
    this.mediaSosial,
    this.whatsapp,
    this.petaUrl,
    this.fotoUrl,
  });

  static const empty = SchoolInfo();

  final String nama;
  final String kota;
  final String? npsn;
  final String? alamat;
  final String? akreditasi;
  final String? telepon;
  final String? email;
  final String? mediaSosial;
  final String? whatsapp;
  final String? petaUrl;

  /// Foto sekolah di beranda; kosong sampai admin mengunggahnya.
  final String? fotoUrl;
}

enum ClassInfoKind {
  pembelajaran('Pembelajaran'),
  kegiatan('Kegiatan');

  const ClassInfoKind(this.label);
  final String label;

  static ClassInfoKind from(String? value) =>
      values.firstWhere((k) => k.label == value, orElse: () => ClassInfoKind.pembelajaran);
}

@immutable
class ClassLevelInfo {
  const ClassLevelInfo({
    required this.id,
    required this.tingkat,
    required this.kind,
    required this.judul,
    required this.deskripsi,
  });

  final int id;
  final int tingkat;
  final ClassInfoKind kind;
  final String judul;
  final String deskripsi;
}

@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.judul,
    required this.deskripsi,
    required this.kategori,
    required this.mulai,
    this.selesai,
  });

  final int id;
  final String judul;
  final String deskripsi;
  final String kategori;
  final DateTime mulai;
  final DateTime? selesai;
}
