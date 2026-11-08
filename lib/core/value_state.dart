import 'package:flutter_riverpod/flutter_riverpod.dart';

class ValueState<T> extends Notifier<T> {
  ValueState(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}
