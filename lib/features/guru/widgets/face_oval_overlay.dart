import 'dart:math' as math;

import 'package:flutter/material.dart';

Rect faceOvalRect(Size size) {
  const ratio = 160 / 210;
  var height = math.min(size.width * 0.62 / ratio, size.height * 0.5);
  height = math.min(height, 360);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.4),
    width: height * ratio,
    height: height,
  );
}

class FaceOvalOverlayPainter extends CustomPainter {
  const FaceOvalOverlayPainter({
    this.dimColor = const Color(0xA3000000),
    this.borderColor = const Color(0xD9FFFFFF),
    this.borderWidth = 2,
    this.scanProgress,
    super.repaint,
  });

  final Color dimColor;
  final Color borderColor;
  final double borderWidth;
  final double? scanProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = faceOvalRect(size);
    final hole = Path()..addOval(oval);
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );
    canvas.drawPath(mask, Paint()..color = dimColor);

    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = scanProgress == null ? borderWidth : borderWidth + 1
        ..color = scanProgress == null ? borderColor : Colors.white,
    );

    final progress = scanProgress;
    if (progress != null) {
      canvas.save();
      canvas.clipPath(hole);
      final y = oval.top + oval.height * (0.1 + 0.8 * progress);
      final left = oval.left + oval.width * 0.04;
      final right = oval.right - oval.width * 0.04;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 6),
      );
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FaceOvalOverlayPainter old) =>
      old.dimColor != dimColor ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.scanProgress != scanProgress;
}

class FaceOvalOverlay extends StatefulWidget {
  const FaceOvalOverlay({super.key, this.scanning = false});

  final bool scanning;

  @override
  State<FaceOvalOverlay> createState() => _FaceOvalOverlayState();
}

class _FaceOvalOverlayState extends State<FaceOvalOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 0.5,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FaceOvalOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.scanning && !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: FaceOvalOverlayPainter(
            scanProgress:
                widget.scanning ? Curves.easeInOut.transform(_controller.value) : null,
          ),
        ),
      ),
    );
  }
}
