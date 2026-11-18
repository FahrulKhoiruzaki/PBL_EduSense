import 'package:edu_sense/main.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/test_env.dart';

Future<FakeGuruRepository> _boot(WidgetTester t, {FakeGuruRepository? guru}) async {
  await prepareFonts();
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);

  final repo = guru ?? FakeGuruRepository();
  await t.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      guruRepositoryProvider.overrideWithValue(repo),
    ],
    child: const AplikasiGuruApp(),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Guru Mapel'));
  await t.pump();
  await t.enterText(find.byType(TextField).at(0), 'pak.andi@contoh.id');
  await t.enterText(find.byType(TextField).at(1), 'Guru12345');
  await t.tap(find.text('Masuk').last);
  await t.pumpAndSettle();
  return repo;
}

Future<void> _openGrades(WidgetTester t) async {
  await t.tap(find.text('Kelas').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Nilai'));
  await t.pumpAndSettle();
}

Future<void> _choose(WidgetTester t, String current, String option) async {
  await t.tap(find.text(current).last);
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

Distribution _dist(List<int> n, {String? kelas}) {
  final classified = n.reduce((a, b) => a + b);
  return Distribution(
    total: classified + 2,
    classified: classified,
    incomplete: 1,
    withoutGrades: 1,
    className: kelas,
    categories: [
      for (var i = 0; i < 3; i++)
        CategoryCount(
          classification: Classification.values[i],
          count: n[i],
          percent: double.parse((n[i] / classified * 100).toStringAsFixed(1)),
        ),
    ],
  );
}

void main() {
  final errors = captureErrors();

  testWidgets('grade form: subject and component come from the admin setup', (t) async {
    final guru = await _boot(t);
    await _openGrades(t);
    expect(find.textContaining('Bahasa Indonesia · Ulangan Harian'), findsOneWidget);

    await t.tap(find.text('+ Tambah Nilai'));
    await t.pumpAndSettle();
    expect(find.text('Tugas (Literasi, bobot 40)'), findsOneWidget);

    // Komponen nonaktif tidak ditawarkan.
    await t.tap(find.text('Tugas (Literasi, bobot 40)'));
    await t.pumpAndSettle();
    expect(find.text('Lama'), findsNothing);
    await t.tap(find.text('Tugas (Literasi, bobot 40)').last);
    await t.pumpAndSettle();

    await _choose(t, 'Bahasa Indonesia', 'Bahasa Jawa (Muatan Lokal)');
    expect(find.text('Praktik'), findsOneWidget);
    expect(
      find.text('Komponen ini tidak dihitung untuk klasifikasi Literasi/Numerasi.'),
      findsOneWidget,
    );

    await t.enterText(find.byType(TextField).at(0), '91');
    await t.tap(find.text('Simpan Nilai'));
    await t.pumpAndSettle();
    final sent = guru.createdGrades.single;
    expect((sent.componentId, sent.value, sent.studentId), (110, 91, 1));
    await t.pump(const Duration(seconds: 3));
    expect(errors, isEmpty);
  });

  testWidgets('grade form explains why input is unavailable', (t) async {
    final guru = FakeGuruRepository()
      ..subjects = const [
        ClassSubject(
          id: 10,
          code: 'BIN',
          name: 'Bahasa Indonesia',
          type: SubjectType.umum,
          canInput: true,
          components: [],
        ),
      ];
    await _boot(t, guru: guru);
    await _openGrades(t);
    await t.tap(find.text('+ Tambah Nilai'));
    await t.pumpAndSettle();
    expect(
      find.text('Komponen penilaian untuk mapel Anda pada periode ini belum ditetapkan admin.'),
      findsOneWidget,
    );
    await t.tap(find.text('Tutup'));
    await t.pumpAndSettle();
    expect(guru.createdGrades, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets('period filter reloads class data for the chosen semester', (t) async {
    final guru = await _boot(t);
    await _openGrades(t);
    expect(guru.classDataPeriods.last, isNull);

    await _choose(t, 'Semester Ganjil 2026/2027 (aktif)', 'Semester Genap 2025/2026');
    expect(guru.classDataPeriods.last, 1);
    expect(errors, isEmpty);
  });

  testWidgets('stats screen shows classification counts, percentages and comparison', (t) async {
    final guru = FakeGuruRepository();
    guru.classification = ClassificationSummary(
      period: guru.periods.first,
      rule: const ClassificationRule(
        method: ClassificationMethod.average,
        mahirMin: 80,
        cukupMin: 65,
      ),
      overall: _dist([2, 1, 1]),
      perClass: [_dist([2, 1, 1], kelas: '5A')],
      comparison: PeriodComparison(
        period: guru.periods.last,
        before: _dist([1, 2, 1]),
        now: _dist([2, 1, 1]),
        compared: 4,
        up: 1,
        down: 0,
        same: 3,
      ),
      note: null,
    );
    await _boot(t, guru: guru);
    await t.tap(find.text('Kelas').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Statistik Kelas'));
    await t.pumpAndSettle();

    expect(find.text('2 siswa · 50%'), findsOneWidget);
    expect(find.text('1 siswa · 25%'), findsNWidgets(2));
    expect(find.textContaining('4 dari 6 siswa terklasifikasi'), findsOneWidget);
    expect(find.textContaining('Mahir ≥ 80'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Tren nilai Literasi kelas'), 200);
    expect(find.text('Terbaru: 78 (Minggu 5–11 Okt 2026)'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Naik 1 · Tetap 3 · Turun 0'), 200);
    expect(find.text('Naik 1 · Tetap 3 · Turun 0'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('stats screen tells when the rule or period is not set', (t) async {
    await _boot(t);
    await t.tap(find.text('Kelas').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Statistik Kelas'));
    await t.pumpAndSettle();
    expect(find.text('Periode akademik aktif belum ditetapkan admin.'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('recap per subject lists component averages and final score', (t) async {
    await _boot(t);
    await _openGrades(t);
    await t.tap(find.text('Rekap per Mapel'));
    await t.pumpAndSettle();
    expect(find.text('Bahasa Indonesia · Semester Ganjil 2026/2027'), findsOneWidget);
    expect(find.text('85'), findsNWidgets(2));
    expect(find.text('—'), findsOneWidget);
    expect(errors, isEmpty);
  });

  test('GradeInput keeps the component id', () {
    final input = GradeInput(
      studentId: 1,
      componentId: 5,
      assessment: '',
      value: 70,
      date: DateTime(2026, 9, 1),
      note: '',
    );
    expect(input.componentId, 5);
  });
}
