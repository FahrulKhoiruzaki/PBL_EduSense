import 'package:edu_sense/features/guru/screens/login_screen.dart';
import 'package:edu_sense/main.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_env.dart';

/// Tanpa sesi tersimpan: `restore()` mengembalikan null, sehingga aplikasi
/// tidak pernah memanggil backend dan langsung menampilkan layar login.
class _SignedOutAuthRepository implements AuthRepository {
  var restoreCalls = 0;

  @override
  Future<AuthSession?> restore() async {
    restoreCalls++;
    return null;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) => throw UnimplementedError('Login tidak dipakai di smoke test ini.');

  @override
  Future<void> changePassword({required String newPassword}) =>
      throw UnimplementedError(
        'Ganti password tidak dipakai di smoke test ini.',
      );

  @override
  Future<void> logout() async {}
}

void main() {
  final errors = captureErrors();

  testWidgets('app boots to the login screen when no session is stored', (
    tester,
  ) async {
    await prepareFonts();
    final auth = _SignedOutAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const AplikasiGuruApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.restoreCalls, 1);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(errors, isEmpty);
  });
}
