import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/school_info_repository.dart';
import '../../website/providers/website_providers.dart';
import '../actions/school_info_actions.dart';
import '../data/school_info_models.dart';

class ClassEntriesNotifier extends AsyncNotifier<List<ClassEntry>> {
  ClassEntryRepository get _repo => ref.read(classEntryRepositoryProvider);

  @override
  Future<List<ClassEntry>> build() => ListClassEntries(ref.watch(classEntryRepositoryProvider))();

  Future<void> save({int? id, required ClassEntryDraft draft}) async {
    await SaveClassEntry(_repo)(id: id, draft: draft);
    invalidateWebsiteData(ref);
    await _reload();
  }

  Future<void> delete(int id) async {
    await DeleteClassEntry(_repo)(id);
    invalidateWebsiteData(ref);
    await _reload();
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(await ListClassEntries(_repo)());
    } on SchoolInfoFailure {
      // Perubahan sudah tersimpan; muat ulang gagal, jadi biarkan provider memuat lagi.
      ref.invalidateSelf();
    }
  }
}

class CalendarNotifier extends AsyncNotifier<List<CalendarEntry>> {
  CalendarRepository get _repo => ref.read(calendarRepositoryProvider);

  @override
  Future<List<CalendarEntry>> build() => ListCalendar(ref.watch(calendarRepositoryProvider))();

  Future<void> save({int? id, required CalendarEntryDraft draft}) async {
    await SaveCalendarEntry(_repo)(id: id, draft: draft);
    invalidateWebsiteData(ref);
    await _reload();
  }

  Future<void> delete(int id) async {
    await DeleteCalendarEntry(_repo)(id);
    invalidateWebsiteData(ref);
    await _reload();
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(await ListCalendar(_repo)());
    } on SchoolInfoFailure {
      ref.invalidateSelf();
    }
  }
}

final classEntriesProvider = AsyncNotifierProvider<ClassEntriesNotifier, List<ClassEntry>>(
  ClassEntriesNotifier.new,
);

final calendarEntriesProvider = AsyncNotifierProvider<CalendarNotifier, List<CalendarEntry>>(
  CalendarNotifier.new,
);
