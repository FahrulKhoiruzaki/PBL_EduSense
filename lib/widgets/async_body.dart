import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/theme.dart';
import 'common_widgets.dart';
import 'custom_button.dart';

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 4, this.height = 84});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
        children: [for (var i = 0; i < count; i++) SkeletonBlock(height: height)],
      );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Text(
              'Data belum dapat dimuat.',
              textAlign: TextAlign.center,
              style: context.styleBold,
            ),
            const SizedBox(height: 4),
            Text(describeError(error), textAlign: TextAlign.center, style: context.styleMuted),
            const SizedBox(height: 16),
            CustomButton(label: 'Coba Lagi', variant: ButtonVariant.secondary, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.loading,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      data: builder,
      loading: () => loading ?? const LoadingList(),
      error: (e, _) => ErrorRetry(error: e, onRetry: onRetry),
    );
  }
}
