import 'package:aplikasi_guru/core/network/api_exception.dart';
import 'package:aplikasi_guru/features/orang_tua/providers/parent_providers.dart';
import 'package:aplikasi_guru/features/orang_tua/screens/parent_main_layout.dart';
import 'package:aplikasi_guru/models/app_models.dart';
import 'package:aplikasi_guru/repositories/parent_repository.dart';
import 'package:aplikasi_guru/widgets/sidebar_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/test_env.dart';

Future<ProviderContainer> _boot(
  WidgetTester t,
  FakeParentRepository repo, {
  Size size = const Size(390, 844),
}) async {
  await prepareFonts();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [parentRepositoryProvider.overrideWithValue(repo)],
    child: harnessApp(const ParentMainLayout()),
  ));
  await t.pumpAndSettle();
  return ProviderScope.containerOf(t.element(find.byType(ParentMainLayout)));
}

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(label)));
  await t.pumpAndSettle();
}

void main() {
  final errors = captureErrors();

  testWidgets('dashboard comes from the repository and the kid can be switched', (t) async {
    final container = await _boot(t, FakeParentRepository());
    expect(find.text('Perkembangan Anak'), findsOneWidget);
    expect(find.text('Ahmad Rizky'), findsWidgets);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('2 kali'), findsOneWidget);
    expect(find.textContaining('Wali kelas Bu Rina'), findsOneWidget);
    expect(find.textContaining('Diperbarui: 8 Oktober 2026'), findsOneWidget);
    expect(find.textContaining('contoh'), findsNothing);

    await t.tap(find.byType(DropdownButton<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Aisyah Rizky · Kelas 2A').last);
    await t.pumpAndSettle();
    expect(container.read(selectedKidIndexProvider), 1);
    expect(find.text('90'), findsOneWidget);

    await t.tap(find.text('Lihat Statistik'));
    await t.pumpAndSettle();
    expect(find.text('Riwayat klasifikasi'), findsOneWidget);
    await t.tap(find.text('Bulan ini'));
    await t.pumpAndSettle();
    expect(container.read(statsPeriodProvider), StatsPeriod.bulan);
    expect(errors, isEmpty);
  });

  testWidgets('children load failure offers retry', (t) async {
    final repo = FakeParentRepository()
      ..failChildren = apiError('Server tidak merespons.', type: ApiErrorType.server);
    await _boot(t, repo);
    expect(find.text('Data belum dapat dimuat.'), findsOneWidget);

    repo.failChildren = null;
    await t.tap(find.text('Coba Lagi'));
    await t.pumpAndSettle();
    expect(find.text('Perkembangan Anak'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('grades: filter, search, detail, back', (t) async {
    final container = await _boot(t, FakeParentRepository());
    await _tab(t, 'Nilai');
    expect(find.text('Literasi · Ulangan Harian 3'), findsOneWidget);

    await t.tap(find.text('Numerasi').first);
    await t.pumpAndSettle();
    expect(find.text('Literasi · Ulangan Harian 3'), findsNothing);
    expect(find.text('Numerasi · Tugas 2'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'zzz');
    await t.pumpAndSettle();
    expect(find.text('Nilai tidak ditemukan.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'tugas');
    await t.pumpAndSettle();

    await t.tap(find.text('Numerasi · Tugas 2'));
    await t.pumpAndSettle();
    expect(find.text('Detail Nilai'), findsOneWidget);
    expect(find.textContaining('▲ 1 dari sebelumnya (75)'), findsOneWidget);
    expect(find.text('5 Oktober 2026'), findsOneWidget);

    await t.tap(find.text('Kembali ke Nilai'));
    await t.pumpAndSettle();
    expect(container.read(selectedGradeIdProvider), isNull);
    expect(errors, isEmpty);
  });

  testWidgets('attendance: months come from the records, calendar and filters work', (t) async {
    final container = await _boot(t, FakeParentRepository());
    await _tab(t, 'Hadir');

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(container.read(selectedMonthProvider), DateTime(2026, 10));
    expect(container.read(monthlyAttendanceSummaryProvider).total, 6);

    await t.tap(find.text('September 2026'));
    await t.pumpAndSettle();
    final summary = container.read(monthlyAttendanceSummaryProvider);
    expect(summary.total, 22);
    expect(summary.percent, 91);

    await t.tap(find.bySemanticsLabel('9 Terlambat'));
    await t.pump();
    expect(find.textContaining('Datang setelah bel masuk'), findsOneWidget);
    expect(container.read(attendanceDayProvider), 9);

    await t.scrollUntilVisible(find.text('Izin').first, 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Izin').last);
    await t.pumpAndSettle();
    expect(container.read(attendanceStatusFilterProvider), AttendanceStatus.izin);
    expect(find.text('15 Sep'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('history comes from the repository and filters by kind', (t) async {
    await _boot(t, FakeParentRepository());
    await _tab(t, 'Riwayat');
    expect(find.text('Literasi 85'), findsOneWidget);
    expect(find.text('6 Okt 2026 · Nilai'), findsOneWidget);

    await t.tap(find.text('Klasifikasi').first);
    await t.pumpAndSettle();
    expect(find.text('Literasi 85'), findsNothing);
    expect(find.text('Tidak berubah dari bulan lalu.'), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('more sheet, profile uses server values and WhatsApp dialog', (t) async {
    await _boot(t, FakeParentRepository());
    await _tab(t, 'Lainnya');
    await t.tap(find.text('Profil Anak'));
    await t.pumpAndSettle();
    expect(find.text('12345'), findsOneWidget);
    expect(find.text('Bu Rina'), findsOneWidget);
    expect(find.text('2026/2027'), findsOneWidget);

    await t.tap(find.text('Data tidak sesuai? Hubungi sekolah via WhatsApp'));
    await t.pump();
    expect(find.text('Membuka WhatsApp…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('Lanjutkan ke WhatsApp'), findsOneWidget);
    await t.tap(find.text('Batal'));
    await t.pumpAndSettle();
    expect(errors, isEmpty);
  });

  testWidgets('notifications open their target and are marked read on the server', (t) async {
    final repo = FakeParentRepository();
    final container = await _boot(t, repo);
    expect(container.read(hasUnreadProvider), isTrue);

    await t.tap(find.byTooltip('Notifikasi'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Nilai Literasi baru ditambahkan.'));
    await t.pumpAndSettle();
    expect(find.text('Detail Nilai'), findsOneWidget);
    expect(repo.markedRead, [11]);

    await t.tap(find.byTooltip('Notifikasi'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tandai semua sudah dibaca'));
    await t.pumpAndSettle();
    expect(container.read(hasUnreadProvider), isFalse);
    expect(repo.markedRead, containsAll([11, 12]));
    expect(errors, isEmpty);
  });

  testWidgets('desktop: sidebar shown, bottom bar hidden', (t) async {
    await _boot(t, FakeParentRepository(), size: const Size(1300, 900));
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Portal Orang Tua'), findsOneWidget);

    await t.tap(find.descendant(of: find.byType(SidebarPanel), matching: find.text('Kehadiran')));
    await t.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(errors, isEmpty);
  });
}
