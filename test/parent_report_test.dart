import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/features/orang_tua/providers/parent_providers.dart';
import 'package:edu_sense/features/orang_tua/screens/parent_main_layout.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/parent_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/test_env.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final Object body;
  final uris = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    uris.add(o.uri);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiParentRepository, _Adapter)> _repo(Object body, {int status = 200}) async {
  final adapter = _Adapter(status, body);
  final tokens = MemoryTokenStorage();
  await tokens.write('tok');
  return (
    ApiParentRepository(
        ApiClient(tokens: tokens, dio: Dio()..httpClientAdapter = adapter, baseUrl: 'http://api.test/api/v1')),
    adapter,
  );
}

StudentReport _report(String name, AcademicPeriod period, {required double finalBin, int alpa = 0}) =>
    StudentReport(
      studentId: 1,
      name: name,
      nis: null,
      className: '5A',
      period: period,
      literasi: 81.5,
      numerasi: 76,
      classification: Classification.cukup,
      summary: const ReportSummary(
          subjects: 2, complete: 1, incomplete: 0, notGraded: 1, noComponents: 0, average: 86),
      subjects: [
        ReportSubject(
          id: 10, code: 'BIN', name: 'Bahasa Indonesia', type: SubjectType.umum,
          status: GradeStatus.lengkap, filled: 2, required: 2, finalScore: finalBin, weighted: true,
          components: const [
            ReportComponent(
              component: GradeComponent(id: 1, name: 'Tugas', category: SubjectCategory.literasi, weight: 40, active: true),
              value: 80, count: 2,
            ),
            ReportComponent(
              component: GradeComponent(id: 2, name: 'UAS', category: SubjectCategory.literasi, weight: 60, active: true),
              value: 90, count: 1,
            ),
          ],
        ),
        const ReportSubject(
          id: 12, code: 'BJAWA', name: 'Bahasa Jawa', type: SubjectType.muatanLokal,
          status: GradeStatus.belumDinilai, filled: 0, required: 1, finalScore: null, weighted: false,
          components: [],
        ),
      ],
      history: const [],
      legacyGrades: 0,
      attendance: AttendanceTally(total: 10, hadir: 7, terlambat: 1, izin: 1, sakit: 0, alpa: alpa, percent: 80),
      trends: TrendSet(literasi: [TrendPoint(weekStart: DateTime(2026, 10, 5), value: 81.5, count: 3)]),
      note: null,
    );

Future<(ProviderContainer, FakeParentRepository)> _openReport(WidgetTester t, FakeParentRepository repo) async {
  await prepareFonts();
  t.view.physicalSize = const Size(1280, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [parentRepositoryProvider.overrideWithValue(repo)],
    child: harnessApp(const ParentMainLayout()),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Rapor Akademik').first);
  await t.pumpAndSettle();
  return (ProviderScope.containerOf(t.element(find.byType(ParentMainLayout))), repo);
}

final _vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

Future<void> _scroll(WidgetTester t, Finder f) => t.scrollUntilVisible(f, 300, scrollable: _vertical.first);

void main() {
  final errors = captureErrors();

  test('report and periods requests hit the parent endpoints', () async {
    final (repo, adapter) = await _repo([
      {'id': 1, 'tahun_ajaran': '2025/2026', 'semester': 2, 'semester_label': 'Genap',
       'label': 'Semester Genap 2025/2026', 'tanggal_mulai': '2026-01-05', 'tanggal_selesai': '2026-06-20',
       'aktif': false},
    ]);
    final periods = await repo.fetchPeriods();
    expect((adapter.uris.single.path, periods.single.label), ('/api/v1/ortu/periods', 'Semester Genap 2025/2026'));

    final (reportRepo, reportAdapter) = await _repo({'message': 'Data anak tidak ditemukan.'}, status: 404);
    // Anak milik akun lain: backend menjawab 404, aplikasi tidak menampilkan data apa pun.
    await expectLater(
      reportRepo.fetchReport(99, periodId: 1),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Data anak tidak ditemukan.')),
    );
    expect(reportAdapter.uris.single.path, '/api/v1/ortu/children/99/report');
    expect(reportAdapter.uris.single.queryParameters, {'periode_id': '1'});
  });

  testWidgets('report shows all subjects, components, scores, classification and attendance', (t) async {
    final repo = FakeParentRepository();
    repo.reports[(1, null)] = _report('Ahmad Rizky', repo.periods.first, finalBin: 86);
    await _openReport(t, repo);

    expect(find.text('Ahmad Rizky · Kelas 5A'), findsWidgets); // pemilih anak
    expect(find.text('81.5'), findsWidgets);
    expect(find.text('80%'), findsOneWidget);
    expect(find.textContaining('Dari 10 hari tercatat'), findsOneWidget);
    expect(find.textContaining('Hadir 7, Terlambat 1, Izin 1, Sakit 0, Alpa 0'), findsOneWidget);
    expect(find.text('Cukup'), findsWidgets);
    expect(find.textContaining('Dihitung dari skor Literasi dan Numerasi'), findsOneWidget);
    await _scroll(t, find.text('Bahasa Jawa (Muatan Lokal)'));
    expect(find.text('Nilai akhir: 86'), findsOneWidget);
    expect(find.text('Belum dinilai'), findsWidgets);
    await t.tap(find.text('Bahasa Indonesia'));
    await t.pumpAndSettle();
    expect(find.text('Tugas · bobot 40 · Literasi'), findsOneWidget);
    expect(find.text('90 (1 nilai)'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('period filter reloads the report for the chosen semester', (t) async {
    final repo = FakeParentRepository();
    repo.reports[(1, null)] = _report('Ahmad Rizky', repo.periods.first, finalBin: 86);
    repo.reports[(1, 1)] = _report('Ahmad Rizky', repo.periods.last, finalBin: 70);
    await _openReport(t, repo);
    expect(find.text('Nilai akhir: 86', skipOffstage: false), findsOneWidget);

    await t.tap(find.text('Semester Ganjil 2026/2027 (aktif)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Semester Genap 2025/2026').last);
    await t.pumpAndSettle();
    expect(repo.reportCalls.last, (1, 1));
    expect(find.text('Nilai akhir: 70', skipOffstage: false), findsOneWidget);
    expect(find.text('Nilai akhir: 86', skipOffstage: false), findsNothing);
    expect(errors, isEmpty);
  });

  testWidgets('switching child replaces every figure with the other child report', (t) async {
    final repo = FakeParentRepository();
    repo.reports[(1, null)] = _report('Ahmad Rizky', repo.periods.first, finalBin: 86);
    final (container, _) = await _openReport(t, repo);
    expect(find.text('Nilai akhir: 86', skipOffstage: false), findsOneWidget);

    container.read(selectedKidIndexProvider.notifier).select(1);
    await t.pumpAndSettle();
    expect(repo.reportCalls.last, (2, null));
    expect(find.text('Aisyah Rizky · Kelas 2A'), findsWidgets);
    // Anak kedua belum punya rapor: tidak ada sisa angka anak pertama.
    expect(find.text('Nilai akhir: 86', skipOffstage: false), findsNothing);
    expect(find.text('81.5', skipOffstage: false), findsNothing);
    expect(find.text('Belum ada mata pelajaran yang tercatat untuk periode ini.', skipOffstage: false),
        findsOneWidget);
    expect(find.textContaining('Belum ada catatan absensi', skipOffstage: false), findsWidgets);
    expect(errors, isEmpty);
  });

  testWidgets('a failed report request shows a retry, not stale data', (t) async {
    final repo = FakeParentRepository()
      ..reportError = const ApiException(type: ApiErrorType.notFound, message: 'Data anak tidak ditemukan.');
    await _openReport(t, repo);
    expect(find.text('Data anak tidak ditemukan.'), findsOneWidget);
    expect(find.textContaining('Nilai akhir'), findsNothing);
    expect(errors, isEmpty);
  });
}
