import '../../../repositories/school_info_repository.dart';
import '../data/school_info_models.dart';

const _required = 'Kolom ini wajib diisi.';
const _titleMax = 150;
const _descriptionMax = 5000;

SchoolInfoFailure _invalid(Map<String, String> errors) =>
    SchoolInfoFailure('Data yang dikirim tidak valid.', fieldErrors: errors);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// Informasi kelas

class ListClassEntries {
  const ListClassEntries(this._repository);

  final ClassEntryRepository _repository;

  /// Urut per kelas, lalu jenis, lalu urutan tampil.
  Future<List<ClassEntry>> call() async {
    final items = [...await _repository.list()];
    items.sort((a, b) {
      final byLevel = a.level.compareTo(b.level);
      if (byLevel != 0) return byLevel;
      final byKind = a.kind.index.compareTo(b.kind.index);
      if (byKind != 0) return byKind;
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return items;
  }
}

class SaveClassEntry {
  const SaveClassEntry(this._repository);

  final ClassEntryRepository _repository;

  /// Membuat entri baru, atau memperbarui bila [id] diberikan.
  Future<ClassEntry> call({int? id, required ClassEntryDraft draft}) {
    final clean = ClassEntryDraft(
      level: draft.level,
      kind: draft.kind,
      title: draft.title.trim(),
      description: draft.description.trim(),
      order: draft.order,
      visible: draft.visible,
    );
    final errors = <String, String>{
      if (!kClassLevels.contains(clean.level)) 'tingkat': 'Pilih kelas 1 sampai 6.',
      if (clean.title.isEmpty)
        'judul': _required
      else if (clean.title.length > _titleMax)
        'judul': 'Maksimal $_titleMax karakter.',
      if (clean.description.length > _descriptionMax)
        'deskripsi': 'Maksimal $_descriptionMax karakter.',
      if (clean.order != null && clean.order! < 0) 'urutan': 'Urutan tidak boleh negatif.',
    };
    if (errors.isNotEmpty) return Future.error(_invalid(errors));
    return id == null ? _repository.create(clean) : _repository.update(id, clean);
  }
}

class DeleteClassEntry {
  const DeleteClassEntry(this._repository);

  final ClassEntryRepository _repository;

  Future<void> call(int id) => _repository.delete(id);
}

// Kalender akademik

class ListCalendar {
  const ListCalendar(this._repository);

  final CalendarRepository _repository;

  /// Urut dari tanggal mulai paling awal.
  Future<List<CalendarEntry>> call() async {
    final items = [...await _repository.list()];
    items.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return items;
  }
}

class SaveCalendarEntry {
  const SaveCalendarEntry(this._repository);

  final CalendarRepository _repository;

  Future<CalendarEntry> call({int? id, required CalendarEntryDraft draft}) {
    final title = draft.title.trim();
    final start = draft.start == null ? null : _dateOnly(draft.start!);
    // Kegiatan satu hari tidak perlu tanggal selesai.
    var end = draft.end == null ? null : _dateOnly(draft.end!);
    if (end != null && start != null && end == start) end = null;

    final errors = <String, String>{
      if (title.isEmpty)
        'judul': _required
      else if (title.length > _titleMax)
        'judul': 'Maksimal $_titleMax karakter.',
      if (start == null) 'tanggal_mulai': _required,
      if (end != null && start != null && end.isBefore(start))
        'tanggal_selesai': 'Tanggal selesai tidak boleh sebelum tanggal mulai.',
    };
    if (errors.isNotEmpty) return Future.error(_invalid(errors));

    final clean = CalendarEntryDraft(
      title: title,
      description: draft.description.trim(),
      category: draft.category,
      start: start,
      end: end,
      visible: draft.visible,
    );
    return id == null ? _repository.create(clean) : _repository.update(id, clean);
  }
}

class DeleteCalendarEntry {
  const DeleteCalendarEntry(this._repository);

  final CalendarRepository _repository;

  Future<void> call(int id) => _repository.delete(id);
}
