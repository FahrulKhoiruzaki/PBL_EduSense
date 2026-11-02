import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'custom_button.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

abstract final class AppToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(String message) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _dismiss();
    final entry = OverlayEntry(builder: (_) => _ToastView(message: message));
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(milliseconds: 2200), _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 200),
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
              ),
              child: Material(
                color: c.ink,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    message,
                    style: context.styleMedium.copyWith(color: c.su),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const scrimColor = Color(0x8016171A);

Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    barrierColor: scrimColor,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    builder: (sheetContext) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}

Future<void> showConfirmDialog(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  required VoidCallback onConfirm,
  ButtonVariant confirmVariant = ButtonVariant.danger,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: scrimColor,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: dialogContext.styleH2),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: 'Batal',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: confirmLabel,
                    variant: confirmVariant,
                    expanded: true,
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onConfirm();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
