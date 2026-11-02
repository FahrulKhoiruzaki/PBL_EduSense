import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/app_models.dart';

extension AttendanceStatusIcon on AttendanceStatus {
  IconData get icon => switch (this) {
        AttendanceStatus.hadir => Icons.check,
        AttendanceStatus.terlambat => Icons.schedule,
        AttendanceStatus.izin => Icons.mail_outline,
        AttendanceStatus.sakit => Icons.add,
        AttendanceStatus.alpa => Icons.close,
      };
}

extension ClassificationIcon on Classification {
  IconData get icon => switch (this) {
        Classification.mahir => Icons.check,
        Classification.cukup => Icons.circle,
        Classification.perlu => Icons.flag,
      };
}

class StripePainter extends CustomPainter {
  const StripePainter({
    required this.base,
    required this.stripe,
    required this.period,
  });

  final Color base;
  final Color stripe;
  final double period;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = stripe
      ..strokeWidth = 1;
    final step = period * math.sqrt2;
    for (var x = (period - 0.5) * math.sqrt2;
        x < size.width + size.height;
        x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(StripePainter old) =>
      old.base != base || old.stripe != stripe || old.period != period;
}

enum BadgeVariant { plain, mahir, cukup, perlu }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = BadgeVariant.plain,
  });

  factory StatusBadge.attendance(AttendanceStatus status) =>
      StatusBadge(label: status.label, icon: status.icon);

  factory StatusBadge.classification(Classification classification) =>
      StatusBadge(
        label: classification.label,
        icon: classification.icon,
        variant: switch (classification) {
          Classification.mahir => BadgeVariant.mahir,
          Classification.cukup => BadgeVariant.cukup,
          Classification.perlu => BadgeVariant.perlu,
        },
      );

  final String label;
  final IconData? icon;
  final BadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = variant == BadgeVariant.mahir ? c.su : c.ink;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: context.styleBadge.copyWith(color: foreground)),
        ],
      ),
    );

    if (variant == BadgeVariant.perlu) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: CustomPaint(
          painter: StripePainter(base: c.mi, stripe: c.si, period: 5),
          child: content,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: variant == BadgeVariant.mahir ? c.ink : null,
        borderRadius: BorderRadius.circular(99),
        border: variant == BadgeVariant.mahir
            ? Border.all(color: Colors.transparent)
            : Border.all(color: variant == BadgeVariant.cukup ? c.ink : c.si),
      ),
      child: content,
    );
  }
}
