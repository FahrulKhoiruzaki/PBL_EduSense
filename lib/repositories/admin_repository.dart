import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/network/api_client.dart';
import '../features/admin/data/admin_models.dart';
import '../features/admin/data/cms_models.dart';

typedef Credentials = ({String email, String password});

abstract interface class AdminRepository {
  Future<AdminUser> fetchMe();

  Future<AdminDataset> fetchDataset();

  Future<void> createClass(String code);

  Future<void> deleteClass(String code);

  Future<void> setWali(String code, String guruId);

  Future<void> addMapel(String code, String guruId);

  Future<void> removeMapel(String code, String guruId);

  Future<void> moveStudents(List<String> studentIds, String targetClass);

  Future<Credentials> createGuru({
    required String name,
    required String email,
    required GuruRole role,
  });

  Future<Credentials> createAdmin({required String name, required String email});

  Future<Credentials> createSiswa({
    required String name,
    required String classCode,
    required String parent,
  });

  Future<void> updateStaffAccount(
    AccountType type,
    String id, {
    required String name,
    required String email,
  });

  Future<void> updateSiswa(
    String id, {
    required String name,
    required String classCode,
    required String parent,
  });

  Future<Credentials> resetPassword(AccountType type, String id);

  Future<void> setActive(AccountType type, String id, {required bool active});

  Future<void> deleteAccount(AccountType type, String id);

  Future<void> changeMyPassword({required String oldPassword, required String newPassword});

  Future<void> saveSettings({required String academicYear, required String lateLimit});

  // Kelola Website (CMS)

  Future<List<CmsPage>> fetchPages();

  /// Hanya mengirim teks yang berubah; mengembalikan daftar lengkap terbaru dari server.
  Future<List<CmsPage>> savePages(Map<String, String> changed);

  Future<CmsSchool> fetchSchool();

  Future<CmsSchool> saveSchool(CmsSchool school);

  /// Mengganti foto beranda; mengembalikan alamat relatifnya (`/media/<nama>`).
  Future<String> replaceSchoolPhoto({required String filename, required Uint8List bytes});

  Future<List<CmsPostSummary>> fetchPosts();

  Future<CmsPost> fetchPost(String slug);

  Future<CmsPost> createPost(CmsPostInput input);

  Future<CmsPost> updatePost(String slug, CmsPostInput input);

  Future<void> deletePost(String slug);

  Future<List<CmsActivity>> fetchActivities();

  Future<CmsActivity> createActivity(CmsActivityInput input);

  Future<CmsActivity> updateActivity(String slug, CmsActivityInput input);

  Future<void> deleteActivity(String slug);

  Future<List<CmsFacility>> fetchFacilities();

  Future<CmsFacility> createFacility(CmsFacilityInput input);

  Future<CmsFacility> updateFacility(int id, CmsFacilityInput input);

  Future<void> deleteFacility(int id);

  Future<List<CmsFaq>> fetchFaqs();

  Future<CmsFaq> createFaq(CmsFaqInput input);

  Future<CmsFaq> updateFaq(int id, CmsFaqInput input);

  Future<void> deleteFaq(int id);

  /// Mengunggah gambar dan mengembalikan alamat relatifnya (`/media/<nama>`).
  Future<String> uploadMedia({required String filename, required Uint8List bytes});
}

abstract final class CmsPaths {
  static const pages = '/admin/cms/pages';
  static const school = '/admin/cms/school';
  static const schoolPhoto = '/admin/cms/school/photo';
  static const posts = '/admin/cms/posts';
  static const activities = '/admin/cms/kegiatan';
  static const facilities = '/admin/cms/fasilitas';
  static const faq = '/admin/cms/faq';
  static const media = '/admin/cms/media';

  static String post(String slug) => '$posts/$slug';
  static String activity(String slug) => '$activities/$slug';
  static String facility(int id) => '$facilities/$id';
  static String faqItem(int id) => '$faq/$id';
}

abstract final class AdminPaths {
  static const me = '/admin/me';
  static const guru = '/admin/guru';
  static const siswa = '/admin/siswa';
  static const admins = '/admin/admins';
  static const classes = '/admin/classes';
  static const logs = '/admin/logs';
  static const settings = '/admin/settings';
  static const password = '/admin/me/password';
  static const moveStudents = '/admin/siswa/move';

  static String classDetail(String code) => '/admin/classes/$code';
  static String classWali(String code) => '/admin/classes/$code/wali';
  static String classMapel(String code) => '/admin/classes/$code/mapel';
  static String classMapelGuru(String code, String guruId) => '/admin/classes/$code/mapel/$guruId';

  static String account(AccountType type, String id) => '${_base(type)}/$id';
  static String accountReset(AccountType type, String id) => '${_base(type)}/$id/reset-password';
  static String accountActive(AccountType type, String id) => '${_base(type)}/$id/active';

  static String _base(AccountType type) => switch (type) {
    AccountType.guru => guru,
    AccountType.siswa => siswa,
    AccountType.adm => admins,
  };
}

class ApiAdminRepository implements AdminRepository {
  const ApiAdminRepository(this._api);

  final ApiClient _api;

  @override
  Future<AdminUser> fetchMe() async {
    final json = await _api.getObject(AdminPaths.me);
    return AdminUser(
      id: '${json['id']}',
      name: json['nama'] as String,
      email: json['email'] as String,
    );
  }

  @override
  Future<AdminDataset> fetchDataset() async {
    final results = await Future.wait([
      _api.getList(AdminPaths.guru),
      _api.getList(AdminPaths.siswa),
      _api.getList(AdminPaths.admins),
      _api.getList(AdminPaths.classes),
      _api.getList(AdminPaths.logs, query: {'limit': 500}),
      _api.getObject(AdminPaths.settings),
    ]);
    final settings = results[5] as JsonMap;

    return AdminDataset(
      guru: [for (final r in results[0] as List<JsonMap>) _guru(r)],
      siswa: [for (final r in results[1] as List<JsonMap>) _siswa(r)],
      admins: [for (final r in results[2] as List<JsonMap>) _admin(r)],
      classes: {
        for (final r in results[3] as List<JsonMap>)
          r['kode'] as String: Kelas(
            code: r['kode'] as String,
            waliId: r['wali_id'] == null ? null : '${r['wali_id']}',
            mapelIds: [for (final id in (r['mapel_ids'] as List<dynamic>? ?? const [])) '$id'],
          ),
      },
      log: [
        for (final r in results[4] as List<JsonMap>)
          LogAktivitas(
            time: DateTime.parse(r['waktu'] as String).toLocal(),
            type: LogType.values.firstWhere(
              (t) => t.label == r['jenis'],
              orElse: () => LogType.sistem,
            ),
            message: r['pesan'] as String,
          ),
      ]..sort((a, b) => b.time.compareTo(a.time)),
      academicYear: settings['tahun_ajaran'] as String? ?? '',
      lateLimit: settings['batas_jam_terlambat'] as String? ?? '',
    );
  }

  @override
  Future<void> createClass(String code) async {
    await _api.post(AdminPaths.classes, body: {'kode': code});
  }

  @override
  Future<void> deleteClass(String code) async {
    await _api.delete(AdminPaths.classDetail(code));
  }

  @override
  Future<void> setWali(String code, String guruId) async {
    await _api.put(AdminPaths.classWali(code), body: {'guru_id': guruId});
  }

  @override
  Future<void> addMapel(String code, String guruId) async {
    await _api.post(AdminPaths.classMapel(code), body: {'guru_id': guruId});
  }

  @override
  Future<void> removeMapel(String code, String guruId) async {
    await _api.delete(AdminPaths.classMapelGuru(code, guruId));
  }

  @override
  Future<void> moveStudents(List<String> studentIds, String targetClass) async {
    await _api.post(
      AdminPaths.moveStudents,
      body: {'siswa_ids': studentIds, 'kelas_tujuan': targetClass},
    );
  }

  @override
  Future<Credentials> createGuru({
    required String name,
    required String email,
    required GuruRole role,
  }) async {
    final json = await _api.postObject(
      AdminPaths.guru,
      body: {'nama': name, 'email': email, 'peran': role.name},
    );
    return _credentials(json, email);
  }

  @override
  Future<Credentials> createAdmin({required String name, required String email}) async {
    final json = await _api.postObject(AdminPaths.admins, body: {'nama': name, 'email': email});
    return _credentials(json, email);
  }

  @override
  Future<Credentials> createSiswa({
    required String name,
    required String classCode,
    required String parent,
  }) async {
    final json = await _api.postObject(
      AdminPaths.siswa,
      body: {'nama': name, 'kelas': classCode, 'nama_orang_tua': parent},
    );
    return _credentials(json, json['email'] as String? ?? '');
  }

  @override
  Future<void> updateStaffAccount(
    AccountType type,
    String id, {
    required String name,
    required String email,
  }) async {
    await _api.put(AdminPaths.account(type, id), body: {'nama': name, 'email': email});
  }

  @override
  Future<void> updateSiswa(
    String id, {
    required String name,
    required String classCode,
    required String parent,
  }) async {
    await _api.put(
      AdminPaths.account(AccountType.siswa, id),
      body: {'nama': name, 'kelas': classCode, 'nama_orang_tua': parent},
    );
  }

  @override
  Future<Credentials> resetPassword(AccountType type, String id) async {
    final json = await _api.postObject(AdminPaths.accountReset(type, id));
    return _credentials(json, json['email'] as String? ?? '');
  }

  @override
  Future<void> setActive(AccountType type, String id, {required bool active}) async {
    await _api.put(AdminPaths.accountActive(type, id), body: {'aktif': active});
  }

  @override
  Future<void> deleteAccount(AccountType type, String id) async {
    await _api.delete(AdminPaths.account(type, id));
  }

  @override
  Future<void> changeMyPassword({required String oldPassword, required String newPassword}) async {
    await _api.put(
      AdminPaths.password,
      body: {'old_password': oldPassword, 'new_password': newPassword},
    );
  }

  @override
  Future<void> saveSettings({required String academicYear, required String lateLimit}) async {
    await _api.put(
      AdminPaths.settings,
      body: {
        'tahun_ajaran': academicYear,
        'batas_jam_terlambat': lateLimit.isEmpty ? null : lateLimit,
      },
    );
  }

  Credentials _credentials(JsonMap json, String fallbackEmail) => (
    email: json['email'] as String? ?? fallbackEmail,
    password: json['password_sementara'] as String,
  );

  // Kelola Website (CMS)

  @override
  Future<List<CmsPage>> fetchPages() async => _pages(await _api.getList(CmsPaths.pages));

  @override
  Future<List<CmsPage>> savePages(Map<String, String> changed) async =>
      _pages(_asList(await _api.put(CmsPaths.pages, body: {'halaman': changed})));

  @override
  Future<CmsSchool> fetchSchool() async => _school(await _api.getObject(CmsPaths.school));

  @override
  Future<CmsSchool> saveSchool(CmsSchool school) async => _school(
    await _api.putObject(
      CmsPaths.school,
      body: {
        'nama': school.nama,
        'kota': school.kota,
        'npsn': school.npsn,
        'alamat': school.alamat,
        'akreditasi': school.akreditasi,
        'telepon': school.telepon,
        'email': school.email,
        'media_sosial': school.mediaSosial,
        'whatsapp': school.whatsapp,
        'peta_url': school.petaUrl,
      },
    ),
  );

  @override
  Future<String> replaceSchoolPhoto({required String filename, required Uint8List bytes}) async {
    final json = await _api.postObject(
      CmsPaths.schoolPhoto,
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    return json['foto_url'] as String;
  }

  @override
  Future<List<CmsPostSummary>> fetchPosts() async => [
    for (final r in await _api.getList(CmsPaths.posts)) _post(r),
  ];

  @override
  Future<CmsPost> fetchPost(String slug) async => _post(await _api.getObject(CmsPaths.post(slug)));

  @override
  Future<CmsPost> createPost(CmsPostInput input) async =>
      _post(await _api.postObject(CmsPaths.posts, body: _postBody(input)));

  @override
  Future<CmsPost> updatePost(String slug, CmsPostInput input) async =>
      _post(await _api.putObject(CmsPaths.post(slug), body: _postBody(input)));

  @override
  Future<void> deletePost(String slug) async {
    await _api.delete(CmsPaths.post(slug));
  }

  @override
  Future<List<CmsActivity>> fetchActivities() async => [
    for (final r in await _api.getList(CmsPaths.activities)) _activity(r),
  ];

  @override
  Future<CmsActivity> createActivity(CmsActivityInput input) async =>
      _activity(await _api.postObject(CmsPaths.activities, body: _activityBody(input)));

  @override
  Future<CmsActivity> updateActivity(String slug, CmsActivityInput input) async =>
      _activity(await _api.putObject(CmsPaths.activity(slug), body: _activityBody(input)));

  @override
  Future<void> deleteActivity(String slug) async {
    await _api.delete(CmsPaths.activity(slug));
  }

  @override
  Future<List<CmsFacility>> fetchFacilities() async => [
    for (final r in await _api.getList(CmsPaths.facilities)) _facility(r),
  ];

  @override
  Future<CmsFacility> createFacility(CmsFacilityInput input) async =>
      _facility(await _api.postObject(CmsPaths.facilities, body: _facilityBody(input)));

  @override
  Future<CmsFacility> updateFacility(int id, CmsFacilityInput input) async =>
      _facility(await _api.putObject(CmsPaths.facility(id), body: _facilityBody(input)));

  @override
  Future<void> deleteFacility(int id) async {
    await _api.delete(CmsPaths.facility(id));
  }

  @override
  Future<List<CmsFaq>> fetchFaqs() async => [
    for (final r in await _api.getList(CmsPaths.faq)) _faq(r),
  ];

  @override
  Future<CmsFaq> createFaq(CmsFaqInput input) async =>
      _faq(await _api.postObject(CmsPaths.faq, body: _faqBody(input)));

  @override
  Future<CmsFaq> updateFaq(int id, CmsFaqInput input) async =>
      _faq(await _api.putObject(CmsPaths.faqItem(id), body: _faqBody(input)));

  @override
  Future<void> deleteFaq(int id) async {
    await _api.delete(CmsPaths.faqItem(id));
  }

  @override
  Future<String> uploadMedia({required String filename, required Uint8List bytes}) async {
    final json = await _api.postObject(
      CmsPaths.media,
      // Server menentukan jenis gambar dari isinya, bukan dari nama atau tipe kiriman klien.
      body: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
    );
    return json['url'] as String;
  }

  List<JsonMap> _asList(Object? data) => [for (final r in data as List<dynamic>) r as JsonMap];

  List<CmsPage> _pages(List<JsonMap> rows) => [
    for (final r in rows)
      CmsPage(
        kunci: r['kunci'] as String,
        label: r['label'] as String,
        grup: r['grup'] as String,
        baris: (r['baris'] as num).toInt(),
        isi: r['isi'] as String? ?? '',
      ),
  ];

  CmsSchool _school(JsonMap r) => CmsSchool(
    nama: r['nama'] as String,
    kota: r['kota'] as String,
    npsn: r['npsn'] as String?,
    alamat: r['alamat'] as String?,
    akreditasi: r['akreditasi'] as String?,
    telepon: r['telepon'] as String?,
    email: r['email'] as String?,
    mediaSosial: r['media_sosial'] as String?,
    whatsapp: r['whatsapp'] as String?,
    petaUrl: r['peta_url'] as String?,
    fotoUrl: r['foto_url'] as String?,
  );

  CmsPost _post(JsonMap r) => CmsPost(
    slug: r['slug'] as String,
    kategori: r['kategori'] as String,
    judul: r['judul'] as String,
    ringkasan: r['ringkasan'] as String? ?? '',
    tanggal: DateTime.parse(r['tanggal'] as String),
    status: ContentStatus.from(r['status'] as String?),
    gambarUrl: r['gambar_url'] as String?,
    isi: r['isi'] as String? ?? '',
  );

  Map<String, dynamic> _postBody(CmsPostInput i) => {
    'judul': i.judul,
    'kategori': i.kategori,
    'ringkasan': i.ringkasan,
    'isi': i.isi,
    'gambar_url': i.gambarUrl,
    'status': i.status.code,
    if (i.tanggal != null) 'tanggal': isoDate(i.tanggal!),
  };

  CmsActivity _activity(JsonMap r) => CmsActivity(
    slug: r['slug'] as String,
    kategori: r['kategori'] as String,
    judul: r['judul'] as String,
    deskripsi: r['deskripsi'] as String? ?? '',
    tanggal: DateTime.parse(r['tanggal'] as String),
    status: ContentStatus.from(r['status'] as String?),
    fotoUrls: [for (final u in (r['foto_urls'] as List<dynamic>? ?? const [])) u as String],
  );

  Map<String, dynamic> _activityBody(CmsActivityInput i) => {
    'judul': i.judul,
    'kategori': i.kategori,
    'deskripsi': i.deskripsi,
    'status': i.status.code,
    'foto_urls': i.fotoUrls,
    if (i.tanggal != null) 'tanggal': isoDate(i.tanggal!),
  };

  CmsFacility _facility(JsonMap r) => CmsFacility(
    id: (r['id'] as num).toInt(),
    nama: r['nama'] as String,
    deskripsi: r['deskripsi'] as String? ?? '',
    urutan: (r['urutan'] as num).toInt(),
    tampil: r['tampil'] as bool? ?? true,
    gambarUrl: r['gambar_url'] as String?,
  );

  Map<String, dynamic> _facilityBody(CmsFacilityInput i) => {
    'nama': i.nama,
    'deskripsi': i.deskripsi,
    'gambar_url': i.gambarUrl,
    'tampil': i.tampil,
    if (i.urutan != null) 'urutan': i.urutan,
  };

  CmsFaq _faq(JsonMap r) => CmsFaq(
    id: (r['id'] as num).toInt(),
    kategori: r['kategori'] as String,
    pertanyaan: r['pertanyaan'] as String,
    jawaban: r['jawaban'] as String,
    urutan: (r['urutan'] as num).toInt(),
    tampil: r['tampil'] as bool? ?? true,
  );

  Map<String, dynamic> _faqBody(CmsFaqInput i) => {
    'kategori': i.kategori,
    'pertanyaan': i.pertanyaan,
    'jawaban': i.jawaban,
    'tampil': i.tampil,
    if (i.urutan != null) 'urutan': i.urutan,
  };

  Guru _guru(JsonMap r) => Guru(
    id: '${r['id']}',
    name: r['nama'] as String,
    email: r['email'] as String,
    role: r['peran'] == 'wali' ? GuruRole.wali : GuruRole.mapel,
    active: r['aktif'] as bool? ?? true,
    mustChangePassword: r['wajib_ganti_password'] as bool? ?? false,
  );

  Siswa _siswa(JsonMap r) => Siswa(
    id: '${r['id']}',
    name: r['nama'] as String,
    email: r['email'] as String,
    classCode: r['kelas'] as String,
    parentName: r['nama_orang_tua'] as String? ?? '',
    active: r['aktif'] as bool? ?? true,
    mustChangePassword: r['wajib_ganti_password'] as bool? ?? false,
  );

  AdminUser _admin(JsonMap r) => AdminUser(
    id: '${r['id']}',
    name: r['nama'] as String,
    email: r['email'] as String,
    active: r['aktif'] as bool? ?? true,
    mustChangePassword: r['wajib_ganti_password'] as bool? ?? false,
  );
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
);
