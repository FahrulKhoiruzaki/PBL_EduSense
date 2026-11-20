import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/features/orang_tua/data/parent_models.dart';
import 'package:edu_sense/main.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
import 'package:edu_sense/widgets/common_widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/test_env.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;
  final uris = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    uris.add(o.uri);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiGuruRepository, _Adapter)> _repo(Object body) async {
  final adapter = _Adapter(body);
  final tokens = MemoryTokenStorage();
  await tokens.write('tok');
  return (
    ApiGuruRepository(ApiClient(tokens: tokens, dio: Dio()..httpClientAdapter = adapter, baseUrl: 'http://api.test/api/v1')),
    adapter,
  );
}

const _period = {
  'id': 2, 'tahun_ajaran': '2026/2027', 'semester': 1, 'semester_label': 'Ganjil',
  'label': 'Semester Ganjil 2026/2027', 'tanggal_mulai': '2026-07-13',
  'tanggal_selesai': '2026-12-19', 'aktif': true,
};

StudentReport _filled(AcademicPeriod period) => StudentReport(
      studentId: 1,
      name: 'Ahmad Rizky',
      nis: '001',
      className: '5A',
      period: period,
      literasi: 82.5,
      numerasi: null,
      classification: null,
      summary: const ReportSummary(
          subjects: 2, complete: 1, incomplete: 1, notGraded: 0, noComponents: 0, average: 86),
      subjects: const [
        ReportSubject(
          id: 10, code: 'BIN', name: 'Bahasa Indonesia', type: SubjectType.umum,
          status: GradeStatus.lengkap, filled: 2, required: 2, finalScore: 86, weighted: true,
          components: [
            ReportComponent(
              component: GradeComponent(id: 1, name: 'Tugas', category: SubjectCategory.literasi, weight: 40, active: true),
              value: 80, count: 2,
            ),
          ],
        ),
        ReportSubject(
          id: 11, code: 'BJAWA', name: 'Bahasa Jawa', type: SubjectType.muatanLokal,
          status: GradeStatus.belumLengkap, filled: 1, required: 2, finalScore: null, weighted: false,
          components: [],
        ),
      ],
      history: [
        ReportHistoryPeriod(period: period, classification: null, subjects: const [
          (id: 10, name: 'Bahasa Indonesia', status: GradeStatus.lengkap, finalScore: 86.0),
        ]),
      ],
      legacyGrades: 0,
      attendance: const AttendanceTally(total: 3, hadir: 1, terlambat: 1, izin: 0, sakit: 1, alpa: 0, percent: 66.7),
      trends: TrendSet(literasi: [TrendPoint(weekStart: DateTime(2026, 10, 5), value: 82.5, count: 2)]),
      note: null,
    );

Future<FakeGuruRepository> _openStudent(
  WidgetTester t, {
  required FakeGuruRepository guru,
  bool student = true,
}) async {
  await prepareFonts();
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      guruRepositoryProvider.overrideWithValue(guru),
    ],
    child: const AplikasiGuruApp(),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Wali Kelas'));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField).at(0), 'bu.rina@contoh.id');
  await t.enterText(find.byType(TextField).at(1), 'Guru12345');
  await t.tap(find.text('Masuk').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Kelas').last);
  await t.pumpAndSettle();
  if (!student) return guru;
  await t.tap(find.text('Siswa').first);
  await t.pumpAndSettle();
  await t.tap(find.text('Ahmad Rizky').first);
  await t.pumpAndSettle();
  return guru;
}

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

Future<void> _scroll(WidgetTester t, Finder f) => t.scrollUntilVisible(f, 300, scrollable: _vertical.first);

void main() {
  final errors = captureErrors();

  test('student report and history requests parse real data', () async {
    final (repo, adapter) = await _repo({
      'siswa': {'id': 1, 'nama': 'Ahmad', 'nis': null, 'kelas': '5A'},
      'periode': _period,
      'skor_literasi': 82.5, 'skor_numerasi': null, 'klasifikasi': null,
      'ringkasan': {'jumlah_mapel': 0, 'lengkap': 0, 'belum_lengkap': 0, 'belum_dinilai': 0,
                    'belum_ada_komponen': 0, 'rata_rata_nilai_akhir': null},
      'mapel': [], 'riwayat': [], 'nilai_tanpa_mapel': 2,
      'kehadiran': {'total': 3, 'hadir': 1, 'terlambat': 1, 'izin': 0, 'sakit': 1, 'alpa': 0, 'persen_hadir': 66.7},
      'tren': {'literasi': [{'tanggal': '2026-10-05', 'nilai': 82.5, 'jumlah': 2}], 'numerasi': [], 'kehadiran': []},
      'catatan': null,
    });
    final report = await repo.fetchStudentReport('5A', 1, periodId: 2);
    expect(adapter.uris.single.path, '/api/v1/guru/classes/5A/students/1/report');
    expect(adapter.uris.single.queryParameters, {'periode_id': '2'});
    expect((report.literasi, report.numerasi, report.legacyGrades), (82.5, null, 2));
    expect((report.attendance.percent, report.attendance.terlambat), (66.7, 1));
    expect(report.trends.literasi.single.value, 82.5);

    final (historyRepo, historyAdapter) = await _repo([
      {'jenis': 'kehadiran', 'tanggal': '2026-10-06', 'judul': 'Terlambat', 'keterangan': 'Tiba pukul 07:52.'},
    ]);
    final items = await historyRepo.fetchStudentHistory('5A', 1);
    expect(historyAdapter.uris.single.path, '/api/v1/guru/classes/5A/students/1/history');
    expect((items.single.kind, items.single.title), (HistoryKind.kehadiran, 'Terlambat'));
  });

  testWidgets('student detail shows backend numbers only, with subjects and history', (t) async {
    final guru = FakeGuruRepository();
    guru.studentReport = _filled(guru.periods.first);
    await _openStudent(t, guru: guru);

    expect(guru.studentReportCalls.last, ('5A', 1, null));
    expect(find.text('82.5'), findsWidgets);
    expect(find.text('66.7%'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    // Angka karangan lama tidak boleh muncul.
    expect(find.text('93%'), findsNothing);
    expect(find.text('78%'), findsNothing);
    expect(find.textContaining('Dari 3 hari tercatat'), findsOneWidget);
    await _scroll(t, find.text('Nilai seluruh mata pelajaran'));
    expect(find.text('2 mapel · 1 lengkap · 1 belum lengkap · 0 belum dinilai · 0 belum ada komponen'),
        findsOneWidget);
    expect(find.text('Bahasa Jawa (Muatan Lokal)'), findsOneWidget);
    expect(find.text('Belum lengkap 1/2'), findsOneWidget);
    await _scroll(t, find.text('Riwayat nilai akhir per periode'));
    expect(errors, isEmpty);
  });

  testWidgets('student without data shows dashes and messages, not invented numbers', (t) async {
    await _openStudent(t, guru: FakeGuruRepository());
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('Belum ada catatan absensi pada Semester Ganjil 2026/2027'), findsOneWidget);
    expect(find.text('Belum ada nilai Literasi pada periode ini.'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('history screens show real student history and class activity', (t) async {
    final guru = FakeGuruRepository()
      ..studentHistory = [
        HistoryItem(kind: HistoryKind.nilai, date: DateTime(2026, 10, 5), title: 'Bahasa Indonesia 90',
            description: 'Naik 10 poin dari nilai sebelumnya.'),
        HistoryItem(kind: HistoryKind.kehadiran, date: DateTime(2026, 10, 6), title: 'Terlambat',
            description: 'Tiba pukul 07:52.'),
      ]
      ..activities = const [
        ActivityItem(title: 'Absensi Ahmad tercatat: Sakit', when: '2 jam lalu',
            target: NavTarget(AppRoute.attendanceClass)),
      ];
    await _openStudent(t, guru: guru);
    await _scroll(t, find.text('Riwayat Perkembangan'));
    await t.tap(find.text('Riwayat Perkembangan'));
    await t.pumpAndSettle();
    expect(find.text('Nilai · Bahasa Indonesia 90'), findsOneWidget);
    expect(find.text('5 Okt 2026'), findsOneWidget);
    expect(find.text('6 Okt 2026'), findsOneWidget);
    // Tanggal statis lama tidak boleh muncul.
    expect(find.text('22 Sep 2026'), findsNothing);
    await t.tap(find.descendant(of: find.byType(FilterChips), matching: find.text('Kehadiran')));
    await t.pumpAndSettle();
    expect(find.text('Nilai · Bahasa Indonesia 90'), findsNothing);
    expect(find.text('Kehadiran · Terlambat'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('class history lists real recent activity, or a message when there is none', (t) async {
    final guru = FakeGuruRepository()
      ..activities = const [
        ActivityItem(title: 'Absensi Ahmad tercatat: Sakit', when: '2 jam lalu',
            target: NavTarget(AppRoute.attendanceClass)),
        ActivityItem(title: 'Nilai Bahasa Indonesia Siti ditambahkan', when: 'Kemarin',
            target: NavTarget(AppRoute.gradeDetail, arg: 4)),
      ];
    await _openStudent(t, guru: guru, student: false);
    await t.tap(find.text('Now Brief'));
    await t.pumpAndSettle();
    await t.tap(find.text('Perubahan terbaru'));
    await t.pumpAndSettle();
    expect(find.text('Riwayat Kelas'), findsOneWidget);
    expect(find.text('Absensi Ahmad tercatat: Sakit'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(FilterChips), matching: find.text('Nilai')));
    await t.pumpAndSettle();
    expect(find.text('Absensi Ahmad tercatat: Sakit'), findsNothing);
    expect(find.text('Nilai Bahasa Indonesia Siti ditambahkan'), findsOneWidget);
    expect(errors, isEmpty);
  });
}
