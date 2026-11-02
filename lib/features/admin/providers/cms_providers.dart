import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../repositories/admin_repository.dart';
import '../../website/providers/website_providers.dart';
import '../data/cms_models.dart';

abstract class _CmsListNotifier<T> extends AsyncNotifier<List<T>> {
  Future<List<T>> load(AdminRepository repo);

  @override
  Future<List<T>> build() => load(ref.watch(adminRepositoryProvider));

  /// Menjalankan perubahan lalu memuat ulang daftar dari server.
  Future<R> mutate<R>(Future<R> Function(AdminRepository repo) action) async {
    final repo = ref.read(adminRepositoryProvider);
    final result = await action(repo);
    invalidateWebsiteData(ref);
    try {
      state = AsyncData(await load(repo));
    } on ApiException {
      // Perubahan sudah tersimpan di server; muat ulang gagal, jadi biarkan provider memuat lagi.
      ref.invalidateSelf();
    }
    return result;
  }
}

class CmsPagesNotifier extends AsyncNotifier<List<CmsPage>> {
  @override
  Future<List<CmsPage>> build() => ref.watch(adminRepositoryProvider).fetchPages();

  Future<void> save(Map<String, String> changed) async {
    state = AsyncData(await ref.read(adminRepositoryProvider).savePages(changed));
    invalidateWebsiteData(ref);
  }
}

class CmsSchoolNotifier extends AsyncNotifier<CmsSchool> {
  @override
  Future<CmsSchool> build() => ref.watch(adminRepositoryProvider).fetchSchool();

  Future<CmsSchool> save(CmsSchool school) async {
    final saved = await ref.read(adminRepositoryProvider).saveSchool(school);
    state = AsyncData(saved);
    invalidateWebsiteData(ref);
    return saved;
  }

  /// Mengunggah foto beranda. Bila gagal, galat dilempar dan foto yang tampil tidak berubah.
  Future<void> replacePhoto(PickedImage image) async {
    final url = await ref
        .read(adminRepositoryProvider)
        .replaceSchoolPhoto(filename: image.name, bytes: image.bytes);
    final current = state.value;
    if (current != null) state = AsyncData(current.withPhoto(url));
    invalidateWebsiteData(ref);
  }
}

class CmsPostsNotifier extends _CmsListNotifier<CmsPostSummary> {
  @override
  Future<List<CmsPostSummary>> load(AdminRepository repo) => repo.fetchPosts();

  Future<void> create(CmsPostInput input) => mutate((r) => r.createPost(input));

  Future<void> edit(String slug, CmsPostInput input) => mutate((r) => r.updatePost(slug, input));

  Future<void> delete(String slug) => mutate((r) => r.deletePost(slug));
}

class CmsActivitiesNotifier extends _CmsListNotifier<CmsActivity> {
  @override
  Future<List<CmsActivity>> load(AdminRepository repo) => repo.fetchActivities();

  Future<void> create(CmsActivityInput input) => mutate((r) => r.createActivity(input));

  Future<void> edit(String slug, CmsActivityInput input) =>
      mutate((r) => r.updateActivity(slug, input));

  Future<void> delete(String slug) => mutate((r) => r.deleteActivity(slug));
}

class CmsFacilitiesNotifier extends _CmsListNotifier<CmsFacility> {
  @override
  Future<List<CmsFacility>> load(AdminRepository repo) => repo.fetchFacilities();

  Future<void> create(CmsFacilityInput input) => mutate((r) => r.createFacility(input));

  Future<void> edit(int id, CmsFacilityInput input) => mutate((r) => r.updateFacility(id, input));

  Future<void> delete(int id) => mutate((r) => r.deleteFacility(id));
}

class CmsFaqNotifier extends _CmsListNotifier<CmsFaq> {
  @override
  Future<List<CmsFaq>> load(AdminRepository repo) => repo.fetchFaqs();

  Future<void> create(CmsFaqInput input) => mutate((r) => r.createFaq(input));

  Future<void> edit(int id, CmsFaqInput input) => mutate((r) => r.updateFaq(id, input));

  Future<void> delete(int id) => mutate((r) => r.deleteFaq(id));
}

final cmsPagesProvider = AsyncNotifierProvider<CmsPagesNotifier, List<CmsPage>>(
  CmsPagesNotifier.new,
);

final cmsSchoolProvider = AsyncNotifierProvider<CmsSchoolNotifier, CmsSchool>(
  CmsSchoolNotifier.new,
);

final cmsPostsProvider = AsyncNotifierProvider<CmsPostsNotifier, List<CmsPostSummary>>(
  CmsPostsNotifier.new,
);

final cmsActivitiesProvider = AsyncNotifierProvider<CmsActivitiesNotifier, List<CmsActivity>>(
  CmsActivitiesNotifier.new,
);

final cmsFacilitiesProvider = AsyncNotifierProvider<CmsFacilitiesNotifier, List<CmsFacility>>(
  CmsFacilitiesNotifier.new,
);

final cmsFaqProvider = AsyncNotifierProvider<CmsFaqNotifier, List<CmsFaq>>(CmsFaqNotifier.new);
