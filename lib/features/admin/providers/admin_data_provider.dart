import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../repositories/admin_repository.dart';
import '../data/admin_models.dart';

export '../../../repositories/admin_repository.dart' show Credentials;

class AdminDataNotifier extends AsyncNotifier<AdminDataset> {
  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  @override
  Future<AdminDataset> build() => ref.watch(adminRepositoryProvider).fetchDataset();

  Future<T> _run<T>(Future<T> Function() mutation) async {
    final result = await mutation();
    try {
      state = AsyncData(await _repo.fetchDataset());
    } on ApiException {
      // Perubahan sudah tersimpan di server; muat ulang gagal, jadi biarkan provider memuat lagi.
      ref.invalidateSelf();
    }
    return result;
  }

  Future<void> addClass(String code) => _run(() => _repo.createClass(code));

  Future<void> deleteClass(String code) => _run(() => _repo.deleteClass(code));

  Future<void> setWali(String code, String guruId) => _run(() => _repo.setWali(code, guruId));

  Future<void> addMapel(String code, String guruId) => _run(() => _repo.addMapel(code, guruId));

  Future<void> removeMapel(String code, String guruId) =>
      _run(() => _repo.removeMapel(code, guruId));

  Future<void> moveStudents(List<String> ids, String target) =>
      _run(() => _repo.moveStudents(ids, target));

  Future<Credentials> createGuru({
    required String name,
    required String email,
    required GuruRole role,
  }) => _run(() => _repo.createGuru(name: name, email: email, role: role));

  Future<Credentials> createAdmin({required String name, required String email}) =>
      _run(() => _repo.createAdmin(name: name, email: email));

  Future<Credentials> createSiswa({
    required String name,
    required String classCode,
    required String parent,
  }) => _run(() => _repo.createSiswa(name: name, classCode: classCode, parent: parent));

  Future<void> updateStaffAccount(
    AccountType type,
    String id, {
    required String name,
    required String email,
  }) => _run(() => _repo.updateStaffAccount(type, id, name: name, email: email));

  Future<void> updateSiswa(
    String id, {
    required String name,
    required String classCode,
    required String parent,
  }) => _run(() => _repo.updateSiswa(id, name: name, classCode: classCode, parent: parent));

  Future<Credentials> resetPassword(AccountType type, String id) =>
      _run(() => _repo.resetPassword(type, id));

  Future<void> setActive(AccountType type, String id, {required bool active}) =>
      _run(() => _repo.setActive(type, id, active: active));

  Future<void> deleteAccount(AccountType type, String id) =>
      _run(() => _repo.deleteAccount(type, id));

  Future<void> saveSettings({required String academicYear, required String lateLimit}) =>
      _run(() => _repo.saveSettings(academicYear: academicYear, lateLimit: lateLimit));

  Future<void> changeMyPassword({required String oldPassword, required String newPassword}) =>
      _repo.changeMyPassword(oldPassword: oldPassword, newPassword: newPassword);
}

final adminDataProvider = AsyncNotifierProvider<AdminDataNotifier, AdminDataset>(
  AdminDataNotifier.new,
);

final adminDatasetProvider = Provider<AdminDataset>(
  (ref) => ref.watch(adminDataProvider).value ?? AdminDataset.empty,
);

final adminProfileProvider = FutureProvider<AdminUser>(
  (ref) => ref.watch(adminRepositoryProvider).fetchMe(),
);
