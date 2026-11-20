import 'package:flutter/foundation.dart';

const kPostCategories = ['Pengumuman', 'Berita', 'Akademik', 'PPDB', 'Kegiatan'];
const kActivityCategories = [
  'Akademik',
  'Ekstrakurikuler',
  'Upacara',
  'Kegiatan Siswa',
  'Sosial',
  'Acara Sekolah',
];
const kFaqCategories = ['Umum', 'PPDB', 'Keuangan', 'Akademik', 'Kegiatan'];

enum ContentStatus {
  draft('draft', 'Draf'),
  terbit('terbit', 'Terbit'),
  arsip('arsip', 'Arsip');

  const ContentStatus(this.code, this.label);
  final String code;
  final String label;

  static ContentStatus from(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => ContentStatus.draft);
}

@immutable
class CmsPage {
  const CmsPage({
    required this.kunci,
    required this.label,
    required this.grup,
    required this.baris,
    required this.isi,
  });

  final String kunci;
  final String label;
  final String grup;
  final int baris;
  final String isi;
}

@immutable
class CmsSchool {
  const CmsSchool({
    required this.nama,
    required this.kota,
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

  /// Hanya dibaca dari server; diganti lewat endpoint foto, bukan lewat formulir kontak.
  final String? fotoUrl;

  CmsSchool withPhoto(String? url) => CmsSchool(
    nama: nama,
    kota: kota,
    npsn: npsn,
    alamat: alamat,
    akreditasi: akreditasi,
    telepon: telepon,
    email: email,
    mediaSosial: mediaSosial,
    whatsapp: whatsapp,
    petaUrl: petaUrl,
    fotoUrl: url,
  );
}

@immutable
class CmsPostSummary {
  const CmsPostSummary({
    required this.slug,
    required this.kategori,
    required this.judul,
    required this.ringkasan,
    required this.tanggal,
    required this.status,
    this.gambarUrl,
  });

  final String slug;
  final String kategori;
  final String judul;
  final String ringkasan;
  final DateTime tanggal;
  final ContentStatus status;
  final String? gambarUrl;
}

@immutable
class CmsPost extends CmsPostSummary {
  const CmsPost({
    required super.slug,
    required super.kategori,
    required super.judul,
    required super.ringkasan,
    required super.tanggal,
    required super.status,
    super.gambarUrl,
    required this.isi,
  });

  final String isi;
}

@immutable
class CmsPostInput {
  const CmsPostInput({
    required this.judul,
    required this.kategori,
    required this.ringkasan,
    required this.isi,
    required this.status,
    this.gambarUrl,
    this.tanggal,
  });

  final String judul;
  final String kategori;
  final String ringkasan;
  final String isi;
  final ContentStatus status;
  final String? gambarUrl;
  final DateTime? tanggal;
}

@immutable
class CmsActivity {
  const CmsActivity({
    required this.slug,
    required this.kategori,
    required this.judul,
    required this.deskripsi,
    required this.tanggal,
    required this.status,
    required this.fotoUrls,
  });

  final String slug;
  final String kategori;
  final String judul;
  final String deskripsi;
  final DateTime tanggal;
  final ContentStatus status;
  final List<String> fotoUrls;
}

@immutable
class CmsActivityInput {
  const CmsActivityInput({
    required this.judul,
    required this.kategori,
    required this.deskripsi,
    required this.status,
    required this.fotoUrls,
    this.tanggal,
  });

  final String judul;
  final String kategori;
  final String deskripsi;
  final ContentStatus status;
  final List<String> fotoUrls;
  final DateTime? tanggal;
}

@immutable
class CmsFacility {
  const CmsFacility({
    required this.id,
    required this.nama,
    required this.deskripsi,
    required this.urutan,
    required this.tampil,
    this.gambarUrl,
  });

  final int id;
  final String nama;
  final String deskripsi;
  final int urutan;
  final bool tampil;
  final String? gambarUrl;
}

@immutable
class CmsFacilityInput {
  const CmsFacilityInput({
    required this.nama,
    required this.deskripsi,
    required this.tampil,
    this.gambarUrl,
    this.urutan,
  });

  final String nama;
  final String deskripsi;
  final bool tampil;
  final String? gambarUrl;
  final int? urutan;
}

@immutable
class CmsFaq {
  const CmsFaq({
    required this.id,
    required this.kategori,
    required this.pertanyaan,
    required this.jawaban,
    required this.urutan,
    required this.tampil,
  });

  final int id;
  final String kategori;
  final String pertanyaan;
  final String jawaban;
  final int urutan;
  final bool tampil;
}

@immutable
class CmsFaqInput {
  const CmsFaqInput({
    required this.kategori,
    required this.pertanyaan,
    required this.jawaban,
    required this.tampil,
    this.urutan,
  });

  final String kategori;
  final String pertanyaan;
  final String jawaban;
  final bool tampil;
  final int? urutan;
}

@immutable
class PickedImage {
  const PickedImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
