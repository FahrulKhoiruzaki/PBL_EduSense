import '../../../core/user_facing_error.dart';

enum ClassEntryKind {
  pembelajaran('Pembelajaran'),
  kegiatan('Kegiatan');

  const ClassEntryKind(this.label);
  final String label;

  static ClassEntryKind from(String? label) =>
      values.firstWhere((k) => k.label == label, orElse: () => ClassEntryKind.pembelajaran);
}

enum CalendarCategory {
  kegiatan('Kegiatan'),
  libur('Libur'),
  ujian('Ujian'),
  rapat('Rapat');

  const CalendarCategory(this.label);
  final String label;

  static CalendarCategory from(String? label) =>
      values.firstWhere((c) => c.label == label, orElse: () => CalendarCategory.kegiatan);
}

const kClassLevels = [1, 2, 3, 4, 5, 6];

class ClassEntry {
  const ClassEntry({
    required this.id,
    required this.level,
    required this.kind,
    required this.title,
    required this.description,
    required this.order,
    required this.visible,
  });

  final int id;
  final int level;
  final ClassEntryKind kind;
  final String title;
  final String description;
  final int order;
  final bool visible;
}

/// Isian formulir sebelum disimpan; `order` kosong berarti "taruh paling akhir".
class ClassEntryDraft {
  const ClassEntryDraft({
    required this.level,
    required this.kind,
    required this.title,
    this.description = '',
    this.order,
    this.visible = true,
  });

  final int level;
  final ClassEntryKind kind;
  final String title;
  final String description;
  final int? order;
  final bool visible;
}

class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.start,
    required this.visible,
    this.end,
  });

  final int id;
  final String title;
  final String description;
  final CalendarCategory category;
  final DateTime start;
  final DateTime? end;
  final bool visible;
}

class CalendarEntryDraft {
  const CalendarEntryDraft({
    required this.title,
    required this.category,
    required this.start,
    this.description = '',
    this.end,
    this.visible = true,
  });

  final String title;
  final String description;
  final CalendarCategory category;

  /// Kosong berarti formulir belum diisi; use case menolaknya.
  final DateTime? start;
  final DateTime? end;
  final bool visible;
}

/// Kegagalan operasi informasi kelas/kalender: validasi domain atau penolakan dari sumber data.
class SchoolInfoFailure implements Exception, UserFacingError {
  const SchoolInfoFailure(this.message, {this.fieldErrors = const {}});

  @override
  final String message;

  @override
  final Map<String, String> fieldErrors;

  @override
  String toString() => 'SchoolInfoFailure($message, $fieldErrors)';
}
