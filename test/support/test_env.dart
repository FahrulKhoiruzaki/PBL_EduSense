import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _arial = '/System/Library/Fonts/Supplemental/Arial.ttf';

Future<void> prepareFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final file = File(_arial);
  if (!file.existsSync()) return;
  final bytes = ByteData.sublistView(file.readAsBytesSync());
  for (final family in ['Inter_regular', 'Inter_500', 'Inter_600', 'Inter_700']) {
    final loader = FontLoader(family)..addFont(Future.value(bytes));
    await loader.load();
  }
}

List<FlutterErrorDetails> captureErrors() {
  final errors = <FlutterErrorDetails>[];
  setUp(() {
    errors.clear();
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('google_fonts')) errors.add(d);
    };
    addTearDown(() => FlutterError.onError = original);
  });
  return errors;
}
