import 'package:aplikasi_guru/core/whatsapp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('whatsAppUri', () {
    test('uses the number in international format and encodes the message', () {
      final uri = whatsAppUri(number: '6281234567890', message: 'Halo Admin & Bu Guru');
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/6281234567890');
      expect(uri.queryParameters['text'], 'Halo Admin & Bu Guru');
      expect(uri.toString(), 'https://wa.me/6281234567890?text=Halo+Admin+%26+Bu+Guru');
    });

    test('turns a local 0-prefixed number into 62', () {
      expect(whatsAppUri(number: '0812-3456-7890', message: 'x').path, '/6281234567890');
    });

    test('strips plus signs, spaces and 00 prefixes', () {
      expect(whatsAppUri(number: '+62 812 3456 7890', message: 'x').path, '/6281234567890');
      expect(whatsAppUri(number: '0062812345', message: 'x').path, '/62812345');
    });

    test('without a number it opens the contact chooser', () {
      expect(whatsAppUri(message: 'Halo').toString(), 'https://wa.me/?text=Halo');
      expect(whatsAppUri(number: '  ', message: 'Halo').path, '/');
    });

    test('keeps non-ASCII text intact', () {
      final uri = whatsAppUri(number: '62812', message: 'Nama: … Perihal: …');
      expect(uri.queryParameters['text'], 'Nama: … Perihal: …');
    });
  });
}
