import 'api_client.dart';

/// Gambar unggahan admin disimpan sebagai `/media/<nama>` (relatif terhadap server). Fungsi ini
/// menjadikannya alamat lengkap; tautan http(s) dari admin dibiarkan apa adanya.
String? resolveMediaUrl(String? url, {String? baseUrl}) {
  final value = url?.trim();
  if (value == null || value.isEmpty) return null;
  if (!value.startsWith('/')) return value;
  return '${Uri.parse(baseUrl ?? ApiConfig.baseUrl).origin}$value';
}
