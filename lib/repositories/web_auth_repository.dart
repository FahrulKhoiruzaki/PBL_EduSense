import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../features/web_auth/data/web_auth_models.dart';
import '../models/app_models.dart';
import 'auth_repository.dart';

abstract interface class WebAuthRepository {
  Future<WebAuthResult> login({
    required String email,
    required String password,
    required WebRole role,
  });

  Future<void> changePassword({required String newPassword});

  Future<void> requestPasswordReset(String email);

  Future<void> logout();
}

class ApiWebAuthRepository implements WebAuthRepository {
  const ApiWebAuthRepository(this._api);

  final ApiClient _api;

  static const _invalidResponse = ApiException(
    type: ApiErrorType.unknown,
    message: 'Format respons server tidak sesuai.',
  );

  @override
  Future<WebAuthResult> login({
    required String email,
    required String password,
    required WebRole role,
  }) async {
    final json = await _api.postObject(
      AuthPaths.login,
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final result = _parse(json, role);
    await _api.tokens.write(result.token);
    return result;
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    await _api.put(AuthPaths.password, body: {'new_password': newPassword});
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await _api.post(AuthPaths.forgotPassword, body: {'email': email}, authenticated: false);
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

  WebAuthResult _parse(JsonMap json, WebRole role) {
    final Map<String, dynamic> user;
    final String token;
    try {
      user = json['user'] as Map<String, dynamic>;
      token = json['token'] as String;
    } on TypeError {
      throw _invalidResponse;
    }

    if (user['role'] != role.apiValue) {
      throw const ApiException(
        type: ApiErrorType.forbidden,
        message: 'Akun ini tidak memiliki akses ke halaman ini.',
      );
    }

    try {
      final email = user['email'] as String;
      return WebAuthResult(
        token: token,
        user: AuthUser(
          id: (user['id'] as num).toInt(),
          email: email,
          name: (user['nama'] as String?) ?? email,
          mustChangePassword: user['must_change_password'] as bool? ?? false,
        ),
      );
    } on TypeError {
      throw _invalidResponse;
    }
  }
}

final webAuthRepositoryProvider = Provider<WebAuthRepository>(
  (ref) => ApiWebAuthRepository(ref.watch(apiClientProvider)),
);
