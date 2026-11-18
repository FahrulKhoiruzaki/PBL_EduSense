import 'package:flutter/foundation.dart';

import '../../../models/academic_models.dart';
import '../../../models/app_models.dart';

enum HistoryKind {
  nilai('Nilai'),
  kehadiran('Kehadiran'),
  klasifikasi('Klasifikasi');

  const HistoryKind(this.label);
  final String label;
}

@immutable
class NilaiUjian {
  const NilaiUjian({
    required this.id,
    required this.kategori,
    required this.jenis,
    required this.nilai,
    required this.sebelumnya,
    required this.tanggal,
    required this.catatan,
    this.mapel,
  });

  final int id;

  /// Null untuk penilaian di luar Literasi/Numerasi (mis. PJOK, muatan lokal).
  final SubjectCategory? kategori;
  final String jenis;

  /// Nama mata pelajaran; null untuk nilai lama sebelum ada data mapel.
  final String? mapel;

  String get mapelLabel => mapel ?? kategori?.label ?? 'Tanpa mapel';
  final int nilai;
  final int sebelumnya;
  final DateTime tanggal;
  final String catatan;

  int get selisih => nilai - sebelumnya;
}

@immutable
class RiwayatKlasifikasi {
  const RiwayatKlasifikasi({required this.bulan, required this.klasifikasi});

  final String bulan;
  final Classification klasifikasi;
}

@immutable
class HariKehadiran {
  const HariKehadiran({required this.tanggal, required this.status});

  final DateTime tanggal;
  final AttendanceStatus status;

  int get hari => tanggal.day;

  DateTime get bulan => DateTime(tanggal.year, tanggal.month);
}

@immutable
class HistoryItem {
  const HistoryItem({
    required this.kind,
    required this.date,
    required this.title,
    required this.description,
  });

  final HistoryKind kind;
  final DateTime date;
  final String title;
  final String description;
}

@immutable
class ParentNotification {
  const ParentNotification({
    required this.id,
    required this.title,
    this.read = false,
    this.tab,
    this.gradeId,
  });

  final int id;
  final String title;
  final bool read;
  final int? tab;
  final int? gradeId;

  ParentNotification copyWith({bool? read}) => ParentNotification(
        id: id,
        title: title,
        read: read ?? this.read,
        tab: tab,
        gradeId: gradeId,
      );
}

@immutable
class Anak {
  const Anak({
    required this.id,
    required this.nama,
    required this.kelas,
    required this.klasifikasi,
    required this.literasi,
    required this.numerasi,
    required this.persenKehadiran,
    required this.jumlahTerlambat,
    required this.trenLiterasi,
    required this.trenNumerasi,
    required this.trenKehadiran,
    required this.riwayatKlasifikasi,
    required this.nilai,
    this.nis,
    this.waliKelas,
    this.tahunAjaran,
    this.periode,
    this.trenTitik = TrendSet.empty,
    this.diperbarui,
  });

  final int id;
  final String nama;
  final String kelas;
  /// Null = belum diklasifikasi pada periode aktif (bukan "Cukup").
  final Classification? klasifikasi;
  final int literasi;
  final int numerasi;
  final int persenKehadiran;
  final int jumlahTerlambat;
  final List<int> trenLiterasi;
  final List<int> trenNumerasi;
  final List<int> trenKehadiran;
  final List<RiwayatKlasifikasi> riwayatKlasifikasi;
  final List<NilaiUjian> nilai;
  final String? nis;
  final String? waliKelas;
  final String? tahunAjaran;

  /// Periode akademik yang dipakai untuk klasifikasi, rata-rata, dan kehadiran.
  final String? periode;

  /// Tren dengan tanggal awal minggu (untuk grafik bersumbu).
  final TrendSet trenTitik;
  final DateTime? diperbarui;

  String get namaDepan => nama.split(' ').first;

  NilaiUjian? nilaiById(int id) {
    for (final n in nilai) {
      if (n.id == id) return n;
    }
    return null;
  }
}
