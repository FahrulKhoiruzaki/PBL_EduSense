import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_exception.dart';
import 'token_storage.dart';

typedef JsonMap = Map<String, dynamic>;

abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8081/api/v1',
  );
  static const connectTimeout = Duration(seconds: 10);
  static const receiveTimeout = Duration(seconds: 20);
}

class ApiClient {
  ApiClient({
    required this.tokens,
    Dio? dio,
    String? baseUrl,
    this.onUnauthorized,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl ?? ApiConfig.baseUrl
      ..connectTimeout = ApiConfig.connectTimeout
      ..receiveTimeout = ApiConfig.receiveTimeout
      ..headers = {'Accept': 'application/json'}
      ..validateStatus = (status) => status != null && status >= 200 && status < 300;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokens.read();
          if (token != null && options.extra[_skipAuth] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  static const _skipAuth = 'skipAuth';

  final Dio _dio;
  final TokenStorage tokens;
  final VoidCallback? onUnauthorized;

  String get baseUrl => _dio.options.baseUrl;

  Future<Object?> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) =>
      _send('GET', path, query: query, authenticated: authenticated, cancelToken: cancelToken);

  Future<Object?> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) =>
      _send('POST', path,
          body: body, query: query, authenticated: authenticated, cancelToken: cancelToken);

  Future<Object?> put(String path, {Object? body, CancelToken? cancelToken}) =>
      _send('PUT', path, body: body, cancelToken: cancelToken);

  Future<Object?> patch(String path, {Object? body, CancelToken? cancelToken}) =>
      _send('PATCH', path, body: body, cancelToken: cancelToken);

  Future<Object?> delete(String path, {CancelToken? cancelToken}) =>
      _send('DELETE', path, cancelToken: cancelToken);

  Future<JsonMap> getObject(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async =>
      _asObject(await get(path, query: query, authenticated: authenticated));

  Future<List<JsonMap>> getList(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async =>
      _asList(await get(path, query: query, authenticated: authenticated));

  Future<JsonMap> postObject(String path, {Object? body, bool authenticated = true}) async =>
      _asObject(await post(path, body: body, authenticated: authenticated));

  Future<JsonMap> putObject(String path, {Object? body}) async =>
      _asObject(await put(path, body: body));

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, extra: {_skipAuth: !authenticated}),
      );
      return response.data;
    } on DioException catch (e) {
      final error = _toApiException(e);
      if (error.isUnauthorized && authenticated) onUnauthorized?.call();
      throw error;
    }
  }

  JsonMap _asObject(Object? data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException(
      type: ApiErrorType.unknown,
      message: 'Format respons server tidak sesuai.',
    );
  }

  List<JsonMap> _asList(Object? data) {
    final raw = data is Map<String, dynamic> ? data['data'] : data;
    if (raw is List) return raw.whereType<Map<String, dynamic>>().toList();
    throw const ApiException(
      type: ApiErrorType.unknown,
      message: 'Format respons server tidak sesuai.',
    );
  }

  ApiException _toApiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          type: ApiErrorType.timeout,
          message: 'Server terlalu lama merespons. Silakan coba lagi.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          type: ApiErrorType.network,
          message: 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        );
      case DioExceptionType.cancel:
        return const ApiException(type: ApiErrorType.cancelled, message: 'Permintaan dibatalkan.');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return const ApiException(
          type: ApiErrorType.network,
          message: 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        );
    }
  }

  ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    final body = response?.data;
    final serverMessage = body is Map ? body['message'] as String? : null;
    final fields = <String, String>{};
    if (body is Map && body['errors'] is Map) {
      (body['errors'] as Map).forEach((k, v) => fields['$k'] = '$v');
    }

    ApiException build(ApiErrorType type, String fallback) => ApiException(
          type: type,
          message: serverMessage ?? fallback,
          statusCode: status,
          fieldErrors: fields,
        );

    return switch (status) {
      401 => build(ApiErrorType.unauthorized, 'Sesi Anda telah berakhir. Silakan masuk kembali.'),
      403 => build(ApiErrorType.forbidden, 'Anda tidak memiliki akses untuk tindakan ini.'),
      404 => build(ApiErrorType.notFound, 'Data tidak ditemukan.'),
      409 => build(ApiErrorType.conflict, 'Data bentrok dengan data yang sudah ada.'),
      400 || 422 => build(ApiErrorType.validation, 'Data yang dikirim tidak valid.'),
      >= 500 => build(ApiErrorType.server, 'Terjadi kesalahan pada server. Silakan coba lagi nanti.'),
      _ => build(ApiErrorType.unknown, 'Terjadi kesalahan yang tidak terduga.'),
    };
  }
}

class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notify() => state++;
}

final sessionExpiredProvider =
    NotifierProvider<SessionExpiredNotifier, int>(SessionExpiredNotifier.new);

final tokenStorageProvider = Provider<TokenStorage>((ref) => MemoryTokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokens: ref.watch(tokenStorageProvider),
    onUnauthorized: () => ref.read(sessionExpiredProvider.notifier).notify(),
  );
});
