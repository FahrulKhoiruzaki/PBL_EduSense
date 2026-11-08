import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../providers/parent_providers.dart';

class ParentTitle extends StatelessWidget {
  const ParentTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.styleH1.copyWith(fontSize: 28, height: 1.1));
  }
}

class ParentBackLink extends StatelessWidget {
  const ParentBackLink(this.text, {super.key, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: context.styleCaption.copyWith(
            fontSize: 13,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.labelWidth = 130});

  final String label;
  final Widget value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: labelWidth, child: Text(label, style: context.styleSoft)),
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: value),
            ),
          ],
        ),
      ),
    );
  }
}

class ParentLineChart extends StatelessWidget {
  const ParentLineChart(this.values, {super.key, this.height = 90});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 300 / height,
          child: CustomPaint(
            painter: _LineChartPainter(
              values: values,
              height: height,
              line: c.ink,
              surface: c.su,
              baseline: c.si,
            ),
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Terbaru: '),
              TextSpan(
                text: '${values.last}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          style: context.styleCaption.copyWith(fontSize: 13),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.values,
    required this.height,
    required this.line,
    required this.surface,
    required this.baseline,
  });

  final List<int> values;
  final double height;
  final Color line;
  final Color surface;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300);

    canvas.drawLine(
      Offset(0, height - 1),
      Offset(300, height - 1),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = maxValue == minValue ? 1 : maxValue - minValue;
    final steps = values.length > 1 ? values.length - 1 : 1;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          8 + i * 284 / steps,
          height - 10 - (values[i] - minValue) / range * (height - 24),
        ),
    ];

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

    for (final p in points) {
      canvas.drawCircle(p, 2.5, Paint()..color = surface);
      canvas.drawCircle(
        p,
        2.5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(points.last, 5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.height != height ||
      old.line != line ||
      old.surface != surface ||
      old.baseline != baseline;
}

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.date,
    required this.title,
    required this.description,
  });

  final String date;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.only(left: 18, bottom: 18),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.si))),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -23,
            top: 6,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: context.styleCaption.copyWith(fontSize: 13)),
              Text(title, style: context.styleBold),
              Text(description, style: context.styleSoft),
            ],
          ),
        ],
      ),
    );
  }
}

class ParentSearchField extends ConsumerStatefulWidget {
  const ParentSearchField({super.key, required this.hint});

  final String hint;

  @override
  ConsumerState<ParentSearchField> createState() => _ParentSearchFieldState();
}

class _ParentSearchFieldState extends ConsumerState<ParentSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(gradeQueryProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gradeQueryProvider, (_, next) {
      if (next != _controller.text) _controller.text = next;
    });
    return TextField(
      controller: _controller,
      style: context.styleBody,
      decoration: InputDecoration(hintText: widget.hint),
      onChanged: (v) => ref.read(gradeQueryProvider.notifier).set(v),
    );
  }
}

class KidSelector extends ConsumerWidget {
  const KidSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final kids = ref.watch(anakListProvider).value ?? const <Anak>[];
    final index = ref.watch(selectedKidIndexProvider);
    if (kids.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Pilih anak',
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: ShapeDecoration(
          color: c.su,
          shape: StadiumBorder(side: BorderSide(color: c.si)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: math.min(index, kids.length - 1),
            dropdownColor: c.su,
            borderRadius: BorderRadius.circular(12),
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            style: context.styleBold.copyWith(fontWeight: FontWeight.w600),
            items: [
              for (var i = 0; i < kids.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text('${kids[i].nama} · Kelas ${kids[i].kelas}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) ref.read(selectedKidIndexProvider.notifier).select(v);
            },
          ),
        ),
      ),
    );
  }
}
