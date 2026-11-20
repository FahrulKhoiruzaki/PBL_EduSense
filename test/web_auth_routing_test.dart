import 'package:edu_sense/core/network/api_exception.dart';
import 'package:edu_sense/core/theme.dart';
import 'package:edu_sense/features/admin/screens/admin_main_layout.dart';
import 'package:edu_sense/features/guru/screens/login_screen.dart';
import 'package:edu_sense/features/guru/screens/main_layout.dart';
import 'package:edu_sense/features/web_auth/data/web_auth_models.dart';
import 'package:edu_sense/features/web_auth/screens/web_login_screen.dart';
import 'package:edu_sense/features/web_auth/screens/web_role_selection_screen.dart';
import 'package:edu_sense/features/web_auth/screens/web_shell.dart';
import 'package:edu_sense/features/website/data/website_models.dart';
import 'package:edu_sense/features/website/screens/website_main_layout.dart';
import 'package:edu_sense/models/app_models.dart';
import 'package:edu_sense/repositories/auth_repository.dart';
import 'package:edu_sense/repositories/guru_repository.dart';
import 'package:edu_sense/repositories/web_auth_repository.dart';
import 'package:edu_sense/repositories/website_repository.dart';
import 'package:edu_sense/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/test_env.dart';

class _FakeWebAuthRepository implements WebAuthRepository {
  _FakeWebAuthRepository();

  final calls = <({String email, WebRole role})>[];
  var logoutCalls = 0;
  var changedPassword = false;

  @override
  Future<WebAuthResult> login({
    required String email,
    required String password,
    required WebRole role,
  }) async {
    calls.add((email: email, role: role));
    if (password != 'Admin12345' || email != 'admin@contoh.id') {
      throw const ApiException(
        type: ApiErrorType.unauthorized,
        message: 'Email atau password tidak sesuai.',
      );
    }
    return WebAuthResult(
      token: 'web-token',
      user: AuthUser(
        id: 7,
        email: email,
        name: 'Admin Sekolah',
        mustChangePassword: false,
      ),
    );
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    changedPassword = true;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> logout() async => logoutCalls++;
}

class _FakeWebsiteRepository implements WebsiteRepository {
  const _FakeWebsiteRepository();

  @override
  Future<List<Berita>> fetchNews() async => const [];

  @override
  Future<Berita> fetchNewsDetail(String slug) async =>
      throw UnimplementedError();

  @override
  Future<List<Kegiatan>> fetchActivities() async => const [];

  @override
  Future<Kegiatan> fetchActivityDetail(String slug) async =>
      throw UnimplementedError();

  @override
  Future<List<Fasilitas>> fetchFacilities() async => const [];

  @override
  Future<List<Faq>> fetchFaq() async => const [];

  @override
  Future<List<StaffMember>> fetchStaff() async => const [];

  @override
  Future<SchoolInfo> fetchSchoolInfo() async => const SchoolInfo();

  @override
  Future<Map<String, String>> fetchPages() async => const {};

  @override
  Future<List<ClassLevelInfo>> fetchClassInfo() async => const [];

  @override
  Future<List<CalendarEvent>> fetchCalendar() async => const [];
}

Widget _app({
  required bool dark,
  _FakeWebAuthRepository? web,
  FakeAuthRepository? auth,
}) {
  return ProviderScope(
    overrides: [
      webAuthRepositoryProvider.overrideWithValue(
        web ?? _FakeWebAuthRepository(),
      ),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      guruRepositoryProvider.overrideWithValue(FakeGuruRepository()),
      websiteRepositoryProvider.overrideWithValue(
        const _FakeWebsiteRepository(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: const WebShell(),
    ),
  );
}

Future<void> _openSelector(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool dark = false,
  _FakeWebAuthRepository? web,
  FakeAuthRepository? auth,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(_app(dark: dark, web: web, auth: auth));
  await tester.pumpAndSettle();
}

Future<void> _loginTeacher(
  WidgetTester tester,
  String email,
  TeacherRole role,
) async {
  await tester.tap(
    find
        .text(role == TeacherRole.guruMapel ? 'Guru Mapel' : 'Wali Kelas')
        .first,
  );
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(
    find.text(
      role == TeacherRole.guruMapel ? 'Login Guru Mapel' : 'Login Wali Kelas',
    ),
    findsOneWidget,
  );

  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), 'Guru12345');
  await tester.tap(find.widgetWithText(CustomButton, 'Masuk'));
  await tester.pumpAndSettle();
}

void main() {
  final errors = captureErrors();

  setUp(() async {
    await prepareFonts();
  });

  testWidgets('selector labels fit at mobile and desktop in both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      for (final size in [const Size(390, 844), const Size(1300, 900)]) {
        await _openSelector(tester, dark: dark, size: size);
        expect(find.byType(WebRoleSelectionScreen), findsOneWidget);
        expect(find.text('Guru Mapel'), findsOneWidget);
        expect(find.text('Wali Kelas'), findsOneWidget);
        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('Website Sekolah'), findsOneWidget);
        expect(find.text('Portal Orang Tua'), findsNothing);
        expect(errors, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('selector opens fixed teacher roles without the role toggle', (
    tester,
  ) async {
    await _openSelector(tester);

    await tester.tap(find.text('Guru Mapel').first);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Login Guru Mapel'), findsOneWidget);
    expect(find.text('Masuk sebagai Wali Kelas'), findsNothing);
    expect(find.text('Masuk sebagai Guru Mapel'), findsOneWidget);
    await tester.tap(find.text('Kembali ke Pilihan Role'));
    await tester.pumpAndSettle();
    expect(find.byType(WebRoleSelectionScreen), findsOneWidget);

    await tester.tap(find.text('Wali Kelas').first);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Login Wali Kelas'), findsOneWidget);
    expect(find.text('Masuk sebagai Guru Mapel'), findsNothing);
    expect(find.text('Masuk sebagai Wali Kelas'), findsOneWidget);
  });

  testWidgets(
    'teacher valid sign-in opens the teacher layout for each fixed role',
    (tester) async {
      for (final (email, role) in [
        ('pak.andi@contoh.id', TeacherRole.guruMapel),
        ('bu.rina@contoh.id', TeacherRole.waliKelas),
      ]) {
        final auth = FakeAuthRepository();
        await _openSelector(tester, auth: auth);
        await _loginTeacher(tester, email, role);
        expect(find.byType(MainLayout), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('teacher assignment mismatch stays on the fixed login screen', (
    tester,
  ) async {
    await _openSelector(tester);
    await tester.tap(find.text('Wali Kelas').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'pak.andi@contoh.id');
    await tester.enterText(fields.at(1), 'Guru12345');
    await tester.tap(find.widgetWithText(CustomButton, 'Masuk'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('belum menjadi wali kelas'), findsOneWidget);
    expect(find.byType(MainLayout), findsNothing);
  });

  testWidgets(
    'teacher forced password change can cancel back to role selector',
    (tester) async {
      await _openSelector(tester);
      await tester.tap(find.text('Guru Mapel').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'guru.baru@contoh.id');
      await tester.enterText(fields.at(1), 'Guru12345');
      await tester.tap(find.widgetWithText(CustomButton, 'Masuk'));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      await tester.tap(find.text('Batal dan Keluar'));
      await tester.pumpAndSettle();
      expect(find.byType(WebRoleSelectionScreen), findsOneWidget);
    },
  );

  testWidgets(
    'admin sign-in uses the web repository and opens the admin layout',
    (tester) async {
      final web = _FakeWebAuthRepository();
      await _openSelector(tester, web: web);
      await tester.tap(find.text('Admin').first);
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
    },
  );

  testWidgets(
    'selector website action opens the public layout and parent entry remains available',
    (tester) async {
      await _openSelector(tester);
      final websiteLink = find.text('Website Sekolah');
      await tester.ensureVisible(websiteLink);
      await tester.tap(websiteLink);
      await tester.pumpAndSettle();
      expect(find.byType(WebsiteMainLayout), findsOneWidget);

      final button = find.text('Login Orang Tua').first;
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(WebLoginScreen), findsOneWidget);
      expect(find.text('Portal Orang Tua'), findsOneWidget);
    },
  );

  testWidgets('teacher web shell does not bootstrap the teacher session', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await _openSelector(tester, auth: auth);
    expect(auth.loggedOut, isFalse);
    expect(find.byType(WebRoleSelectionScreen), findsOneWidget);
  });
}
