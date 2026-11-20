import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/media_url.dart';
import '../features/website/data/website_models.dart';

abstract interface class WebsiteRepository {
  Future<List<Berita>> fetchNews();

  Future<Berita> fetchNewsDetail(String slug);

  Future<List<Kegiatan>> fetchActivities();

  Future<Kegiatan> fetchActivityDetail(String slug);

  Future<List<Fasilitas>> fetchFacilities();

  Future<List<Faq>> fetchFaq();

  Future<List<StaffMember>> fetchStaff();

  Future<SchoolInfo> fetchSchoolInfo();

  Future<Map<String, String>> fetchPages();

  Future<List<ClassLevelInfo>> fetchClassInfo();

  Future<List<CalendarEvent>> fetchCalendar();
}

abstract final class WebsitePaths {
  static const news = '/public/informasi';
  static String newsDetail(String slug) => '/public/informasi/$slug';
  static const activities = '/public/kegiatan';
  static String activityDetail(String slug) => '/public/kegiatan/$slug';
  static const facilities = '/public/fasilitas';
  static const faq = '/public/faq';
  static const staff = '/public/guru';
  static const schoolInfo = '/public/sekolah';
  static const pages = '/public/halaman';
  static const classInfo = '/public/kelas';
  static const calendar = '/public/kalender';
}

class ApiWebsiteRepository implements WebsiteRepository {
  const ApiWebsiteRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Berita>> fetchNews() async {
    final rows = await _api.getList(WebsitePaths.news, authenticated: false);
    return [for (final r in rows) _berita(r)];
  }

  @override
  Future<Berita> fetchNewsDetail(String slug) async =>
      _berita(await _api.getObject(WebsitePaths.newsDetail(slug), authenticated: false));

  @override
  Future<List<Kegiatan>> fetchActivities() async {
    final rows = await _api.getList(WebsitePaths.activities, authenticated: false);
    return [for (final r in rows) _kegiatan(r)];
  }

  @override
  Future<Kegiatan> fetchActivityDetail(String slug) async =>
      _kegiatan(await _api.getObject(WebsitePaths.activityDetail(slug), authenticated: false));

  @override
  Future<List<Fasilitas>> fetchFacilities() async {
    final rows = await _api.getList(WebsitePaths.facilities, authenticated: false);
    return [
      for (final r in rows)
        Fasilitas(
          id: (r['id'] as num).toInt(),
          nama: r['nama'] as String,
          deskripsi: r['deskripsi'] as String? ?? '',
          imageUrl: _url(r['gambar_url']),
        ),
    ];
  }

  @override
  Future<List<Faq>> fetchFaq() async {
    final rows = await _api.getList(WebsitePaths.faq, authenticated: false);
    return [
      for (final r in rows)
        Faq(
          kategori: FaqKategori.values.firstWhere(
            (k) => k.label == r['kategori'],
            orElse: () => FaqKategori.umum,
          ),
          pertanyaan: r['pertanyaan'] as String,
          jawaban: r['jawaban'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<List<StaffMember>> fetchStaff() async {
    final rows = await _api.getList(WebsitePaths.staff, authenticated: false);
    return [
      for (final r in rows)
        StaffMember(
          nama: r['nama'] as String,
          jabatan: r['jabatan'] as String? ?? '',
          fotoUrl: _url(r['foto_url']),
        ),
    ];
  }

  @override
  Future<SchoolInfo> fetchSchoolInfo() async {
    final r = await _api.getObject(WebsitePaths.schoolInfo, authenticated: false);
    return SchoolInfo(
      nama: r['nama'] as String? ?? SchoolInfo.empty.nama,
      kota: r['kota'] as String? ?? SchoolInfo.empty.kota,
      npsn: _text(r['npsn']),
      alamat: _text(r['alamat']),
      akreditasi: _text(r['akreditasi']),
      telepon: _text(r['telepon']),
      email: _text(r['email']),
      mediaSosial: _text(r['media_sosial']),
      whatsapp: _text(r['whatsapp']),
      petaUrl: _url(r['peta_url']),
      fotoUrl: _url(r['foto_url']),
    );
  }

  @override
  Future<Map<String, String>> fetchPages() async {
    final rows = await _api.getList(WebsitePaths.pages, authenticated: false);
    return {
      for (final r in rows)
        if (_text(r['isi']) != null) r['kunci'] as String: r['isi'] as String,
    };
  }

  @override
  Future<List<ClassLevelInfo>> fetchClassInfo() async {
    final rows = await _api.getList(WebsitePaths.classInfo, authenticated: false);
    return [
      for (final r in rows)
        ClassLevelInfo(
          id: (r['id'] as num).toInt(),
          tingkat: (r['tingkat'] as num).toInt(),
          kind: ClassInfoKind.from(r['jenis'] as String?),
          judul: r['judul'] as String,
          deskripsi: r['deskripsi'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<List<CalendarEvent>> fetchCalendar() async {
    final rows = await _api.getList(WebsitePaths.calendar, authenticated: false);
    return [
      for (final r in rows)
        CalendarEvent(
          id: (r['id'] as num).toInt(),
          judul: r['judul'] as String,
          deskripsi: r['deskripsi'] as String? ?? '',
          kategori: r['kategori'] as String? ?? 'Kegiatan',
          mulai: DateTime.parse(r['tanggal_mulai'] as String),
          selesai: r['tanggal_selesai'] == null
              ? null
              : DateTime.parse(r['tanggal_selesai'] as String),
        ),
    ];
  }

  Berita _berita(Map<String, dynamic> r) => Berita(
        slug: r['slug'] as String,
        kategori: BeritaKategori.values.firstWhere(
          (k) => k.label == r['kategori'],
          orElse: () => BeritaKategori.berita,
        ),
        tanggal: DateTime.parse(r['tanggal'] as String),
        judul: r['judul'] as String,
        ringkasan: r['ringkasan'] as String? ?? '',
        isi: r['isi'] as String? ?? '',
        imageUrl: _url(r['gambar_url']),
      );

  Kegiatan _kegiatan(Map<String, dynamic> r) => Kegiatan(
        slug: r['slug'] as String,
        kategori: KegiatanKategori.values.firstWhere(
          (k) => k.label == r['kategori'],
          orElse: () => KegiatanKategori.acaraSekolah,
        ),
        tanggal: DateTime.parse(r['tanggal'] as String),
        judul: r['judul'] as String,
        deskripsi: r['deskripsi'] as String? ?? '',
        imageUrl: _url(r['gambar_url']),
        fotoUrls: [
          for (final f in (r['foto'] as List<dynamic>? ?? const []))
            ?_url((f as Map<String, dynamic>)['url']),
        ],
      );

  String? _text(Object? value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _url(Object? value) => resolveMediaUrl(_text(value), baseUrl: _api.baseUrl);
}

final websiteRepositoryProvider = Provider<WebsiteRepository>(
  (ref) => ApiWebsiteRepository(ref.watch(apiClientProvider)),
);
