import 'package:aplikasi_guru/core/network/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'http://localhost:8081/api/v1';

  test('uploaded images are resolved against the server origin, not the /api/v1 prefix', () {
    expect(resolveMediaUrl('/media/a.jpg', baseUrl: base), 'http://localhost:8081/media/a.jpg');
    expect(
      resolveMediaUrl('/media/a.jpg', baseUrl: 'https://api.sekolah.id/api/v1'),
      'https://api.sekolah.id/media/a.jpg',
    );
  });

  test('absolute links are left alone and blanks become null', () {
    expect(resolveMediaUrl('https://cdn.contoh.id/x.png', baseUrl: base), 'https://cdn.contoh.id/x.png');
    expect(resolveMediaUrl('  ', baseUrl: base), isNull);
    expect(resolveMediaUrl(null, baseUrl: base), isNull);
  });
}
