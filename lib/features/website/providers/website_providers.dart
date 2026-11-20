import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/value_state.dart';
import '../../../repositories/website_repository.dart';
import '../data/website_models.dart';

final newsProvider = FutureProvider<List<Berita>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchNews(),
);

final newsDetailProvider = FutureProvider.autoDispose.family<Berita, String>(
  (ref, slug) => ref.watch(websiteRepositoryProvider).fetchNewsDetail(slug),
);

final activitiesProvider = FutureProvider<List<Kegiatan>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchActivities(),
);

final activityDetailProvider = FutureProvider.autoDispose.family<Kegiatan, String>(
  (ref, slug) => ref.watch(websiteRepositoryProvider).fetchActivityDetail(slug),
);

final facilitiesProvider = FutureProvider<List<Fasilitas>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchFacilities(),
);

final faqProvider = FutureProvider<List<Faq>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchFaq(),
);

final staffProvider = FutureProvider<List<StaffMember>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchStaff(),
);

final schoolInfoProvider = FutureProvider<SchoolInfo>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchSchoolInfo(),
);

final schoolInfoValueProvider = Provider<SchoolInfo>(
  (ref) => ref.watch(schoolInfoProvider).value ?? SchoolInfo.empty,
);

final classInfoProvider = FutureProvider<List<ClassLevelInfo>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchClassInfo(),
);

final calendarProvider = FutureProvider<List<CalendarEvent>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchCalendar(),
);

final sitePagesProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(websiteRepositoryProvider).fetchPages(),
);

final selectedProfilSectionProvider =
    NotifierProvider<ValueState<ProfilSection>, ProfilSection>(
  () => ValueState(ProfilSection.tentang),
);

final newsDetailSlugProvider =
    NotifierProvider<ValueState<String?>, String?>(() => ValueState(null));

final activityDetailSlugProvider =
    NotifierProvider<ValueState<String?>, String?>(() => ValueState(null));

final newsSearchQueryProvider =
    NotifierProvider<ValueState<String>, String>(() => ValueState(''));

final newsCategoryProvider =
    NotifierProvider<ValueState<BeritaKategori?>, BeritaKategori?>(
  () => ValueState(null),
);

final newsOrderProvider = NotifierProvider<ValueState<NewsOrder>, NewsOrder>(
  () => ValueState(NewsOrder.terbaru),
);

final faqSearchQueryProvider =
    NotifierProvider<ValueState<String>, String>(() => ValueState(''));

final faqCategoryProvider =
    NotifierProvider<ValueState<FaqKategori?>, FaqKategori?>(() => ValueState(null));

final activityCategoryProvider =
    NotifierProvider<ValueState<KegiatanKategori?>, KegiatanKategori?>(
  () => ValueState(null),
);

class WebsiteNavigator extends Notifier<WebsiteNav> {
  @override
  WebsiteNav build() => WebsiteNav.beranda;

  void _clearDetails() {
    ref.read(newsDetailSlugProvider.notifier).set(null);
    ref.read(activityDetailSlugProvider.notifier).set(null);
  }

  void open(WebsiteNav nav) {
    _clearDetails();
    if (nav == WebsiteNav.profil) {
      ref.read(selectedProfilSectionProvider.notifier).set(ProfilSection.tentang);
    }
    state = nav;
  }

  void openProfil(ProfilSection section) {
    _clearDetails();
    ref.read(selectedProfilSectionProvider.notifier).set(section);
    state = WebsiteNav.profil;
  }

  void openNews(String slug) {
    ref.read(activityDetailSlugProvider.notifier).set(null);
    ref.read(newsDetailSlugProvider.notifier).set(slug);
    state = WebsiteNav.informasi;
  }

  void openActivity(String slug) {
    ref.read(newsDetailSlugProvider.notifier).set(null);
    ref.read(activityDetailSlugProvider.notifier).set(slug);
    state = WebsiteNav.kegiatan;
  }

  void closeDetail() => _clearDetails();

  bool back() {
    if (ref.read(newsDetailSlugProvider) != null ||
        ref.read(activityDetailSlugProvider) != null) {
      closeDetail();
      return true;
    }
    if (state != WebsiteNav.beranda) {
      open(WebsiteNav.beranda);
      return true;
    }
    return false;
  }
}

final activeNavProvider =
    NotifierProvider<WebsiteNavigator, WebsiteNav>(WebsiteNavigator.new);

final canGoBackProvider =
    Provider<bool>((ref) => ref.watch(activeNavProvider) != WebsiteNav.beranda);

void resetNewsFilters(WidgetRef ref) {
  ref.invalidate(newsSearchQueryProvider);
  ref.invalidate(newsCategoryProvider);
}

final filteredNewsProvider = Provider.autoDispose<List<Berita>>((ref) {
  final query = ref.watch(newsSearchQueryProvider).toLowerCase();
  final category = ref.watch(newsCategoryProvider);
  final order = ref.watch(newsOrderProvider);
  final all = ref.watch(newsProvider).value ?? const <Berita>[];

  return [
    for (final b in all)
      if ((category == null || b.kategori == category) && b.judul.toLowerCase().contains(query))
        b,
  ]..sort((a, b) => order == NewsOrder.terbaru
      ? b.tanggal.compareTo(a.tanggal)
      : a.tanggal.compareTo(b.tanggal));
});

final filteredFaqProvider = Provider.autoDispose<List<Faq>>((ref) {
  final query = ref.watch(faqSearchQueryProvider).toLowerCase();
  final category = ref.watch(faqCategoryProvider);
  final all = ref.watch(faqProvider).value ?? const <Faq>[];
  return [
    for (final f in all)
      if ((category == null || f.kategori == category) &&
          f.pertanyaan.toLowerCase().contains(query))
        f,
  ];
});

final filteredActivitiesProvider = Provider.autoDispose<List<Kegiatan>>((ref) {
  final category = ref.watch(activityCategoryProvider);
  final all = ref.watch(activitiesProvider).value ?? const <Kegiatan>[];
  return [
    for (final k in all)
      if (category == null || k.kategori == category) k,
  ];
});

/// Admin dan website hidup dalam satu aplikasi; setelah admin mengubah konten, data publik yang
/// sudah tersimpan di memori harus dimuat ulang agar perubahan langsung terlihat.
void invalidateWebsiteData(Ref ref) {
  ref
    ..invalidate(newsProvider)
    ..invalidate(activitiesProvider)
    ..invalidate(facilitiesProvider)
    ..invalidate(faqProvider)
    ..invalidate(staffProvider)
    ..invalidate(schoolInfoProvider)
    ..invalidate(sitePagesProvider)
    ..invalidate(classInfoProvider)
    ..invalidate(calendarProvider);
}
