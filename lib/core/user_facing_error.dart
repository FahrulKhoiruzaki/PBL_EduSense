/// Galat yang aman ditampilkan ke pengguna, dengan pesan per kolom formulir bila ada.
///
/// Dipakai bersama oleh lapisan data (dari respons server) dan domain (validasi), sehingga
/// formulir cukup menangkap satu jenis galat tanpa tahu dari mana asalnya.
abstract interface class UserFacingError {
  String get message;

  /// Kunci kolom (sama dengan nama kolom di API) -> pesan.
  Map<String, String> get fieldErrors;
}
