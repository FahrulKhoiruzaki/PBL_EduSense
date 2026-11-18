import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/parent_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  test('child overview keeps unclassified children unclassified and shows subjects', () async {
    final tokens = MemoryTokenStorage();
    await tokens.write('tok');
    final api = ApiClient(
      tokens: tokens,
      dio: Dio()
        ..httpClientAdapter = _Adapter([
          {
            'id': 1,
            'nis': '001',
            'nama': 'Ahmad',
            'kelas': '5A',
            'klasifikasi': null,
            'literasi': 0,
            'numerasi': 0,
            'persen_kehadiran': 100,
            'jumlah_terlambat': 0,
            'tren': {'literasi': <int>[], 'numerasi': <int>[], 'kehadiran': <int>[]},
            'riwayat_klasifikasi': [
              {'bulan': 'Ganjil 2025/2026', 'klasifikasi': 'Mahir'},
            ],
            'nilai': [
              {
                'id': 3,
                'kategori': null,
                'jenis_ujian': 'Praktik',
                'mapel': 'PJOK',
                'periode_id': 2,
                'nilai': 90.0,
                'nilai_sebelumnya': null,
                'tanggal': '2026-09-01',
                'catatan_guru': null,
              },
              {
                'id': 1,
                'kategori': 'Numerasi',
                'jenis_ujian': 'UH',
                'mapel': null,
                'periode_id': null,
                'nilai': 70.0,
                'nilai_sebelumnya': null,
                'tanggal': '2026-03-01',
                'catatan_guru': null,
              },
            ],
            'wali_kelas': 'Bu Rina',
            'tahun_ajaran': '2026/2027',
            'periode': 'Semester Ganjil 2026/2027',
            'diperbarui': null,
          },
        ]),
      baseUrl: 'http://api.test/api/v1',
    );

    final kid = (await ApiParentRepository(api).fetchChildren()).single;

    expect(kid.klasifikasi, isNull);
    expect(kid.periode, 'Semester Ganjil 2026/2027');
    expect(kid.riwayatKlasifikasi.single.klasifikasi, Classification.mahir);
    expect((kid.nilai[0].kategori, kid.nilai[0].mapelLabel), (null, 'PJOK'));
    expect((kid.nilai[1].kategori, kid.nilai[1].mapelLabel), (SubjectCategory.numerasi, 'Numerasi'));
  });
}
