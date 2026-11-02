import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../models/app_models.dart';
import '../../../repositories/web_auth_repository.dart';
import '../data/web_auth_models.dart';

enum WebAuthStatus { signedOut, mustChangePassword, signedIn }

class WebSession {
  const WebSession({
    this.status = WebAuthStatus.signedOut,
    this.role,
    this.user,
    this.notice,
  });

  final WebAuthStatus status;
  final WebRole? role;
  final AuthUser? user;
  final String? notice;
}

class WebSessionNotifier extends Notifier<WebSession> {
  @override
  WebSession build() {
    ref.listen(sessionExpiredProvider, (_, _) => _expire());
    return const WebSession();
  }

  WebAuthRepository get _repo => ref.read(webAuthRepositoryProvider);

  Future<String?> signIn({
    required String email,
    required String password,
    required WebRole role,
  }) async {
    try {
      final result = await _repo.login(email: email, password: password, role: role);
      state = WebSession(
        status: result.user.mustChangePassword
            ? WebAuthStatus.mustChangePassword
            : WebAuthStatus.signedIn,
        role: role,
        user: result.user,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> completePasswordChange(String newPassword) async {
    final current = state.user;
    if (current == null) return 'Sesi Anda telah berakhir. Silakan masuk kembali.';
    try {
      await _repo.changePassword(newPassword: newPassword);
    } on ApiException catch (e) {
      return e.message;
    }
    state = WebSession(
      status: WebAuthStatus.signedIn,
      role: state.role,
      user: AuthUser(
        id: current.id,
        email: current.email,
        name: current.name,
        mustChangePassword: false,
      ),
    );
    return null;
  }

  Future<void> signOut() async {
    await _repo.logout();
    state = const WebSession();
  }

  void _expire() {
    if (state.status == WebAuthStatus.signedOut) return;
    ref.read(tokenStorageProvider).clear();
    state = const WebSession(notice: 'Sesi Anda telah berakhir. Silakan masuk kembali.');
  }
}

final webSessionProvider =
    NotifierProvider<WebSessionNotifier, WebSession>(WebSessionNotifier.new);
