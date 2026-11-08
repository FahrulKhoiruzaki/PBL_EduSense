import 'package:flutter/material.dart';

import '../core/theme.dart';

class SidebarLogo extends StatelessWidget {
  const SidebarLogo({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment(-0.34, -0.94),
              end: Alignment(0.34, 0.94),
              colors: [AppColors.darkCardStart, AppColors.darkCardEnd],
            ),
          ),
          child: Text(
            '02',
            style: context.styleBadge.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.onDarkCard,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.styleBold),
              if (subtitle != null) Text(subtitle!, style: context.styleCaption),
            ],
          ),
        ),
      ],
    );
  }
}

class SidebarItem extends StatelessWidget {
  const SidebarItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: context.styleMedium.copyWith(color: selected ? c.su : c.sl),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SidebarPanel extends StatelessWidget {
  const SidebarPanel({super.key, required this.logo, required this.top, required this.bottom});

  final Widget logo;
  final List<Widget> top;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.su,
        border: Border(right: BorderSide(color: c.mi)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), child: logo),
            ...top,
            const Spacer(),
            ...bottom,
          ],
        ),
      ),
    );
  }
}
