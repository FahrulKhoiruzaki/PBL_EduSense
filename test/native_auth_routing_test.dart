import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/core/theme.dart';
import 'package:edu_sense/features/admin/screens/admin_main_layout.dart';
import 'package:edu_sense/features/guru/screens/login_screen.dart';
import 'package:edu_sense/features/guru/screens/main_layout.dart';
import 'package:edu_sense/features/guru/screens/native_role_selection_screen.dart';
import 'package:edu_sense/features/web_auth/data/web_auth_models.dart';
import 'package:edu_sense/features/web_auth/screens/web_login_screen.dart';
import 'package:edu_sense/main.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
import 'package:edu_sense/repositories/web_auth_repository.dart';
import 'package:edu_sense/widgets/avatar.dart';
import 'package:edu_sense/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/test_env.dart';

class _RecordingAuthRepository extends FakeAuthRepository {
  var restoreCalls = 0;
  var loginCalls = 0;

  @override
  Future<AuthSession?> restore() {
    restoreCalls++;
    return super.restore();
  }

  @override
  Future<AuthSession> login({required String email, required String password}) {
    loginCalls++;
    return super.login(email: email, password: password);
  }
}

class _FakeWebAuthRepository implements WebAuthRepository {
  final calls = <({String email, WebRole role})>[];
  var logoutCalls = 0;

  @override
  Future<WebAuthResult> login({
    required String email,
    required String password,
    required WebRole role,
  }) async {
    calls.add((email: email, role: role));
    if (email != 'admin@contoh.id' || password != 'Admin12345') {
      throw const ApiException(
        type: ApiErrorType.unauthorized,
        message: 'Email atau password tidak sesuai.',
      );
    }
    return WebAuthResult(
      token: 'admin-token',
      user: AuthUser(
        id: 10,
        email: email,
        name: 'Admin Sekolah',
        mustChangePassword: false,
      ),
    );
  }

  @override
  Future<void> changePassword({required String newPassword}) async {}

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> logout() async => logoutCalls++;
}

Widget _app({
  required FakeAuthRepository auth,
  required _FakeWebAuthRepository web,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      guruRepositoryProvider.overrideWithValue(FakeGuruRepository()),
      webAuthRepositoryProvider.overrideWithValue(web),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AplikasiGuruApp(),
    ),
  );
}

Future<void> _boot(
  WidgetTester tester, {
  FakeAuthRepository? auth,
  _FakeWebAuthRepository? web,
}) async {
  await prepareFonts();
  await tester.pumpWidget(
    _app(
      auth: auth ?? FakeAuthRepository(),
      web: web ?? _FakeWebAuthRepository(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final errors = captureErrors();

  testWidgets('signed-out native app shows exactly three roles', (
    tester,
  ) async {
    await _boot(tester);

    expect(find.byType(NativeRoleSelectionScreen), findsOneWidget);
    expect(find.text('Guru Mapel'), findsOneWidget);
    expect(find.text('Wali Kelas'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Orang Tua'), findsNothing);
    expect(find.text('Portal Orang Tua'), findsNothing);
    expect(errors, isEmpty);
  });

  for (final role in ['Guru Mapel', 'Wali Kelas', 'Admin']) {
    testWidgets('$role opens immediately without authentication requests', (
      tester,
    ) async {
      final auth = _RecordingAuthRepository();
      final web = _FakeWebAuthRepository();
      await _boot(tester, auth: auth, web: web);
      final restoreCalls = auth.restoreCalls;

      await tester.tap(find.text(role));
      // Start the route, then advance one display frame into the fade.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final destination = role == 'Admin'
          ? find.byType(WebLoginScreen)
          : find.byType(LoginScreen);
      expect(destination, findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final route = ModalRoute.of(tester.element(destination))!;
      expect(route.transitionDuration, const Duration(milliseconds: 250));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 230),
      );
      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pump(const Duration(milliseconds: 260));
      expect(route.animation!.isCompleted, isTrue);
      expect(auth.loginCalls, 0);
      expect(auth.restoreCalls, restoreCalls);
      expect(web.calls, isEmpty);
      expect(errors, isEmpty);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('selector fits narrow screens with large text in $brightness', (
      tester,
    ) async {
      await prepareFonts();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final theme = brightness == Brightness.dark
          ? AppTheme.dark
          : AppTheme.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const NativeRoleSelectionScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guru Mapel'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Wali Kelas'), 150);
      await tester.pumpAndSettle();
      expect(find.text('Wali Kelas').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Admin'), 150);
      await tester.pumpAndSettle();
      expect(find.text('Admin').hitTestable(), findsOneWidget);
      expect(errors, isEmpty);
    });
  }

  testWidgets('teacher cards open the existing fixed-role login', (
    tester,
  ) async {
    await _boot(tester);

    await tester.tap(find.text('Guru Mapel'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Login Guru Mapel'), findsOneWidget);
    expect(find.text('Masuk sebagai Wali Kelas'), findsNothing);
    expect(find.text('Kembali ke Pilihan Role'), findsOneWidget);

    await tester.tap(find.text('Kembali ke Pilihan Role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wali Kelas'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Login Wali Kelas'), findsOneWidget);
    expect(find.text('Masuk sebagai Guru Mapel'), findsNothing);
  });

  testWidgets(
    'teacher login reaches dashboard and logout returns to selector',
    (tester) async {
      final auth = FakeAuthRepository();
      await _boot(tester, auth: auth);

      await tester.tap(find.text('Guru Mapel'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'pak.andi@contoh.id');
      await tester.enterText(fields.at(1), 'Guru12345');
      await tester.tap(find.widgetWithText(CustomButton, 'Masuk'));
      await tester.pumpAndSettle();

      expect(find.byType(MainLayout), findsOneWidget);

      await tester.tap(find.byType(Avatar).first);
      await tester.pumpAndSettle();
      final logout = find.widgetWithText(CustomButton, 'Keluar');
      await tester.scrollUntilVisible(
        logout,
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(logout);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keluar').last);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(auth.loggedOut, isTrue);
      expect(find.byType(NativeRoleSelectionScreen), findsOneWidget);
      expect(find.byType(MainLayout), findsNothing);
      expect(errors, isEmpty);
    },
  );

  testWidgets('admin card opens existing admin authentication and dashboard', (
    tester,
  ) async {
    final web = _FakeWebAuthRepository();
    await _boot(tester, web: web);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.byType(WebLoginScreen), findsOneWidget);
    expect(find.text('Kembali ke Pilihan Role'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'admin@contoh.id');
    await tester.enterText(fields.at(1), 'Admin12345');
    await tester.tap(find.widgetWithText(CustomButton, 'Masuk'));
    await tester.pumpAndSettle();

    expect(web.calls, [(email: 'admin@contoh.id', role: WebRole.admin)]);
    expect(find.byType(AdminMainLayout), findsOneWidget);

    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar').last);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(web.logoutCalls, 1);
    expect(find.byType(NativeRoleSelectionScreen), findsOneWidget);
    expect(find.byType(AdminMainLayout), findsNothing);
    expect(errors, isEmpty);
  });
}
