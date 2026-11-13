import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/features/orang_tua/data/parent_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/parent_repository.dart';

/// Galat server tiruan dengan bentuk yang sama seperti hasil `ApiClient`.
ApiException apiError(
  String message, {
  ApiErrorType type = ApiErrorType.validation,
}) => ApiException(type: type, message: message);

/// Repository orang tua dalam memori: data tetap untuk tes alur dan pencatat
/// panggilan ke server (mis. notifikasi yang ditandai dibaca).
class FakeParentRepository implements ParentRepository {
  FakeParentRepository() {
    final days = <HariKehadiran>[];
    const marks = {
      9: {
        9: AttendanceStatus.terlambat,
        15: AttendanceStatus.izin,
        23: AttendanceStatus.sakit,
      },
      10: {5: AttendanceStatus.terlambat, 7: AttendanceStatus.terlambat},
    };
    for (final (month, last) in [(9, 30), (10, 8)]) {
      for (var d = 1; d <= last; d++) {
        final date = DateTime(2026, month, d);
        if (date.weekday <= DateTime.friday) {
          days.add(
            HariKehadiran(
              tanggal: date,
              status: marks[month]![d] ?? AttendanceStatus.hadir,
            ),
          );
        }
      }
    }
    attendance = days;
  }

  final List<Anak> children = [
    Anak(
      id: 1,
      nama: 'Ahmad Rizky',
      kelas: '5A',
      klasifikasi: Classification.cukup,
      literasi: 82,
      numerasi: 76,
      persenKehadiran: 96,
      jumlahTerlambat: 2,
      trenLiterasi: const [76, 78, 80, 81, 82],
      trenNumerasi: const [74, 73, 75, 76, 76],
      trenKehadiran: const [100, 95, 96, 96],
      riwayatKlasifikasi: const [
        RiwayatKlasifikasi(bulan: 'Agustus', klasifikasi: Classification.cukup),
        RiwayatKlasifikasi(bulan: 'Oktober', klasifikasi: Classification.cukup),
      ],
      nis: '12345',
      waliKelas: 'Bu Rina',
      tahunAjaran: '2026/2027',
      diperbarui: DateTime(2026, 10, 8),
      nilai: [
        NilaiUjian(
          id: 1,
          kategori: SubjectCategory.literasi,
          jenis: 'Ulangan Harian 3',
          nilai: 85,
          sebelumnya: 82,
          tanggal: DateTime(2026, 10, 6),
          catatan: 'Peningkatan yang baik.',
        ),
        NilaiUjian(
          id: 2,
          kategori: SubjectCategory.numerasi,
          jenis: 'Tugas 2',
          nilai: 76,
          sebelumnya: 75,
          tanggal: DateTime(2026, 10, 5),
          catatan: 'Stabil.',
        ),
      ],
    ),
    const Anak(
      id: 2,
      nama: 'Aisyah Rizky',
      kelas: '2A',
      klasifikasi: Classification.mahir,
      literasi: 90,
      numerasi: 88,
      persenKehadiran: 98,
      jumlahTerlambat: 0,
      trenLiterasi: [86, 87, 89, 90, 90],
      trenNumerasi: [84, 86, 87, 88, 88],
      trenKehadiran: [100, 100, 96, 98],
      riwayatKlasifikasi: [],
      nilai: [],
    ),
  ];

  late final List<HariKehadiran> attendance;
  List<ParentNotification> notifications = const [
    ParentNotification(
      id: 11,
      title: 'Nilai Literasi baru ditambahkan.',
      gradeId: 1,
    ),
    ParentNotification(
      id: 12,
      title: 'Kehadiran hari ini tercatat: Hadir.',
      tab: 2,
    ),
  ];
  final markedRead = <int>[];
  ApiException? failChildren;
  var childrenFetches = 0;

  @override
  Future<List<Anak>> fetchChildren() async {
    childrenFetches++;
    final error = failChildren;
    if (error != null) throw error;
    return children;
  }

  @override
  Future<List<HariKehadiran>> fetchAttendance(int childId) async =>
      childId == 1 ? attendance : const [];

  @override
  Future<List<HistoryItem>> fetchHistory(int childId) async => childId == 1
      ? [
          HistoryItem(
            kind: HistoryKind.nilai,
            date: DateTime(2026, 10, 6),
            title: 'Literasi 85',
            description: 'Peningkatan yang baik.',
          ),
          HistoryItem(
            kind: HistoryKind.klasifikasi,
            date: DateTime(2026, 10, 1),
            title: 'Cukup',
            description: 'Tidak berubah dari bulan lalu.',
          ),
        ]
      : const [];

  @override
  Future<List<ParentNotification>> fetchNotifications() async => notifications;

  @override
  Future<void> markNotificationRead(int id) async => markedRead.add(id);

  @override
  Future<void> markAllNotificationsRead() async =>
      markedRead.addAll(notifications.map((n) => n.id));
}
