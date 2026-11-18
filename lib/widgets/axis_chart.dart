import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/academic_models.dart';
import 'common_widgets.dart';
import 'custom_card.dart';

/// Komponen grafik bersama untuk Guru, Wali Kelas, dan Orang Tua.
///
/// Prinsip: skala Y tetap (bawaan 0–100) agar perubahan kecil tidak tampak dramatis; sumbu X
/// memakai label data asli; titik tanpa data tidak digambar (tidak ada nol palsu); setiap grafik
/// punya tooltip (hover di web, ketuk di layar sentuh) dan tabel data dengan dataset yang sama.

@immutable
class ChartPoint {
  const ChartPoint({
    required this.label,
    required this.detail,
    required this.value,
    this.date,
    this.count,
  });

  /// Label pendek di sumbu X (mis. "6 Okt" atau "BIN").
  final String label;

  /// Label lengkap di tooltip dan tabel (mis. "Minggu 6–12 Okt 2026" atau "Bahasa Indonesia").
  final String detail;
  final double value;

  /// Bila ada, posisi X mengikuti waktu (jarak antartitik sesuai jarak tanggal).
  final DateTime? date;

  /// Jumlah data pembentuk titik (mis. jumlah nilai); null bila tidak relevan.
  final int? count;
}

enum ChartKind { line, bar }

/// Warna seri grafik yang konsisten di semua halaman (tidak acak per halaman).
enum ChartTone { literasi, numerasi, attendance, subject }

Color chartToneColor(AppColors c, ChartTone tone) => switch (tone) {
      ChartTone.literasi => c.primary,
      ChartTone.numerasi => c.chartNumerasi,
      ChartTone.attendance => c.chartAttendance,
      ChartTone.subject => c.chartSubject,
    };

/// Format angka: tanpa desimal bila bulat, selain itu satu desimal.
String chartNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _withUnit(double v, String unit) => unit == '%' ? '${chartNumber(v)}%' : chartNumber(v);

String _change(double now, double before, String unit) {
  final d = now - before;
  if (d.abs() < 0.05) return 'tetap';
  final text = unit == '%' ? '${chartNumber(d.abs())} poin persen' : chartNumber(d.abs());
  return d > 0 ? 'naik $text' : 'turun $text';
}

/// Titik tren mingguan backend -> titik grafik berlabel tanggal.
List<ChartPoint> weeklyChartPoints(List<TrendPoint> points) => [
      for (final p in points)
        ChartPoint(
          label: '${p.weekStart.day} ${monthNameShort(p.weekStart.month)}',
          detail: 'Minggu ${_weekRange(p)}',
          value: p.value,
          date: p.weekStart,
          count: p.count,
        ),
    ];

String _weekRange(TrendPoint p) {
  final a = p.weekStart, b = p.weekEnd;
  if (a.month == b.month) return '${a.day}–${b.day} ${monthNameShort(b.month)} ${b.year}';
  if (a.year == b.year) {
    return '${a.day} ${monthNameShort(a.month)} – ${b.day} ${monthNameShort(b.month)} ${b.year}';
  }
  return '${formatDate(a)} – ${formatDate(b)}';
}

/// Kartu grafik lengkap: judul, deskripsi, keterangan sumbu, grafik/tabel, dan keadaan kosong.
class ChartPanel extends StatefulWidget {
  const ChartPanel({
    super.key,
    required this.title,
    required this.description,
    required this.points,
    required this.xTitle,
    required this.yTitle,
    this.unit = '',
    this.kind = ChartKind.line,
    this.yMin = 0,
    this.yMax = 100,
    this.yStep = 25,
    this.countLabel = 'data',
    this.emptyMessage = 'Belum ada data untuk ditampilkan.',
    this.color,
    this.tone = ChartTone.literasi,
    this.card = true,
  });

  final String title;
  final String description;
  final List<ChartPoint> points;
  final String xTitle;
  final String yTitle;

  /// '' untuk nilai, '%' untuk persentase.
  final String unit;
  final ChartKind kind;
  final double yMin;
  final double yMax;
  final double yStep;

  /// Nama satuan [ChartPoint.count], mis. "nilai" atau "catatan absensi".
  final String countLabel;
  final String emptyMessage;
  final Color? color;

  /// Warna seri bila [color] tidak diberikan.
  final ChartTone tone;
  final bool card;

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  var _table = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Kick(w.title, bottom: 2)),
            if (w.points.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _table = !_table),
                child: Text(_table ? 'Lihat grafik' : 'Lihat tabel'),
              ),
          ],
        ),
        Text(w.description, style: context.styleCaption),
        const SizedBox(height: 8),
        if (w.points.isEmpty)
          EmptyState(w.emptyMessage)
        else if (_table)
          ChartDataTable(
            points: w.points,
            xTitle: w.xTitle,
            yTitle: w.yTitle,
            unit: w.unit,
            countLabel: w.countLabel,
            showChange: w.kind == ChartKind.line,
          )
        else ...[
          Text('Sumbu Y: ${w.yTitle}', style: context.styleCaption),
          AxisChart(
            points: w.points,
            kind: w.kind,
            unit: w.unit,
            yMin: w.yMin,
            yMax: w.yMax,
            yStep: w.yStep,
            countLabel: w.countLabel,
            color: w.color ?? chartToneColor(context.colors, w.tone),
            semanticTitle: w.title,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Sumbu X: ${w.xTitle}', style: context.styleCaption),
          ),
          if (w.kind == ChartKind.line)
            Text(
              'Terbaru: ${_withUnit(w.points.last.value, w.unit)} (${w.points.last.detail})',
              style: context.styleCaption.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ],
    );
    return w.card ? CustomCard(child: body) : body;
  }
}

/// Tabel data dengan dataset yang sama dengan grafik.
class ChartDataTable extends StatelessWidget {
  const ChartDataTable({
    super.key,
    required this.points,
    required this.xTitle,
    required this.yTitle,
    this.unit = '',
    this.countLabel = 'data',
    this.showChange = true,
  });

  final List<ChartPoint> points;
  final String xTitle;
  final String yTitle;
  final String unit;
  final String countLabel;
  final bool showChange;

  @override
  Widget build(BuildContext context) {
    final hasCount = points.any((p) => p.count != null);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 20,
        columns: [
          DataColumn(label: Text(xTitle)),
          DataColumn(numeric: true, label: Text(yTitle)),
          if (showChange) const DataColumn(label: Text('Perubahan')),
          if (hasCount) DataColumn(numeric: true, label: Text('Jumlah $countLabel')),
        ],
        rows: [
          for (var i = 0; i < points.length; i++)
            DataRow(cells: [
              DataCell(Text(points[i].detail)),
              DataCell(Text(_withUnit(points[i].value, unit))),
              if (showChange)
                DataCell(Text(i == 0 ? '—' : _change(points[i].value, points[i - 1].value, unit))),
              if (hasCount) DataCell(Text(points[i].count?.toString() ?? '—')),
            ]),
        ],
      ),
    );
  }
}

/// Grafik garis/batang dengan sumbu, garis bantu, dan tooltip.
class AxisChart extends StatefulWidget {
  const AxisChart({
    super.key,
    required this.points,
    this.kind = ChartKind.line,
    this.unit = '',
    this.yMin = 0,
    this.yMax = 100,
    this.yStep = 25,
    this.countLabel = 'data',
    this.height = 200,
    this.color,
    this.semanticTitle = 'Grafik',
  });

  final List<ChartPoint> points;
  final ChartKind kind;
  final String unit;
  final double yMin;
  final double yMax;
  final double yStep;
  final String countLabel;
  final double height;
  final Color? color;
  final String semanticTitle;

  @override
  State<AxisChart> createState() => _AxisChartState();
}

class _AxisChartState extends State<AxisChart> {
  int? _hover;
  int? _pinned;

  int? get _selected => _hover ?? _pinned;

  @override
  void didUpdateWidget(AxisChart old) {
    super.didUpdateWidget(old);
    // Data berubah (mis. filter periode): pilihan lama tidak lagi berlaku.
    if (old.points != widget.points) {
      _hover = null;
      _pinned = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget;
    final last = w.points.last;
    return Semantics(
      label: '${w.semanticTitle}: ${w.points.length} titik, '
          '${w.kind == ChartKind.line ? 'terbaru' : 'terakhir'} ${_withUnit(last.value, w.unit)} '
          'pada ${last.detail}. Gunakan Lihat tabel untuk semua nilai.',
      child: SizedBox(
        height: w.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final geo = _ChartGeometry(
              size: Size(box.maxWidth, w.height),
              points: w.points,
              kind: w.kind,
              yMin: w.yMin,
              yMax: w.yMax,
            );
            final selected = _selected;
            return MouseRegion(
              onHover: (e) => setState(() => _hover = geo.nearest(e.localPosition)),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (e) {
                  final i = geo.nearest(e.localPosition);
                  setState(() => _pinned = _pinned == i ? null : i);
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _AxisPainter(
                          geo: geo,
                          kind: w.kind,
                          unit: w.unit,
                          yStep: w.yStep,
                          selected: selected,
                          line: w.color ?? c.primary,
                          grid: c.mi,
                          axis: c.si,
                          label: c.st,
                          surface: c.su,
                          textStyle: context.styleCaption,
                        ),
                      ),
                    ),
                    if (selected != null)
                      _Tooltip(
                        geo: geo,
                        index: selected,
                        points: w.points,
                        unit: w.unit,
                        countLabel: w.countLabel,
                        showChange: w.kind == ChartKind.line,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChartGeometry {
  _ChartGeometry({
    required this.size,
    required this.points,
    required this.kind,
    required this.yMin,
    required this.yMax,
  }) : plot = Rect.fromLTRB(40, 14, size.width - 12, size.height - 26);

  final Size size;
  final List<ChartPoint> points;
  final ChartKind kind;
  final double yMin;
  final double yMax;
  final Rect plot;

  double get band => plot.width / points.length;

  double x(int i) {
    if (kind == ChartKind.bar) return plot.left + band * (i + 0.5);
    if (points.length == 1) return plot.center.dx;
    final first = points.first.date, lastDate = points.last.date;
    if (first != null && lastDate != null && lastDate.isAfter(first)) {
      final span = lastDate.difference(first).inHours;
      final at = points[i].date!.difference(first).inHours;
      return plot.left + plot.width * at / span;
    }
    return plot.left + plot.width * i / (points.length - 1);
  }

  double y(double v) {
    final t = ((v.clamp(yMin, yMax) - yMin) / (yMax - yMin));
    return plot.bottom - plot.height * t;
  }

  int nearest(Offset p) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (x(i) - p.dx).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.geo,
    required this.kind,
    required this.unit,
    required this.yStep,
    required this.selected,
    required this.line,
    required this.grid,
    required this.axis,
    required this.label,
    required this.surface,
    required this.textStyle,
  });

  final _ChartGeometry geo;
  final ChartKind kind;
  final String unit;
  final double yStep;
  final int? selected;
  final Color line;
  final Color grid;
  final Color axis;
  final Color label;
  final Color surface;
  final TextStyle textStyle;

  TextPainter _text(String s) => TextPainter(
        text: TextSpan(text: s, style: textStyle.copyWith(color: label, fontSize: 11, height: 1.2)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final plot = geo.plot;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Sumbu Y: skala tetap + garis bantu horizontal.
    for (var v = geo.yMin; v <= geo.yMax + 0.001; v += yStep) {
      final y = geo.y(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final t = _text(_withUnit(v, unit));
      t.paint(canvas, Offset(plot.left - 6 - t.width, y - t.height / 2));
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.2;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axisPaint);

    // Sumbu X: label data asli, dijarangkan agar tidak bertumpuk (pertama & terakhir diutamakan).
    final n = geo.points.length;
    final labels = [for (var i = 0; i < n; i++) _text(geo.points[i].label)];
    final widest = labels.map((t) => t.width).fold<double>(0, math.max) + 10;
    final room = math.max(1, (plot.width / widest).floor());
    final step = (n / room).ceil();
    final shown = <int>{for (var i = 0; i < n; i += step) i, n - 1};
    var rightEdge = double.negativeInfinity;
    for (final i in shown.toList()..sort()) {
      final t = labels[i];
      final left = (geo.x(i) - t.width / 2).clamp(0.0, size.width - t.width);
      if (left < rightEdge + 4) continue;
      t.paint(canvas, Offset(left, plot.bottom + 6));
      rightEdge = left + t.width;
    }

    final fill = Paint()..color = line;
    if (kind == ChartKind.bar) {
      final width = math.min(36.0, geo.band * 0.6);
      for (var i = 0; i < n; i++) {
        final x = geo.x(i);
        final rect = Rect.fromLTRB(x - width / 2, geo.y(geo.points[i].value), x + width / 2, plot.bottom);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          i == selected ? fill : (Paint()..color = line.withAlpha(185)),
        );
      }
      return;
    }

    final points = [for (var i = 0; i < n; i++) Offset(geo.x(i), geo.y(geo.points[i].value))];
    if (n > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (var i = 0; i < n; i++) {
      final isSelected = i == selected, isLast = i == n - 1;
      if (isSelected) {
        canvas.drawLine(Offset(points[i].dx, plot.top), Offset(points[i].dx, plot.bottom), gridPaint);
        canvas.drawCircle(points[i], 8, Paint()..color = line.withAlpha(60));
      }
      canvas.drawCircle(points[i], isSelected || isLast ? 5 : 3.5, fill);
      // Titik terbaru diberi inti terang agar terbedakan tanpa bergantung pada warna saja.
      if (isLast) canvas.drawCircle(points[i], 2, Paint()..color = surface);
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.geo.points != geo.points ||
      old.geo.size != geo.size ||
      old.selected != selected ||
      old.line != line ||
      old.grid != grid;
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.geo,
    required this.index,
    required this.points,
    required this.unit,
    required this.countLabel,
    required this.showChange,
  });

  final _ChartGeometry geo;
  final int index;
  final List<ChartPoint> points;
  final String unit;
  final String countLabel;
  final bool showChange;

  @override
  Widget build(BuildContext context) {
    const width = 190.0;
    final c = context.colors;
    final p = points[index];
    final left = (geo.x(index) - width / 2).clamp(0.0, math.max(0.0, geo.size.width - width)).toDouble();
    final style = context.styleCaption.copyWith(color: c.su, height: 1.35);
    return Positioned(
      left: left,
      top: 0,
      width: width,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.detail, style: style.copyWith(fontWeight: FontWeight.w700)),
                Text(_withUnit(p.value, unit), style: style.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                if (showChange && index > 0)
                  Text(
                    '${_change(p.value, points[index - 1].value, unit)} dari ${points[index - 1].detail}',
                    style: style,
                  ),
                if (p.count != null) Text('Dari ${p.count} $countLabel', style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
