import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../features/admin/data/school_info_models.dart';

/// Kontrak sumber data. Domain hanya mengenal antarmuka ini, bukan HTTP/Dio.
abstract interface class ClassEntryRepository {
  Future<List<ClassEntry>> list();

  Future<ClassEntry> create(ClassEntryDraft draft);

  Future<ClassEntry> update(int id, ClassEntryDraft draft);

  Future<void> delete(int id);
}

abstract interface class CalendarRepository {
  Future<List<CalendarEntry>> list();

  Future<CalendarEntry> create(CalendarEntryDraft draft);

  Future<CalendarEntry> update(int id, CalendarEntryDraft draft);

  Future<void> delete(int id);
}

/// Endpoint `app/api/routers/admin_school_info.py` (prefix `/admin/cms`).
abstract final class SchoolInfoPaths {
  static const classEntries = '/admin/cms/kelas';
  static const calendar = '/admin/cms/kalender';

  static String classEntry(int id) => '$classEntries/$id';
  static String calendarEntry(int id) => '$calendar/$id';
}

/// Menerjemahkan galat jaringan/server ke kegagalan domain, supaya lapisan atas
/// tidak mengenal Dio. Pesan dan galat per kolom dari server tetap diteruskan.
Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ApiException catch (e) {
    throw SchoolInfoFailure(e.message, fieldErrors: e.fieldErrors);
  }
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

class ApiClassEntryRepository implements ClassEntryRepository {
  const ApiClassEntryRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ClassEntry>> list() => _guard(
    () async => [
      for (final r in await _api.getList(SchoolInfoPaths.classEntries))
        _entry(r),
    ],
  );

  @override
  Future<ClassEntry> create(ClassEntryDraft draft) => _guard(
    () async => _entry(
      await _api.postObject(SchoolInfoPaths.classEntries, body: _body(draft)),
    ),
  );

  @override
  Future<ClassEntry> update(int id, ClassEntryDraft draft) => _guard(
    () async => _entry(
      await _api.putObject(SchoolInfoPaths.classEntry(id), body: _body(draft)),
    ),
  );

  @override
  Future<void> delete(int id) => _guard(() async {
    await _api.delete(SchoolInfoPaths.classEntry(id));
  });

  ClassEntry _entry(JsonMap r) => ClassEntry(
    id: (r['id'] as num).toInt(),
    level: (r['tingkat'] as num).toInt(),
    kind: ClassEntryKind.from(r['jenis'] as String?),
    title: r['judul'] as String,
    description: r['deskripsi'] as String? ?? '',
    order: (r['urutan'] as num).toInt(),
    visible: r['tampil'] as bool? ?? true,
  );

  /// `urutan` kosong tidak dikirim: server menaruh entri di akhir daftar.
  Map<String, dynamic> _body(ClassEntryDraft d) => {
    'tingkat': d.level,
    'jenis': d.kind.label,
    'judul': d.title,
    'deskripsi': d.description,
    'tampil': d.visible,
    if (d.order != null) 'urutan': d.order,
  };
}

class ApiCalendarRepository implements CalendarRepository {
  const ApiCalendarRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<CalendarEntry>> list() => _guard(
    () async => [
      for (final r in await _api.getList(SchoolInfoPaths.calendar)) _entry(r),
    ],
  );

  @override
  Future<CalendarEntry> create(CalendarEntryDraft draft) => _guard(
    () async => _entry(
      await _api.postObject(SchoolInfoPaths.calendar, body: _body(draft)),
    ),
  );

  @override
  Future<CalendarEntry> update(int id, CalendarEntryDraft draft) => _guard(
    () async => _entry(
      await _api.putObject(
        SchoolInfoPaths.calendarEntry(id),
        body: _body(draft),
      ),
    ),
  );

  @override
  Future<void> delete(int id) => _guard(() async {
    await _api.delete(SchoolInfoPaths.calendarEntry(id));
  });

  CalendarEntry _entry(JsonMap r) => CalendarEntry(
    id: (r['id'] as num).toInt(),
    title: r['judul'] as String,
    description: r['deskripsi'] as String? ?? '',
    category: CalendarCategory.from(r['kategori'] as String?),
    start: _date(r['tanggal_mulai'])!,
    end: _date(r['tanggal_selesai']),
    visible: r['tampil'] as bool? ?? true,
  );

  /// `start` sudah dipastikan terisi oleh [SaveCalendarEntry] sebelum sampai sini.
  Map<String, dynamic> _body(CalendarEntryDraft d) => {
    'judul': d.title,
    'deskripsi': d.description,
    'kategori': d.category.label,
    'tanggal_mulai': isoDate(d.start!),
    'tanggal_selesai': d.end == null ? null : isoDate(d.end!),
    'tampil': d.visible,
  };
}

// Penyambungan (DI): satu-satunya tempat implementasi data dipilih.
// Tes cukup mengganti provider ini dengan repository palsu.

final classEntryRepositoryProvider = Provider<ClassEntryRepository>(
  (ref) => ApiClassEntryRepository(ref.watch(apiClientProvider)),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => ApiCalendarRepository(ref.watch(apiClientProvider)),
);
