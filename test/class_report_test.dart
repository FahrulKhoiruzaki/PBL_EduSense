import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/main.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
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
  final api = ApiClient(tokens: tokens, dio: Dio()..httpClientAdapter = adapter, baseUrl: 'http://api.test/api/v1');
  return (ApiGuruRepository(api), adapter);
}

const _period = {
  'id': 2, 'tahun_ajaran': '2026/2027', 'semester': 1, 'semester_label': 'Ganjil',
  'label': 'Semester Ganjil 2026/2027', 'tanggal_mulai': '2026-07-13',
  'tanggal_selesai': '2026-12-19', 'aktif': true,
};

ClassReport _report(AcademicPeriod period) => ClassReport(
      period: period,
      subjects: const [
        ClassReportSubject(id: 10, code: 'BIN', name: 'Bahasa Indonesia', type: SubjectType.umum,
            complete: 1, incomplete: 1, notGraded: 1, average: 86),
        ClassReportSubject(id: 11, code: 'BJAWA', name: 'Bahasa Jawa', type: SubjectType.muatanLokal,
            complete: 0, incomplete: 0, notGraded: 3, average: null),
      ],
      students: const [
        ClassReportStudent(id: 1, name: 'Ahmad Rizky', cells: [
          SubjectCell(subjectId: 10, status: GradeStatus.lengkap, filled: 2, required: 2, finalScore: 86),
          SubjectCell(subjectId: 11, status: GradeStatus.belumDinilai, filled: 0, required: 1, finalScore: null),
        ]),
        ClassReportStudent(id: 2, name: 'Siti Aulia', cells: [
          SubjectCell(subjectId: 10, status: GradeStatus.belumLengkap, filled: 1, required: 2, finalScore: null),
          SubjectCell(subjectId: 11, status: GradeStatus.belumDinilai, filled: 0, required: 1, finalScore: null),
        ]),
        ClassReportStudent(id: 3, name: 'Dimas Arya', cells: [
          SubjectCell(subjectId: 10, status: GradeStatus.belumDinilai, filled: 0, required: 2, finalScore: null),
          SubjectCell(subjectId: 11, status: GradeStatus.belumAdaKomponen, filled: 0, required: 0, finalScore: null),
        ]),
      ],
      note: null,
    );

Future<FakeGuruRepository> _boot(WidgetTester t, {required String role, required String email}) async {
  await prepareFonts();
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final guru = FakeGuruRepository();
  guru.classReport = _report(guru.periods.first);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      guruRepositoryProvider.overrideWithValue(guru),
    ],
    child: const AplikasiGuruApp(),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text(role));
  await t.pump();
  await t.enterText(find.byType(TextField).at(0), email);
  await t.enterText(find.byType(TextField).at(1), 'Guru12345');
  await t.tap(find.text('Masuk').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Kelas').last);
  await t.pumpAndSettle();
  return guru;
}

final _vertical = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

Future<void> _scroll(WidgetTester t, Finder finder, {bool up = false}) =>
    t.scrollUntilVisible(finder, up ? -300 : 300, scrollable: _vertical.first);

void main() {
  final errors = captureErrors();

  test('class report request sends periode_id and parses statuses', () async {
    final (repo, adapter) = await _repo({
      'periode': _period,
      'mapel': [
        {'id': 10, 'kode': 'BIN', 'nama': 'Bahasa Indonesia', 'jenis': 'umum', 'lengkap': 1,
         'belum_lengkap': 1, 'belum_dinilai': 1, 'rata_rata': 86.0},
      ],
      'siswa': [
        {'siswa_id': 1, 'nama': 'Ahmad', 'nilai': [
          {'mapel_id': 10, 'status': 'belum_lengkap', 'komponen_terisi': 1, 'komponen_wajib': 2,
           'nilai_akhir': null},
        ]},
      ],
      'catatan': null,
    });
    final report = await repo.fetchClassReport('5A', periodId: 2);
    expect(adapter.uris.single.path, '/api/v1/guru/classes/5A/report');
    expect(adapter.uris.single.queryParameters, {'periode_id': '2'});
    final cell = report.students.single.cells.single;
    expect((cell.status, cell.filled, cell.required, cell.finalScore), (GradeStatus.belumLengkap, 1, 2, null));
    expect(report.subjects.single.average, 86.0);
  });

  test('subject recap parses status and progress per period', () {
    final recap = SubjectRecap.fromJson({
      'periode': _period,
      'mapel': {'id': 10, 'kode': 'BIN', 'nama': 'Bahasa Indonesia'},
      'komponen': [
        {'id': 1, 'nama': 'Tugas', 'kategori': 'Literasi', 'bobot': 40, 'aktif': true},
      ],
      'metode': 'berbobot',
      'siswa': [
        {'siswa_id': 1, 'nama': 'Ahmad', 'nilai_komponen': [80.0], 'nilai_akhir': null,
         'status': 'belum_lengkap', 'komponen_terisi': 1, 'komponen_wajib': 2},
      ],
      'perkembangan': [
        {'periode': _period, 'rata_rata': null, 'jumlah_lengkap': 0, 'jumlah_siswa': 3},
      ],
    });
    final row = recap.rows.single;
    expect((row.status, row.filled, row.required, row.finalScore), (GradeStatus.belumLengkap, 1, 2, null));
    expect((recap.progress.single.average, recap.progress.single.students), (null, 3));
  });

  testWidgets('wali sees every subject per student with statuses, no input, and comparison chart',
      (t) async {
    final guru = await _boot(t, role: 'Wali Kelas', email: 'bu.rina@contoh.id');
    await t.tap(find.text('Rekap Semua Mapel'));
    await t.pumpAndSettle();

    expect(find.text('Nilai seluruh mapel per siswa'), findsNothing); // sudah di halaman rekap
    expect(find.text('BIN'), findsWidgets);
    expect(find.text('86'), findsWidgets); // nilai akhir lengkap
    expect(find.text('BL 1/2'), findsOneWidget); // belum lengkap: nilai akhir kosong
    expect(find.text('BK'), findsOneWidget);
    expect(find.text('+ Tambah Nilai'), findsNothing);
    await _scroll(t, find.text('Perbandingan rata-rata nilai antarmapel'));
    expect(find.textContaining('Belum ada nilai akhir: BJAWA'), findsOneWidget);

    // Filter periode memuat ulang rekap untuk semester yang dipilih.
    await _scroll(t, find.text('Semester Ganjil 2026/2027 (aktif)'), up: true);
    await t.tap(find.text('Semester Ganjil 2026/2027 (aktif)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Semester Genap 2025/2026').last);
    await t.pumpAndSettle();
    expect(guru.classReportPeriods.last, 1);
    expect(errors, isEmpty);
  });

  testWidgets('subject teacher recap shows weights, status and distribution', (t) async {
    await _boot(t, role: 'Guru Mapel', email: 'pak.andi@contoh.id');
    await t.tap(find.text('Nilai'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rekap per Mapel'));
    await t.pumpAndSettle();

    expect(find.text('Tugas\nbobot 40'), findsOneWidget);
    expect(find.text('Lama\nnonaktif'), findsOneWidget);
    expect(find.text('Lengkap'), findsOneWidget);
    expect(find.text('1 lengkap · 0 belum lengkap · 0 belum dinilai (1 siswa)'), findsOneWidget);
    await _scroll(t, find.text('Distribusi nilai akhir'));
    expect(find.textContaining('Hanya 1 dari 1 siswa'), findsOneWidget);
    await _scroll(t, find.textContaining('Belum ada periode dengan nilai akhir'));
    expect(errors, isEmpty);
  });
}
