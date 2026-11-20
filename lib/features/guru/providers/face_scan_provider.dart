import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';

typedef FaceScanner = Future<FaceScanResult> Function(String classCode, Uint8List image);

/// Mengirim foto ke `POST /guru/classes/{kode}/attendance/face`. Data kelas dimuat ulang
/// otomatis bila wajah cocok, sehingga daftar absensi langsung ikut berubah.
final faceScannerProvider = Provider<FaceScanner>((ref) {
  return (classCode, image) =>
      ref.read(classDataAsyncProvider(classCode).notifier).scanFace(image);
});
