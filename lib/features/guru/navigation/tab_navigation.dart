import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';

final tabNavigatorKeys = List.generate(
  3,
  (i) => GlobalKey<NavigatorState>(debugLabel: 'tab$i'),
);

void goTab(WidgetRef ref, int index, {bool resetStack = true}) {
  ref.read(activeTabProvider.notifier).select(index);
  if (!resetStack) return;
  for (final key in tabNavigatorKeys) {
    key.currentState?.popUntil((r) => r.isFirst);
  }
}
