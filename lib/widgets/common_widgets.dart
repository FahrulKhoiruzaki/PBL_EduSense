import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';
import 'avatar.dart';
import 'custom_card.dart';
import 'status_badge.dart';

InlineSpan iconSpan(IconData icon, Color color, {double size = 12}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(icon, size: size, color: color),
    );

class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.children,
    this.title,
    this.backBar = false,
    this.banner,
    this.barIcon = Icons.arrow_back,
    this.barTooltip = 'Kembali',
  });

  final List<Widget> children;
  final String? title;
  final bool backBar;
  final String? banner;
  final IconData barIcon;
  final String barTooltip;

  @override
  Widget build(BuildContext context) {
    final hasBar = backBar || title != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, hasBar && banner == null ? 8 : 16, 16, 24),
          children: [
            if (banner != null) InfoBanner(banner!),
            if (hasBar) ScreenBar(title: title, icon: barIcon, tooltip: barTooltip),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ScreenBar extends StatelessWidget {
  const ScreenBar({
    super.key,
    this.title,
    this.icon = Icons.arrow_back,
    this.tooltip = 'Kembali',
    this.bottom = 8,
  });

  final String? title;
  final IconData icon;
  final String tooltip;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Transform.translate(
        offset: const Offset(-8, 0),
        child: Row(
          children: [
            IconButton(
              tooltip: tooltip,
              icon: Icon(icon, size: 22),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            if (title != null) Text(title!, style: context.styleBold),
          ],
        ),
      ),
    );
  }
}

class Kick extends StatelessWidget {
  const Kick(this.text, {super.key, this.bottom = 6, this.color});

  final String text;
  final double bottom;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(text, style: context.styleKick.copyWith(color: color)),
    );
  }
}

class RowList extends StatelessWidget {
  const RowList({super.key, required this.children, this.dividerBeforeFirst = false});

  final List<Widget> children;
  final bool dividerBeforeFirst;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(height: 1, thickness: 1, color: context.colors.mi);
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 || dividerBeforeFirst) divider,
          children[i],
        ],
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: child,
        ),
      ),
    );
  }
}

class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      onTap: onTap,
      child: Row(
        children: [
          Avatar(name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.styleBold),
                Text(subtitle, style: context.styleCaption),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.title, this.subtitle, this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.styleBold),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: context.styleCaption),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: context.colors.ink),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.labelWidth});

  final String label;
  final String value;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: context.styleMuted);
    return _RowShell(
      onTap: null,
      child: Row(
        children: [
          if (labelWidth != null)
            SizedBox(width: labelWidth, child: labelText)
          else
            Expanded(child: labelText),
          if (labelWidth != null) const SizedBox(width: 12),
          if (labelWidth != null)
            Expanded(child: Text(value, style: context.styleBold))
          else
            Text(value, style: context.styleBold),
        ],
      ),
    );
  }
}

class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String value, String label)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in options) ...[
              Material(
                color: selected == value ? c.ink : c.mi,
                borderRadius: BorderRadius.circular(99),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(value),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          style: context.styleBody.copyWith(
                            color: selected == value ? c.su : c.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class SearchField extends ConsumerStatefulWidget {
  const SearchField({super.key, required this.scope, required this.hint});

  final String scope;
  final String hint;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: context.styleBody,
      decoration: InputDecoration(hintText: widget.hint),
      onChanged: (v) =>
          ref.read(searchQueryProvider(widget.scope).notifier).set(v),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(
    this.text, {
    super.key,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.child,
  });

  final String text;
  final EdgeInsetsGeometry margin;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.mi,
          borderRadius: BorderRadius.circular(10),
        ),
        child: child ?? Text(text, style: context.styleMedium),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(message, style: context.styleMuted, textAlign: TextAlign.center),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.percent, this.topMargin = 12});

  final int percent;
  final double topMargin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: topMargin),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.mi)),
              FractionallySizedBox(
                widthFactor: (percent / 100).clamp(0, 1),
                child: ColoredBox(color: c.ink, child: const SizedBox.expand()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DistributionBar extends StatelessWidget {
  const DistributionBar(this.distribution, {super.key});

  final ClassificationDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fills = <Classification, Widget>{
      Classification.mahir: ColoredBox(color: c.ink),
      Classification.cukup: ColoredBox(color: c.si),
      Classification.perlu: CustomPaint(
        painter: StripePainter(base: c.mi, stripe: c.st, period: 4),
      ),
    };
    final segments = [
      for (final k in Classification.values)
        if (distribution.countOf(k) > 0)
          Expanded(flex: distribution.countOf(k), child: fills[k]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  segments[i],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < Classification.values.length; i++) ...[
                if (i > 0) const TextSpan(text: ' · '),
                iconSpan(Classification.values[i].icon, c.st, size: 10),
                TextSpan(
                  text:
                      ' ${Classification.values[i].label} ${distribution.countOf(Classification.values[i])}',
                ),
              ],
            ],
          ),
          style: context.styleCaption,
        ),
      ],
    );
  }
}

class FiveStats extends StatelessWidget {
  const FiveStats(this.summary, {super.key, this.topMargin = 14});

  final AttendanceSummary summary;
  final double topMargin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: topMargin),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in AttendanceStatus.values)
            Expanded(
              child: Column(
                children: [
                  Text('${summary.countOf(status)}', style: context.styleNum),
                  Text.rich(
                    TextSpan(
                      children: [
                        iconSpan(status.icon, c.st),
                        TextSpan(text: ' ${status.label}'),
                      ],
                    ),
                    style: context.styleCaption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, this.height = 56});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (values.isEmpty) {
      return AspectRatio(aspectRatio: 300 / height, child: const SizedBox.shrink());
    }
    return AspectRatio(
      aspectRatio: 300 / height,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, height: height, line: c.ink, base: c.si),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.height,
    required this.line,
    required this.base,
  });

  final List<int> values;
  final double height;
  final Color line;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300);

    canvas.drawLine(
      Offset(0, height - 1),
      Offset(300, height - 1),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = maxV == minV ? 1 : maxV - minV;
    final steps = values.length > 1 ? values.length - 1 : 1;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          6 + i * 288 / steps,
          height - 6 - (values[i] - minV) / range * (height - 14),
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
    canvas.drawCircle(points.last, 4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.height != height || old.line != line || old.base != base;
}

class TimelineEntry extends StatelessWidget {
  const TimelineEntry({super.key, required this.date, required this.title, required this.description});

  final String date;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.only(left: 16, bottom: 16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.colors.si)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: context.styleCaption),
          Text(title, style: context.styleBold),
          Text(description, style: context.styleBody),
        ],
      ),
    );
  }
}

class TwoColumnGrid extends StatelessWidget {
  const TwoColumnGrid({super.key, required this.children, this.spacing = 12});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) SizedBox(height: spacing),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                SizedBox(width: spacing),
                Expanded(
                  child: i + 1 < children.length ? children[i + 1] : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.styleCaption),
          Text(value, style: context.styleBig),
        ],
      ),
    );
  }
}

class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({super.key, this.height = 84});

  final double height;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final center = -2 + 4 * _controller.value;
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment(center - 1, 0),
                end: Alignment(center + 1, 0),
                colors: [c.mi, c.su, c.mi],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ClassPill extends ConsumerWidget {
  const ClassPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cls = ref.watch(selectedClassProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: c.su,
          clipBehavior: Clip.antiAlias,
          shape: StadiumBorder(side: BorderSide(color: c.si)),
          child: InkWell(
            onTap: () => showClassPicker(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(left: 18, right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kelas $cls',
                      style: context.styleBold.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showClassPicker(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    barrierColor: const Color(0x8016171A),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
    builder: (_) => const _ClassPickerSheet(),
  );
}

class _ClassPickerSheet extends ConsumerWidget {
  const _ClassPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedClassProvider);
    final classes = ref.watch(myClassesProvider);
    final summaries = ref.watch(classSummaryMapProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pilih Kelas', style: context.styleH2),
          const SizedBox(height: 8),
          RowList(
            children: [
              for (final code in classes)
                _ClassPickerRow(
                  code: code,
                  info: summaries[code],
                  selected: code == selected,
                  onTap: () {
                    ref.read(selectedClassProvider.notifier).select(code);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassPickerRow extends StatelessWidget {
  const _ClassPickerRow({
    required this.code,
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final ClassInfo? info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text('Kelas $code', style: context.styleBold)),
              if (info != null)
                Text(
                  '${info!.studentCount} siswa · ${info!.attendancePercent}% hadir',
                  style: context.styleCaption,
                ),
              SizedBox(
                width: 28,
                child: selected
                    ? Icon(Icons.check, size: 18, color: context.colors.ink)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
