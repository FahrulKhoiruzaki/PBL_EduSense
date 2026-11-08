import 'package:flutter/material.dart';

import '../core/theme.dart';

enum ButtonVariant { primary, secondary, outline, danger }

class CustomButton extends StatefulWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
    this.expanded = false,
    this.onDark = false,
    this.surfaceFill = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final IconData? icon;
  final bool expanded;
  final bool onDark;
  final bool surfaceFill;
  final bool compact;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;

    final (Color? background, Color foreground, Color? border) =
        switch (widget.variant) {
      ButtonVariant.primary => widget.onDark
          ? (AppColors.onDarkCard, AppColors.darkCardEnd, null)
          : (c.ink, c.su, null),
      ButtonVariant.secondary => (c.mi, c.ink, null),
      ButtonVariant.outline => widget.onDark
          ? (null, AppColors.onDarkCard, const Color(0xFF6B6E75))
          : (widget.surfaceFill ? c.su : null, c.ink, c.si),
      ButtonVariant.danger => (c.danger, Colors.white, null),
    };

    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: context.styleBold.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: widget.compact ? 13 : null,
        color: foreground,
      ),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: foreground),
          const SizedBox(width: 6),
        ],
        Flexible(child: label),
      ],
    );

    final button = AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: background ?? Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: widget.compact ? 36 : 44),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 16),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: widget.expanded
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }
}
