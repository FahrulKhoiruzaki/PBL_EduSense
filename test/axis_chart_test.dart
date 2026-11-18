import 'package:edu_sense/core/theme.dart';
import 'package:edu_sense/features/orang_tua/providers/parent_providers.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/widgets/axis_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

final _weeks = [
  TrendPoint(weekStart: DateTime(2026, 9, 28), value: 75, count: 2),
  TrendPoint(weekStart: DateTime(2026, 10, 5), value: 79, count: 3),
  TrendPoint(weekStart: DateTime(2026, 10, 19), value: 71.5, count: 1),
];

Future<void> _pump(WidgetTester t, Widget child, {ThemeData? theme}) async {
  await prepareFonts();
  t.view.physicalSize = const Size(800, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
  ));
  await t.pumpAndSettle();
}

ChartPanel _panel(List<ChartPoint> points, {String unit = '', ChartKind kind = ChartKind.line}) => ChartPanel(
      title: 'Literasi',
      description: 'Rata-rata nilai per minggu.',
      points: points,
      xTitle: 'Minggu (tanggal awal)',
      yTitle: unit == '%' ? 'Kehadiran (%)' : 'Nilai rata-rata',
      unit: unit,
      kind: kind,
      countLabel: 'nilai',
      emptyMessage: 'Belum ada nilai Literasi pada periode ini.',
      card: false,
    );

void main() {
  final errors = captureErrors();

  test('weekly points carry real dates as axis labels and week ranges as detail', () {
    final points = weeklyChartPoints(_weeks);
    expect(points.map((p) => p.label), ['28 Sep', '5 Okt', '19 Okt']);
    expect(points.first.detail, 'Minggu 28 Sep – 4 Okt 2026');
    expect(points[1].detail, 'Minggu 5–11 Okt 2026');
    expect((points[2].value, points[2].count), (71.5, 1));
  });

  test('trend set parses backend titik and tolerates an old backend without it', () {
    final set = TrendSet.fromJson({
      'literasi': [
        {'tanggal': '2026-10-05', 'nilai': 79.25, 'jumlah': 3},
      ],
      'numerasi': <Object>[],
      'kehadiran': [
        {'tanggal': '2026-10-05', 'nilai': 50.0, 'jumlah': 4},
      ],
    });
    expect((set.literasi.single.weekStart, set.literasi.single.value), (DateTime(2026, 10, 5), 79.25));
    expect(set.attendance.single.count, 4);
    expect(TrendSet.fromJson(null).literasi, isEmpty);
  });

  test('"Bulan ini" keeps only weeks overlapping the current month', () {
    final today = DateTime(2026, 10, 20);
    expect(pointsIn(_weeks, StatsPeriod.semester, today), _weeks);
    // Minggu 28 Sep - 4 Okt beririsan dengan Oktober, jadi ikut.
    expect(pointsIn(_weeks, StatsPeriod.bulan, today), _weeks);
    expect(pointsIn(_weeks, StatsPeriod.bulan, DateTime(2026, 11, 2)), isEmpty);
  });

  testWidgets('panel shows axes, fixed scale, latest value and a matching table', (t) async {
    await _pump(t, _panel(weeklyChartPoints(_weeks)));

    expect(find.text('Sumbu Y: Nilai rata-rata'), findsOneWidget);
    expect(find.text('Sumbu X: Minggu (tanggal awal)'), findsOneWidget);
    expect(find.text('Terbaru: 71.5 (Minggu 19–25 Okt 2026)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Literasi: 3 titik, terbaru 71.5')), findsOneWidget);

    await t.tap(find.text('Lihat tabel'));
    await t.pumpAndSettle();
    expect(find.text('Minggu 28 Sep – 4 Okt 2026'), findsOneWidget);
    expect(find.text('naik 4'), findsOneWidget);
    expect(find.text('turun 7.5'), findsOneWidget);
    expect(find.text('Jumlah nilai'), findsOneWidget);
    await t.tap(find.text('Lihat grafik'));
    await t.pumpAndSettle();
    expect(find.byType(AxisChart), findsOneWidget);
    expect(errors, isEmpty);
  });

  testWidgets('hover (web) and tap (touch) show the tooltip with value and change', (t) async {
    await _pump(t, _panel(weeklyChartPoints(_weeks)));
    final chart = find.byType(AxisChart);
    final box = t.getRect(chart);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // Titik kedua (5 Okt) berada 1/3 rentang waktu dari kiri area plot.
    await mouse.moveTo(Offset(box.left + 40 + (box.width - 52) / 3, box.center.dy));
    await t.pumpAndSettle();
    expect(find.text('Minggu 5–11 Okt 2026'), findsOneWidget);
    expect(find.text('naik 4 dari Minggu 28 Sep – 4 Okt 2026'), findsOneWidget);
    expect(find.text('Dari 3 nilai'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('Dari 3 nilai'), findsNothing);

    await t.tapAt(Offset(box.right - 14, box.center.dy));
    await t.pumpAndSettle();
    expect(find.text('Dari 1 nilai'), findsOneWidget);
    await t.tapAt(Offset(box.right - 14, box.center.dy));
    await t.pumpAndSettle();
    expect(find.text('Dari 1 nilai'), findsNothing);
    expect(errors, isEmpty);
  });

  testWidgets('empty data shows a message, not a fake chart', (t) async {
    await _pump(t, _panel(const []));
    expect(find.text('Belum ada nilai Literasi pada periode ini.'), findsOneWidget);
    expect(find.byType(AxisChart), findsNothing);
    expect(find.text('Lihat tabel'), findsNothing);
    expect(errors, isEmpty);
  });

  testWidgets('percent unit, single point, bar chart and dark mode render', (t) async {
    final single = weeklyChartPoints([TrendPoint(weekStart: DateTime(2026, 10, 5), value: 50, count: 4)]);
    await _pump(t, Column(children: [
      _panel(single, unit: '%'),
      _panel(
        const [
          ChartPoint(label: 'BIN', detail: 'Bahasa Indonesia', value: 86),
          ChartPoint(label: 'MTK', detail: 'Matematika', value: 72.5),
        ],
        kind: ChartKind.bar,
      ),
    ]), theme: AppTheme.dark);
    expect(find.text('Terbaru: 50% (Minggu 5–11 Okt 2026)'), findsOneWidget);

    await t.tap(find.text('Lihat tabel').last);
    await t.pumpAndSettle();
    expect(find.text('Bahasa Indonesia'), findsOneWidget);
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('Perubahan'), findsNothing); // kategori, bukan waktu: tanpa kolom perubahan
    expect(errors, isEmpty);
  });
}
