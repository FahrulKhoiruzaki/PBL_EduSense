import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.size = 36,
    this.fontSize = 12,
    this.onTap,
  });

  final String name;
  final double size;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.mi, shape: BoxShape.circle),
      child: Text(
        initials(name),
        style: context.styleBadge.copyWith(fontSize: fontSize, color: c.ink),
      ),
    );

    if (onTap == null) return circle;
    return Semantics(
      button: true,
      label: 'Profil $name',
      child: GestureDetector(onTap: onTap, child: circle),
    );
  }
}
