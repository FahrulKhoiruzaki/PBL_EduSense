import '../../../core/user_facing_error.dart';

/// Galat validasi lokal formulir akademik; ditangkap formulir sama seperti galat server.
class AcademicFormError implements UserFacingError {
  AcademicFormError(String field, String fieldMessage)
      : fieldErrors = {field: fieldMessage},
        message = 'Periksa kembali isian formulir.';

  @override
  final String message;

  @override
  final Map<String, String> fieldErrors;
}

/// Angka 0–100 dengan desimal opsional ("72,5" atau "72.5"). Kosong = null bila [optional].
double? parseScore(String raw, {required String field, bool optional = false}) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) {
    if (optional) return null;
    throw AcademicFormError(field, 'Kolom ini wajib diisi.');
  }
  final value = double.tryParse(text);
  if (value == null || value < 0 || value > 100) {
    throw AcademicFormError(field, 'Masukkan angka 0–100.');
  }
  return value;
}

String scoreText(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}
