import 'dart:convert';
import 'dart:typed_data';

import 'package:edu_sense/core/network/api_client.dart';
import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/core/network/token_storage.dart';
import 'package:edu_sense/models/academic_models.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorded {
  _Recorded(this.options, this.body);
  final RequestOptions options;
  final String body;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.json);

  final int status;
  final Map<String, dynamic> json;
  final requests = <_Recorded>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requests.add(_Recorded(options, latin1.decode(bytes)));
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiGuruRepository, _Adapter)> _repo(int status, Map<String, dynamic> json) async {
  final adapter = _Adapter(status, json);
  final tokens = MemoryTokenStorage();
  await tokens.write('tok-123');
  final dio = Dio()..httpClientAdapter = adapter;
  final api = ApiClient(tokens: tokens, dio: dio, baseUrl: 'http://api.test/api/v1');
  return (ApiGuruRepository(api), adapter);
}

Future<FaceScanResult> _scan(ApiGuruRepository repo) =>
    repo.recognizeFace(classCode: '5A', image: Uint8List.fromList([1, 2, 3]));

void main() {
  test('face scan posts the photo as multipart field "foto" with the bearer token', () async {
    final (repo, adapter) = await _repo(200, {'hasil': 'tidak_dikenali'});

    await _scan(repo);

    final sent = adapter.requests.single;
    expect(sent.options.method, 'POST');
    expect(sent.options.uri.toString(), 'http://api.test/api/v1/guru/classes/5A/attendance/face');
    expect(sent.options.headers['Authorization'], 'Bearer tok-123');
    expect(sent.options.contentType, startsWith('multipart/form-data'));
    expect(sent.body, contains('name="foto"'));
    expect(sent.body, contains('filename="scan.jpg"'));
  });

  test('hasil "cocok" becomes FaceMatched with the HH:mm time', () async {
    final (repo, _) = await _repo(200, {
      'hasil': 'cocok',
      'kode': null,
      'pesan': null,
      'siswa_id': 7,
      'nama': 'Ahmad Rizky',
      'kelas': '5A',
      'waktu': '07:41:05',
      'status': 'H',
    });

    final result = await _scan(repo);

    expect(result, isA<FaceMatched>());
    final matched = result as FaceMatched;
    expect((matched.studentId, matched.studentName, matched.time), (7, 'Ahmad Rizky', '07:41'));
  });

  test('hasil "duplikat" becomes FaceDuplicate', () async {
    final (repo, _) = await _repo(200, {
      'hasil': 'duplikat',
      'kode': 'FaceDuplicate',
      'siswa_id': 7,
      'nama': 'Ahmad Rizky',
      'kelas': '5A',
      'waktu': '07:41:05',
    });

    final result = await _scan(repo);

    expect(result, isA<FaceDuplicate>());
    expect((result as FaceDuplicate).time, '07:41');
  });

  test('hasil "kelas_lain" becomes FaceOtherClass', () async {
    final (repo, _) = await _repo(200, {'hasil': 'kelas_lain', 'kode': 'FaceOtherClass'});

    expect(await _scan(repo), isA<FaceOtherClass>());
  });

  test('FaceNotRecognized comes back as a normal 200 result, not an exception', () async {
    final (repo, _) = await _repo(200, {
      'hasil': 'tidak_dikenali',
      'kode': 'FaceNotRecognized',
      'pesan': 'Wajah belum terdaftar. Minta wali kelas mendaftarkan wajah siswa.',
    });

    expect(await _scan(repo), isA<FaceNotRecognized>());
  });

  test('a 403 from the server surfaces as ApiException with the server message', () async {
    final (repo, _) = await _repo(403, {
      'message': 'Hanya guru mapel kelas ini yang dapat mencatat absensi dan nilai.',
    });

    await expectLater(
      _scan(repo),
      throwsA(
        isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.forbidden)
            .having((e) => e.message, 'message', contains('Hanya guru mapel')),
      ),
    );
  });

  test('class detail response from the backend parses into ClassData', () async {
    final (repo, _) = await _repo(200, {
      'siswa': [
        {
          'id': 1,
          'nama': 'Ahmad Rizky',
          'klasifikasi': 'Perlu Pendampingan',
          'status': null,
          'waktu': null,
          'literasi': 75,
          'numerasi': 0,
          'menurun': true,
        },
      ],
      'nilai': [
        {
          'id': 4,
          'siswa_id': 1,
          'siswa': 'Ahmad Rizky',
          'kategori': 'Literasi',
          'jenis_ujian': 'Ulangan',
          'nilai': 70.0,
          'nilai_sebelumnya': 80.0,
          'tanggal': '2026-10-05',
          'catatan_guru': null,
        },
      ],
      'rata_literasi': 73,
      'rata_numerasi': 0,
      'tren': {
        'literasi': [75, 71],
        'numerasi': <int>[],
        'kehadiran': [50],
      },
    });

    final data = await repo.fetchClassData('5A');

    expect(data.students.single.classification, Classification.perlu);
    expect(data.students.single.declining, isTrue);
    expect((data.grades.single.value, data.grades.single.previous), (70, 80));
    expect(data.grades.single.note, '');
    expect(data.literasiTrend, [75, 71]);
    expect(data.attendanceTrend, [50]);
  });

  test('grades are sent with komponen_id (not kategori)', () async {
    final (repo, adapter) = await _repo(201, {'id': 9});

    await repo.createGrade(
      '5A',
      GradeInput(
        studentId: 1,
        componentId: 100,
        assessment: '',
        value: 88,
        date: DateTime(2026, 9, 1),
        note: '',
      ),
    );

    final body = jsonDecode(adapter.requests.single.body) as Map<String, dynamic>;
    expect(body['komponen_id'], 100);
    expect(body.containsKey('kategori'), isFalse);
    expect(body['tanggal'], '2026-09-01');
  });

  test('class detail sends periode_id and keeps unclassified students unclassified', () async {
    final (repo, adapter) = await _repo(200, {
      'periode': {
        'id': 1,
        'tahun_ajaran': '2025/2026',
        'semester': 2,
        'semester_label': 'Genap',
        'label': 'Semester Genap 2025/2026',
        'tanggal_mulai': '2026-01-05',
        'tanggal_selesai': '2026-06-20',
        'aktif': false,
      },
      'siswa': [
        {'id': 1, 'nama': 'Ahmad', 'klasifikasi': null, 'status': null, 'waktu': null,
         'literasi': 0, 'numerasi': 0, 'menurun': false},
      ],
      'nilai': [
        {'id': 4, 'siswa_id': 1, 'siswa': 'Ahmad', 'kategori': null, 'jenis_ujian': 'Praktik',
         'periode_id': 1, 'mapel_id': 7, 'mapel': 'PJOK', 'komponen_id': 70,
         'komponen': 'Praktik', 'nilai': 90.0, 'nilai_sebelumnya': null,
         'tanggal': '2026-03-02', 'catatan_guru': null},
      ],
      'rata_literasi': 0,
      'rata_numerasi': 0,
      'tren': {'literasi': <int>[], 'numerasi': <int>[], 'kehadiran': <int>[]},
    });

    final data = await repo.fetchClassData('5A', periodId: 1);

    expect(adapter.requests.single.options.uri.queryParameters, {'periode_id': '1'});
    expect(data.period?.label, 'Semester Genap 2025/2026');
    expect(data.students.single.classification, isNull);
    final g = data.grades.single;
    expect((g.category, g.subjectName, g.componentId, g.isLegacy), (null, 'PJOK', 70, false));
    expect(g.subjectLabel, 'PJOK');
  });

  test('classification summary parses counts, percentages and comparison', () async {
    Map<String, dynamic> dist(List<int> n, {String? kelas}) => {
          'kelas': ?kelas,
          'total_siswa': n.reduce((a, b) => a + b) + 1,
          'terklasifikasi': n.reduce((a, b) => a + b),
          'belum_lengkap': 1,
          'tanpa_nilai': 0,
          'kategori': [
            {'klasifikasi': 'Mahir', 'jumlah': n[0], 'persen': 50.0},
            {'klasifikasi': 'Cukup', 'jumlah': n[1], 'persen': 25.0},
            {'klasifikasi': 'Perlu Pendampingan', 'jumlah': n[2], 'persen': 25.0},
          ],
        };
    final period = {
      'id': 2, 'tahun_ajaran': '2026/2027', 'semester': 1, 'semester_label': 'Ganjil',
      'label': 'Semester Ganjil 2026/2027', 'tanggal_mulai': '2026-07-13',
      'tanggal_selesai': '2026-12-19', 'aktif': true,
    };
    final (repo, adapter) = await _repo(200, {
      'periode': period,
      'aturan': {'periode_id': 2, 'metode': 'terendah', 'batas_mahir': 80, 'batas_cukup': 65,
                 'updated_at': '2026-10-01T00:00:00Z'},
      'ringkasan': dist([2, 1, 1]),
      'per_kelas': [dist([2, 1, 1], kelas: '5A')],
      'perbandingan': {
        'periode': {...period, 'id': 1, 'label': 'Semester Genap 2025/2026', 'aktif': false},
        'sebelumnya': dist([1, 2, 1]),
        'sekarang': dist([2, 1, 1]),
        'dibandingkan': 4, 'naik': 1, 'turun': 0, 'tetap': 3,
      },
      'catatan': null,
    });

    final s = await repo.fetchClassification('5A');

    expect(adapter.requests.single.options.uri.path, '/api/v1/guru/classes/5A/classification');
    expect(s.rule?.method, ClassificationMethod.lowest);
    expect(s.overall.countOf(Classification.mahir).count, 2);
    expect(s.overall.countOf(Classification.mahir).percent, 50.0);
    expect((s.overall.classified, s.overall.incomplete), (4, 1));
    expect(s.perClass.single.className, '5A');
    expect((s.comparison?.up, s.comparison?.same), (1, 3));
  });

  test('class subjects parse type, input permission and components', () async {
    final tokens = MemoryTokenStorage();
    await tokens.write('tok-123');
    final dio = Dio()
      ..httpClientAdapter = _ListAdapter([
        {
          'mapel_id': 9, 'kode': 'BJAWA', 'nama': 'Bahasa Jawa', 'jenis': 'muatan_lokal',
          'boleh_input': true,
          'komponen': [
            {'id': 1, 'nama': 'Tugas', 'kategori': null, 'bobot': null, 'aktif': true},
            {'id': 2, 'nama': 'Lama', 'kategori': 'Literasi', 'bobot': 30, 'aktif': false},
          ],
        },
      ]);
    final repo = ApiGuruRepository(ApiClient(tokens: tokens, dio: dio, baseUrl: 'http://api.test/api/v1'));
    final subjects = await repo.fetchClassSubjects('5A', periodId: 2);

    final s = subjects.single;
    expect((s.type, s.canInput, s.components.length), (SubjectType.muatanLokal, true, 2));
    expect(s.activeComponents.map((c) => c.id), [1]);
    expect(s.components[1].weight, 30);
  });
}

class _ListAdapter implements HttpClientAdapter {
  _ListAdapter(this.rows);

  final List<Map<String, dynamic>> rows;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(rows),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}
