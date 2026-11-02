import 'package:flutter/material.dart';

import '../core/theme.dart';

class CustomCard extends StatelessWidget {
  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.dark = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(14);

    final decoration = BoxDecoration(
      borderRadius: radius,
      color: dark ? null : c.su,
      gradient: dark
          ? const LinearGradient(
              begin: Alignment(-0.34, -0.94),
              end: Alignment(0.34, 0.94),
              colors: [AppColors.darkCardStart, AppColors.darkCardEnd],
            )
          : null,
      border: dark ? null : Border.all(color: c.mi),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F16171A),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
