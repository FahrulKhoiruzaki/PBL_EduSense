import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/features/admin/screens/admin_main_layout.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/academic_admin_repository.dart';
import 'package:edu_sense/repositories/admin_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/test_env.dart';

typedef _Env = ({FakeAdminRepository admin, FakeAcademicAdminRepository academic});

Future<_Env> _boot(WidgetTester t, {FakeAcademicAdminRepository? academic}) async {
  await prepareFonts();
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final admin = FakeAdminRepository();
  final repo = academic ?? FakeAcademicAdminRepository();
  await t.pumpWidget(ProviderScope(
    overrides: [
      adminRepositoryProvider.overrideWithValue(admin),
      academicAdminRepositoryProvider.overrideWithValue(repo),
    ],
    child: harnessApp(const AdminMainLayout()),
  ));
  await t.pumpAndSettle();
  return (admin: admin, academic: repo);
}

Future<void> _openMenu(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(AdminSidebar), matching: find.text(label)));
  await t.pumpAndSettle();
}

Future<void> _drainToast(WidgetTester t) => t.pump(const Duration(seconds: 3));

Finder _field(String label) => find.ancestor(
      of: find.descendant(of: find.byType(Dialog), matching: find.text(label)),
      matching: find.byType(Column),
    ).first;

Future<void> _enter(WidgetTester t, String label, String text) async {
  await t.enterText(find.descendant(of: _field(label), matching: find.byType(TextField)), text);
}

Future<void> _pickChoice(WidgetTester t, String current, String option) async {
  await t.tap(find.text(current).last);
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

Future<void> _pickDate(WidgetTester t, int index, int day) async {
  await t.tap(find.text('Pilih tanggal').at(index));
  await t.pumpAndSettle();
  await t.tap(find.text('$day').last);
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
}

class _Recorder implements HttpClientAdapter {
  _Recorder(this.response);

  final Object? response;
  final requests = <(RequestOptions, String)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requests.add((options, utf8.decode(bytes)));
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _Recorder)> _client(Object? response) async {
  final rec = _Recorder(response);
  final tokens = MemoryTokenStorage();
  await tokens.write('tok');
  return (
    ApiClient(tokens: tokens, dio: Dio()..httpClientAdapter = rec, baseUrl: 'http://api.test/api/v1'),
    rec,
  );
}

void main() {
  final errors = captureErrors();

  group('repository contract', () {
    test('period, rule and component bodies match the API', () async {
      final (api, rec) = await _client({'id': 1});
      final repo = ApiAcademicAdminRepository(api);

      await repo.createPeriod(PeriodInput(
        academicYear: '2026/2027',
        semester: 2,
        start: DateTime(2027, 1, 4),
        end: DateTime(2027, 6, 19),
      ));
      await repo.saveRule(
        3,
        const ClassificationRule(method: ClassificationMethod.lowest, mahirMin: 80, cukupMin: 62.5),
      );
      await repo.createComponent(const ComponentInput(
        periodId: 3,
        subjectId: 9,
        name: 'Praktik',
        category: null,
        weight: null,
      ));

      final bodies = [for (final r in rec.requests) jsonDecode(r.$2) as Map<String, dynamic>];
      expect(rec.requests[0].$1.uri.path, '/api/v1/admin/academic/periods');
      expect(bodies[0], {
        'tahun_ajaran': '2026/2027',
        'semester': 2,
        'tanggal_mulai': '2027-01-04',
        'tanggal_selesai': '2027-06-19',
      });
      expect(rec.requests[1].$1.method, 'PUT');
      expect(rec.requests[1].$1.uri.path, '/api/v1/admin/academic/periods/3/rule');
      expect(bodies[1], {'metode': 'terendah', 'batas_mahir': 80.0, 'batas_cukup': 62.5});
      expect(bodies[2]['kategori'], isNull);
      expect(bodies[2]['bobot'], isNull);
      expect(bodies[2]['mapel_id'], 9);
    });

    test('a period without a rule returns null', () async {
      final (api, _) = await _client(null);
      expect(await ApiAcademicAdminRepository(api).fetchRule(1), isNull);
    });

    test('classification query sends periode_id and kelas only when set', () async {
      final (api, rec) = await _client({
        'periode': null,
        'aturan': null,
        'ringkasan': {'total_siswa': 0, 'terklasifikasi': 0, 'belum_lengkap': 0, 'tanpa_nilai': 0, 'kategori': []},
        'per_kelas': [],
        'perbandingan': null,
        'catatan': 'Periode akademik aktif belum ditetapkan admin.',
      });
      final repo = ApiAcademicAdminRepository(api);
      await repo.fetchClassification();
      await repo.fetchClassification(periodId: 2, classCode: '5A');
      expect(rec.requests[0].$1.uri.queryParameters, isEmpty);
      expect(rec.requests[1].$1.uri.queryParameters, {'periode_id': '2', 'kelas': '5A'});
    });

    test('mapel assignment sends mapel_id; removal targets one subject', () async {
      final (api, rec) = await _client(null);
      final repo = ApiAdminRepository(api);
      await repo.addMapel('5A', '7', subjectId: 3);
      await repo.removeMapel('5A', '7', subjectId: 3);
      expect(jsonDecode(rec.requests[0].$2), {'guru_id': '7', 'mapel_id': 3});
      expect(rec.requests[1].$1.uri.path, '/api/v1/admin/classes/5A/mapel/7');
      expect(rec.requests[1].$1.uri.queryParameters, {'mapel_id': '3'});
    });
  });

  testWidgets('periods: list, add with validation, activate', (t) async {
    final env = await _boot(t);
    await _openMenu(t, 'Periode Akademik');
    expect(find.text('Semester Ganjil 2026/2027'), findsOneWidget);
    expect(find.text('Aktif'), findsOneWidget);
    expect(find.text('0 nilai · 2 komponen'), findsOneWidget);

    await t.tap(find.text('+ Tambah Periode'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tambah').last);
    await t.pump();
    expect(find.text('Kolom ini wajib diisi.'), findsNWidgets(3));

    await _enter(t, 'Tahun ajaran', '2026/2027');
    await _pickChoice(t, 'Ganjil (1)', 'Genap (2)');
    await _pickDate(t, 0, 20);
    await _pickDate(t, 0, 10);
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    expect(find.text('Tanggal selesai harus setelah tanggal mulai.'), findsOneWidget);
    expect(env.academic.createdPeriods, isEmpty);

    // Perbaiki tanggal selesai; server menolak (mis. tumpang tindih) dan pesannya muncul di kolom.
    await t.tap(find.byIcon(Icons.calendar_today).at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('28').last);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    env.academic.nextError = const ApiException(
      type: ApiErrorType.conflict,
      message: 'Rentang tanggal bertumpang tindih.',
      fieldErrors: {'tanggal_mulai': 'Rentang tanggal bertumpang tindih dengan Semester Ganjil.'},
    );
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    expect(find.text('Rentang tanggal bertumpang tindih dengan Semester Ganjil.'), findsOneWidget);
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    final created = env.academic.createdPeriods.single;
    expect((created.academicYear, created.semester, created.end.day - created.start.day),
        ('2026/2027', 2, 8));
    await _drainToast(t);
    expect(find.text('Semester Genap 2026/2027'), findsOneWidget);

    await t.tap(find.text('Aktifkan').last);
    await t.pumpAndSettle();
    expect(find.text('Jadikan Semester Genap 2025/2026 periode aktif?'), findsOneWidget);
    await t.tap(find.text('Aktifkan').last);
    await t.pumpAndSettle();
    expect(env.academic.activated, [1]);
    await _drainToast(t);
    expect(errors, isEmpty);
  });

  testWidgets('classification rule: validated locally, then saved', (t) async {
    final env = await _boot(t);
    await _openMenu(t, 'Periode Akademik');
    await t.tap(find.text('Aturan').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Belum ada ambang resmi'), findsOneWidget);

    await _enter(t, 'Batas Mahir (skor ≥)', '70');
    await _enter(t, 'Batas Cukup (skor ≥)', '75');
    await t.tap(find.text('Simpan Aturan'));
    await t.pumpAndSettle();
    expect(find.text('Batas Cukup harus lebih rendah dari batas Mahir.'), findsOneWidget);
    expect(env.academic.savedRules, isEmpty);

    await _enter(t, 'Batas Cukup (skor ≥)', '55,5');
    await _pickChoice(
      t,
      ClassificationMethod.average.label,
      ClassificationMethod.lowest.label,
    );
    await t.tap(find.text('Simpan Aturan'));
    await t.pumpAndSettle();
    final (periodId, rule) = env.academic.savedRules.single;
    expect((periodId, rule.method, rule.mahirMin, rule.cukupMin),
        (2, ClassificationMethod.lowest, 70.0, 55.5));
    await _drainToast(t);
    expect(errors, isEmpty);
  });

  testWidgets('subjects: filter muatan lokal, add a local subject with levels', (t) async {
    final env = await _boot(t);
    await _openMenu(t, 'Mata Pelajaran');
    expect(find.text('Bahasa Inggris'), findsOneWidget);

    await t.tap(find.text('Muatan Lokal').first);
    await t.pumpAndSettle();
    expect(find.text('Bahasa Jawa'), findsOneWidget);
    expect(find.text('Bahasa Indonesia'), findsNothing);

    await t.tap(find.text('+ Tambah Mapel'));
    await t.pumpAndSettle();
    await _enter(t, 'Kode', 'bsun');
    await _enter(t, 'Nama mata pelajaran', 'Bahasa Sunda');
    await _pickChoice(t, 'Umum', 'Muatan Lokal');
    await t.tap(find.text('Kelas 1'));
    await t.tap(find.text('Kelas 2'));
    await t.pump();
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();

    final input = env.academic.createdSubjects.single;
    expect((input.code, input.name, input.type), ('BSUN', 'Bahasa Sunda', SubjectType.muatanLokal));
    expect(input.levels, [3, 4, 5, 6]);
    // Mapel yang sudah dipakai tidak bisa dihapus (tidak ada tombol Hapus untuknya).
    await t.tap(find.text('Semua').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Nonaktifkan').first);
    await t.pumpAndSettle();
    expect(env.academic.subjectToggles, [(10, false)]);
    await _drainToast(t);
    expect(errors, isEmpty);
  });

  testWidgets('components: weight summary, add component, server field error', (t) async {
    final env = await _boot(t);
    await _openMenu(t, 'Komponen Penilaian');
    expect(find.text('Semester Ganjil 2026/2027 (aktif)'), findsOneWidget);
    expect(find.text('Total bobot komponen aktif: 70 (maksimal 100).'), findsOneWidget);

    await t.tap(find.text('+ Tambah Komponen'));
    await t.pumpAndSettle();
    await _enter(t, 'Nama komponen', 'Asesmen Sumatif');
    await _pickChoice(t, 'Tidak (komponen biasa)', 'Ya, sebagai Literasi');
    await _enter(t, 'Bobot (opsional)', '40');
    env.academic.nextError = const ApiException(
      type: ApiErrorType.validation,
      message: 'Periksa kembali.',
      fieldErrors: {'bobot': 'Total bobot komponen aktif mapel ini akan menjadi 110; maksimal 100.'},
    );
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    expect(find.textContaining('akan menjadi 110'), findsOneWidget);

    await _enter(t, 'Bobot (opsional)', '30');
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    final input = env.academic.createdComponents.single;
    expect((input.periodId, input.subjectId, input.category, input.weight),
        (2, 10, SubjectCategory.literasi, 30.0));
    await _drainToast(t);

    // Periode lain belum punya komponen.
    await _pickChoice(t, 'Semester Ganjil 2026/2027 (aktif)', 'Semester Genap 2025/2026');
    expect(find.text('Belum ada komponen penilaian untuk Semester Genap 2025/2026.'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('classification: counts, percentages and per-class comparison', (t) async {
    Distribution dist(List<int> n, {String? kelas}) {
      final classified = n.reduce((a, b) => a + b);
      return Distribution(
        total: classified,
        classified: classified,
        incomplete: 0,
        withoutGrades: 0,
        className: kelas,
        categories: [
          for (var i = 0; i < 3; i++)
            CategoryCount(
              classification: Classification.values[i],
              count: n[i],
              percent: n[i] / classified * 100,
            ),
        ],
      );
    }

    final academic = FakeAcademicAdminRepository();
    final period = academic.periods.first;
    academic.summary = ClassificationSummary(
      period: period,
      rule: const ClassificationRule(method: ClassificationMethod.average, mahirMin: 80, cukupMin: 65),
      overall: dist([3, 4, 1]),
      perClass: [dist([1, 2, 1], kelas: '5A'), dist([2, 2, 0], kelas: '5B')],
      comparison: null,
      note: null,
    );
    await _boot(t, academic: academic);
    await _openMenu(t, 'Klasifikasi Siswa');

    expect(find.text('Seluruh sekolah · Semester Ganjil 2026/2027'), findsOneWidget);
    expect(find.text('3 siswa · 37.5%'), findsOneWidget);
    expect(find.text('4 siswa · 50%'), findsOneWidget);
    expect(find.text('Perbandingan antarkelas'), findsOneWidget);
    expect(find.text('Kelas 5A'), findsOneWidget);
    expect(find.text('M 2 (50%) · C 2 (50%) · P 0 (0%)'), findsOneWidget);
    expect(academic.classificationQueries.last, (2, null));

    await _pickChoice(t, 'Semua kelas', 'Kelas 5B');
    expect(academic.classificationQueries.last, (2, '5B'));
    expect(errors, isEmpty);
  });

  testWidgets('class structure: assign a guru to a subject valid for the class level', (t) async {
    final env = await _boot(t);
    await _openMenu(t, 'Struktur Kelas');
    await t.tap(find.text('Kelas 5A'));
    await t.pumpAndSettle();
    expect(find.text('Mapel belum ditetapkan · belum dapat memasukkan nilai'), findsOneWidget);

    await t.tap(find.text('+ Tambah').last);
    await t.pumpAndSettle();
    await _pickChoice(t, 'Pilih guru…', 'Pak Andi');
    await t.tap(find.text('Pilih mata pelajaran…'));
    await t.pumpAndSettle();
    // Mapel nonaktif tidak ditawarkan; IPAS (kelas 3-6) berlaku untuk kelas 5.
    expect(find.text('Bahasa Inggris'), findsNothing);
    await t.tap(find.text('Bahasa Jawa (Muatan Lokal)').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Tambah').last);
    await t.pumpAndSettle();
    expect(env.admin.addedMapel, [('5A', 'g2', 12)]);
    await _drainToast(t);
    expect(errors, isEmpty);
  });
}
