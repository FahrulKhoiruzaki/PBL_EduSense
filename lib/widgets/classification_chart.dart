import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/academic_models.dart';
import '../models/app_models.dart';
import 'common_widgets.dart';
import 'status_badge.dart';

/// Chart klasifikasi dari ringkasan server: jumlah dan persentase per kategori, dengan
/// keterangan siswa yang belum terklasifikasi. Persentase dihitung dari siswa terklasifikasi.
class ClassificationChart extends StatelessWidget {
  const ClassificationChart(this.distribution, {super.key});

  final Distribution distribution;

  @override
  Widget build(BuildContext context) {
    final d = distribution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final k in Classification.values) _CategoryBar(count: d.countOf(k)),
        const SizedBox(height: 4),
        Text(_coverage(d), style: context.styleCaption),
      ],
    );
  }
}

String _coverage(Distribution d) {
  final parts = ['${d.classified} dari ${d.total} siswa terklasifikasi'];
  if (d.incomplete > 0) parts.add('${d.incomplete} data belum lengkap');
  if (d.withoutGrades > 0) parts.add('${d.withoutGrades} belum ada nilai');
  return parts.join(' · ');
}

String percentLabel(double value) =>
    value == value.roundToDouble() ? '${value.toStringAsFixed(0)}%' : '${value.toStringAsFixed(1)}%';

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.count});

  final CategoryCount count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = count.classification;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(k.icon, size: 12, color: c.st),
              const SizedBox(width: 4),
              Expanded(child: Text(k.label, style: context.styleBody)),
              Text(
                '${count.count} siswa · ${percentLabel(count.percent)}',
                style: context.styleBold,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: c.mi)),
                  FractionallySizedBox(
                    widthFactor: (count.percent / 100).clamp(0, 1),
                    child: SizedBox.expand(child: _fill(context, k)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _fill(BuildContext context, Classification k) {
  final c = context.colors;
  return switch (k) {
    Classification.mahir => ColoredBox(color: c.primary),
    Classification.cukup => ColoredBox(color: c.lavender),
    Classification.perlu => CustomPaint(painter: StripePainter(base: c.amber.withAlpha(90), stripe: c.amber, period: 4)),
  };
}

/// Satu baris bertumpuk 100% per kelas, untuk membandingkan proporsi antarkelas.
class ClassComparisonChart extends StatelessWidget {
  const ClassComparisonChart(this.rows, {super.key});

  final List<Distribution> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Kelas ${row.className ?? '-'}', style: context.styleBold),
                    ),
                    Text(
                      row.classified == 0
                          ? 'Belum ada yang terklasifikasi'
                          : [
                              for (final k in Classification.values)
                                '${k.code} ${row.countOf(k).count} (${percentLabel(row.countOf(k).percent)})',
                            ].join(' · '),
                      style: context.styleCaption,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    height: 10,
                    child: row.classified == 0
                        ? ColoredBox(color: c.mi, child: const SizedBox.expand())
                        : Row(
                            children: [
                              for (final k in Classification.values)
                                if (row.countOf(k).count > 0)
                                  Expanded(flex: row.countOf(k).count, child: _fill(context, k)),
                            ],
                          ),
                  ),
                ),
                Text(_coverage(row), style: context.styleCaption),
              ],
            ),
          ),
        Text(
          'M = Mahir · C = Cukup · P = Perlu Pendampingan. Persentase dari siswa terklasifikasi.',
          style: context.styleCaption,
        ),
      ],
    );
  }
}

/// Perbandingan kohort yang sama dengan periode sebelumnya.
class PeriodComparisonView extends StatelessWidget {
  const PeriodComparisonView(this.comparison, {super.key});

  final PeriodComparison comparison;

  @override
  Widget build(BuildContext context) {
    final p = comparison;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dibanding ${p.period.label} (${p.compared} siswa yang sama)',
          style: context.styleCaption,
        ),
        const SizedBox(height: 6),
        for (final k in Classification.values)
          DetailRow(
            label: k.label,
            value: '${p.before.countOf(k).count} → ${p.now.countOf(k).count} siswa',
            labelWidth: 140,
          ),
        const SizedBox(height: 6),
        Text('Naik ${p.up} · Tetap ${p.same} · Turun ${p.down}', style: context.styleBold),
      ],
    );
  }
}

/// Isi lengkap kartu klasifikasi: catatan aturan, chart, dan perbandingan (bila ada).
class ClassificationSummaryView extends StatelessWidget {
  const ClassificationSummaryView(this.summary, {super.key, this.showPerClass = false});

  final ClassificationSummary summary;
  final bool showPerClass;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.note != null) InfoBanner(s.note!),
        if (s.period != null && s.rule != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${s.rule!.method.label} · Mahir ≥ ${formatScore(s.rule!.mahirMin)} · '
              'Cukup ≥ ${formatScore(s.rule!.cukupMin)}',
              style: context.styleCaption,
            ),
          ),
        if (s.period != null)
          s.overall.total == 0
              ? const EmptyState('Belum ada siswa pada periode ini.')
              : ClassificationChart(s.overall),
        if (showPerClass && s.perClass.length > 1) ...[
          const SizedBox(height: 12),
          const Kick('Perbandingan antarkelas'),
          ClassComparisonChart(s.perClass),
        ],
        if (s.comparison != null) ...[
          const SizedBox(height: 12),
          const Kick('Perbandingan dengan periode sebelumnya'),
          PeriodComparisonView(s.comparison!),
        ],
      ],
    );
  }
}
