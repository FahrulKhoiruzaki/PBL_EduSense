import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/app_models.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login({required String email, required String password});

  Future<AuthSession?> restore();

  Future<void> changePassword({required String newPassword});

  Future<void> logout();
}

abstract final class AuthPaths {
  static const login = '/auth/login';
  static const me = '/auth/me';
  static const password = '/auth/password';
  static const logout = '/auth/logout';
  static const forgotPassword = '/auth/forgot-password';
}

class ApiAuthRepository implements AuthRepository {
  const ApiAuthRepository(this._api);

  final ApiClient _api;

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    final json = await _api.postObject(
      AuthPaths.login,
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final session = _parseSession(json, token: json['token'] as String);
    await _api.tokens.write(session.token);
    return session;
  }

  @override
  Future<AuthSession?> restore() async {
    final token = await _api.tokens.read();
    if (token == null) return null;
    try {
      return _parseSession(await _api.getObject(AuthPaths.me), token: token);
    } on ApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      await _api.tokens.clear();
      return null;
    }
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    await _api.put(AuthPaths.password, body: {'new_password': newPassword});
  }

  @override
  Future<void> logout() async {
    try {
      await _api.post(AuthPaths.logout);
    } on ApiException {
      // Token tetap dihapus lokal walaupun server tidak terjangkau.
    } finally {
      await _api.tokens.clear();
    }
  }

  AuthSession _parseSession(Map<String, dynamic> json, {required String token}) {
    final user = json['user'] as Map<String, dynamic>;
    if (user['role'] != 'guru') {
      throw const ApiException(
        type: ApiErrorType.forbidden,
        message: 'Akun ini bukan akun guru.',
      );
    }
    final guru = (json['guru'] as Map<String, dynamic>?) ?? const {};
    final settings = (json['pengaturan'] as Map<String, dynamic>?) ?? const {};
    List<String> classes(String key) =>
        [for (final c in (guru[key] as List<dynamic>? ?? const [])) c as String];

    String? text(Object? value) {
      final t = (value as String?)?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final lateLimit = text(settings['batas_jam_terlambat']);

    return AuthSession(
      token: token,
      user: AuthUser(
        id: (user['id'] as num).toInt(),
        email: user['email'] as String,
        name: user['nama'] as String,
        mustChangePassword: user['must_change_password'] as bool? ?? false,
        nip: text(guru['nip']),
      ),
      waliClasses: classes('wali_kelas'),
      mapelClasses: classes('mapel'),
      lateLimit: lateLimit != null && lateLimit.length > 5 ? lateLimit.substring(0, 5) : lateLimit,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(ref.watch(apiClientProvider)),
);
