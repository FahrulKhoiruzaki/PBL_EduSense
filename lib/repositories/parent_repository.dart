import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../features/orang_tua/data/parent_models.dart';
import '../models/app_models.dart';

abstract interface class ParentRepository {
  Future<List<Anak>> fetchChildren();

  Future<List<HariKehadiran>> fetchAttendance(int childId);

  Future<List<HistoryItem>> fetchHistory(int childId);

  Future<List<ParentNotification>> fetchNotifications();

  Future<void> markNotificationRead(int id);

  Future<void> markAllNotificationsRead();
}

abstract final class ParentPaths {
  static const children = '/ortu/children';
  static String attendance(int id) => '/ortu/children/$id/attendance';
  static String history(int id) => '/ortu/children/$id/history';
  static const notifications = '/ortu/notifications';
  static String notificationRead(int id) => '/ortu/notifications/$id/read';
  static const notificationsReadAll = '/ortu/notifications/read-all';
}

class ApiParentRepository implements ParentRepository {
  const ApiParentRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Anak>> fetchChildren() async {
    final rows = await _api.getList(ParentPaths.children);
    return [for (final r in rows) _child(r)];
  }

  @override
  Future<List<HariKehadiran>> fetchAttendance(int childId) async {
    final rows = await _api.getList(ParentPaths.attendance(childId));
    final days = [
      for (final r in rows)
        HariKehadiran(
          tanggal: DateTime.parse(r['tanggal'] as String),
          status: _status(r['status'] as String?),
        ),
    ]..sort((a, b) => a.tanggal.compareTo(b.tanggal));
    return days;
  }

  @override
  Future<List<HistoryItem>> fetchHistory(int childId) async {
    final rows = await _api.getList(ParentPaths.history(childId));
    return [
      for (final r in rows)
        HistoryItem(
          kind: switch (r['jenis']) {
            'kehadiran' => HistoryKind.kehadiran,
            'klasifikasi' => HistoryKind.klasifikasi,
            _ => HistoryKind.nilai,
          },
          date: DateTime.parse(r['tanggal'] as String),
          title: r['judul'] as String,
          description: r['keterangan'] as String? ?? '',
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<List<ParentNotification>> fetchNotifications() async {
    final rows = await _api.getList(ParentPaths.notifications);
    return [
      for (final r in rows)
        ParentNotification(
          id: (r['id'] as num).toInt(),
          title: r['judul'] as String,
          read: r['dibaca'] as bool? ?? false,
          tab: switch (r['target']) {
            'dashboard' => 0,
            'kehadiran' => 2,
            'riwayat' => 3,
            _ => null,
          },
          gradeId: r['target'] == 'nilai' ? (r['target_id'] as num?)?.toInt() : null,
        ),
    ];
  }

  @override
  Future<void> markNotificationRead(int id) async {
    await _api.post(ParentPaths.notificationRead(id));
  }

  @override
  Future<void> markAllNotificationsRead() async {
    await _api.post(ParentPaths.notificationsReadAll);
  }

  Anak _child(Map<String, dynamic> json) {
    final trend = (json['tren'] as Map<String, dynamic>?) ?? const {};
    List<int> series(String key) =>
        [for (final v in (trend[key] as List<dynamic>? ?? const [])) (v as num).round()];

    return Anak(
      id: (json['id'] as num).toInt(),
      nama: json['nama'] as String,
      kelas: json['kelas'] as String,
      klasifikasi: Classification.values.firstWhere(
        (c) => c.label == json['klasifikasi'],
        orElse: () => Classification.cukup,
      ),
      literasi: (json['literasi'] as num?)?.round() ?? 0,
      numerasi: (json['numerasi'] as num?)?.round() ?? 0,
      persenKehadiran: (json['persen_kehadiran'] as num?)?.round() ?? 0,
      jumlahTerlambat: (json['jumlah_terlambat'] as num?)?.toInt() ?? 0,
      trenLiterasi: series('literasi'),
      trenNumerasi: series('numerasi'),
      trenKehadiran: series('kehadiran'),
      riwayatKlasifikasi: [
        for (final r in (json['riwayat_klasifikasi'] as List<dynamic>? ?? const []))
          RiwayatKlasifikasi(
            bulan: (r as Map<String, dynamic>)['bulan'] as String,
            klasifikasi: Classification.values.firstWhere(
              (c) => c.label == r['klasifikasi'],
              orElse: () => Classification.cukup,
            ),
          ),
      ],
      nilai: [
        for (final g in (json['nilai'] as List<dynamic>? ?? const []))
          _grade(g as Map<String, dynamic>),
      ],
      nis: json['nis'] as String?,
      waliKelas: json['wali_kelas'] as String?,
      tahunAjaran: json['tahun_ajaran'] as String?,
      diperbarui: json['diperbarui'] == null ? null : DateTime.parse(json['diperbarui'] as String),
    );
  }

  NilaiUjian _grade(Map<String, dynamic> json) {
    final value = (json['nilai'] as num).round();
    return NilaiUjian(
      id: (json['id'] as num).toInt(),
      kategori:
          json['kategori'] == 'Numerasi' ? SubjectCategory.numerasi : SubjectCategory.literasi,
      jenis: json['jenis_ujian'] as String,
      nilai: value,
      sebelumnya: (json['nilai_sebelumnya'] as num?)?.round() ?? value,
      tanggal: DateTime.parse(json['tanggal'] as String),
      catatan: json['catatan_guru'] as String? ?? '',
    );
  }

  AttendanceStatus _status(String? code) => AttendanceStatus.values.firstWhere(
        (s) => s.code == code,
        orElse: () => AttendanceStatus.alpa,
      );
}

final parentRepositoryProvider = Provider<ParentRepository>(
  (ref) => ApiParentRepository(ref.watch(apiClientProvider)),
);
