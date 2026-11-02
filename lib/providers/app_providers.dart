import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/app_models.dart';
import '../repositories/auth_repository.dart';
import '../repositories/guru_repository.dart';

export '../core/clock.dart';

abstract final class Scopes {
  static const attendance = 'attendance';
  static const students = 'students';
  static const grades = 'grades';
  static const history = 'history';
}

enum AuthStatus { signedOut, mustChangePassword, signedIn }

class Session {
  const Session({
    this.status = AuthStatus.signedOut,
    this.role = TeacherRole.guruMapel,
    this.user,
    this.classes = const [],
    this.lateLimit,
    this.notice,
  });

  final AuthStatus status;
  final TeacherRole role;
  final AuthUser? user;
  final List<String> classes;
  final String? lateLimit;
  final String? notice;

  bool get isWali => role == TeacherRole.waliKelas;

  String get displayName => user?.name ?? '';

  String get contactEmail => user?.email ?? '';

  Session copyWith({AuthStatus? status}) => Session(
        status: status ?? this.status,
        role: role,
        user: user,
        classes: classes,
        lateLimit: lateLimit,
      );
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() {
    ref.listen(sessionExpiredProvider, (_, _) => _expire());
    return const Session();
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<String?> signIn({
    required String email,
    required String password,
    required TeacherRole role,
  }) async {
    try {
      final result = await _auth.login(email: email, password: password);
      final classes = result.classesFor(role);
      if (classes.isEmpty) {
        await _auth.logout();
        return role == TeacherRole.waliKelas
            ? 'Akun ini belum menjadi wali kelas. Hubungi admin sekolah.'
            : 'Akun ini belum ditugaskan sebagai guru mapel. Hubungi admin sekolah.';
      }
      _start(result, role, classes);
      return null;
    } on ApiException catch (e) {
      await ref.read(tokenStorageProvider).clear();
      return e.message;
    }
  }

  // Peran yang dipilih saat login tidak disimpan di server, jadi pemulihan sesi
  // memakai Guru Mapel bila ada penugasan, selain itu Wali Kelas.
  Future<void> restore() async {
    final result = await _auth.restore();
    if (result == null) return;
    final role = result.mapelClasses.isNotEmpty ? TeacherRole.guruMapel : TeacherRole.waliKelas;
    final classes = result.classesFor(role);
    if (classes.isEmpty) {
      await _auth.logout();
      return;
    }
    _start(result, role, classes);
  }

  void _start(AuthSession result, TeacherRole role, List<String> classes) {
    state = Session(
      status: result.user.mustChangePassword
          ? AuthStatus.mustChangePassword
          : AuthStatus.signedIn,
      role: role,
      user: result.user,
      classes: classes,
      lateLimit: result.lateLimit,
    );
    ref.read(selectedClassProvider.notifier).select(classes.first);
    ref.read(activeTabProvider.notifier).select(0);
  }

  Future<String?> completePasswordChange(String newPassword) async {
    try {
      await _auth.changePassword(newPassword: newPassword);
    } on ApiException catch (e) {
      return e.message;
    }
    state = state.copyWith(status: AuthStatus.signedIn);
    ref.read(activeTabProvider.notifier).select(0);
    return null;
  }

  Future<void> signOut() async {
    await _auth.logout();
    _reset();
  }

  void _expire() {
    if (state.status == AuthStatus.signedOut) return;
    ref.read(tokenStorageProvider).clear();
    _reset(notice: 'Sesi Anda telah berakhir. Silakan masuk kembali.');
  }

  void _reset({String? notice}) {
    state = Session(role: state.role, notice: notice);
    ref.read(selectedClassProvider.notifier).select('');
    ref.read(activeTabProvider.notifier).select(0);
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, Session>(SessionNotifier.new);

final sessionBootstrapProvider =
    FutureProvider<void>((ref) => ref.read(sessionProvider.notifier).restore());

final currentUserIdProvider =
    Provider<int?>((ref) => ref.watch(sessionProvider.select((s) => s.user?.id)));

final teacherRoleProvider =
    Provider<TeacherRole>((ref) => ref.watch(sessionProvider.select((s) => s.role)));

final isWaliProvider =
    Provider<bool>((ref) => ref.watch(teacherRoleProvider) == TeacherRole.waliKelas);

final waliBannerProvider = Provider<String?>((ref) {
  if (!ref.watch(isWaliProvider)) return null;
  final cls = ref.watch(selectedClassProvider);
  return 'Mode lihat · Wali Kelas $cls. Input absensi dan nilai dilakukan oleh Guru Mapel.';
});

final myClassesProvider =
    Provider<List<String>>((ref) => ref.watch(sessionProvider.select((s) => s.classes)));

class ActiveTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final activeTabProvider =
    NotifierProvider<ActiveTabNotifier, int>(ActiveTabNotifier.new);

class SelectedClassNotifier extends Notifier<String> {
  @override
  String build() => '';

  void select(String code) => state = code;
}

final selectedClassProvider =
    NotifierProvider<SelectedClassNotifier, String>(SelectedClassNotifier.new);

class LoadingNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void pulse(Duration duration) {
    _timer?.cancel();
    state = true;
    _timer = Timer(duration, () => state = false);
  }

  void stop() {
    _timer?.cancel();
    state = false;
  }
}

class SearchQueryNotifier extends Notifier<String> {
  SearchQueryNotifier(this.scope);
  final String scope;

  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider.autoDispose
    .family<SearchQueryNotifier, String, String>(SearchQueryNotifier.new);

class FilterNotifier extends Notifier<String> {
  FilterNotifier(this.scope);
  final String scope;

  @override
  String build() => 'all';

  void set(String filter) => state = filter;
}

final filterProvider = NotifierProvider.autoDispose
    .family<FilterNotifier, String, String>(FilterNotifier.new);

class CameraPermissionNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void grant() => state = true;
}

final cameraPermissionProvider =
    NotifierProvider<CameraPermissionNotifier, bool>(CameraPermissionNotifier.new);

Future<String?> _guard(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } on ApiException catch (e) {
    return e.message;
  }
}

class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    return ref.watch(guruRepositoryProvider).fetchNotifications();
  }

  Future<String?> markRead(int id) async {
    final previous = state.value;
    if (previous == null) return null;
    state = AsyncData([
      for (final n in previous) n.id == id ? n.copyWith(read: true) : n,
    ]);
    final error = await _guard(() => ref.read(guruRepositoryProvider).markNotificationRead(id));
    if (error != null) state = AsyncData(previous);
    return error;
  }

  Future<String?> markAllRead() async {
    final previous = state.value;
    if (previous == null) return null;
    state = AsyncData([for (final n in previous) n.copyWith(read: true)]);
    final error = await _guard(() => ref.read(guruRepositoryProvider).markAllNotificationsRead());
    if (error != null) state = AsyncData(previous);
    return error;
  }
}

final notificationsAsyncProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(
        NotificationsNotifier.new);

final notificationsProvider = Provider<List<AppNotification>>(
    (ref) => ref.watch(notificationsAsyncProvider).value ?? const []);

final hasUnreadNotificationsProvider = Provider<bool>(
    (ref) => ref.watch(notificationsProvider).any((n) => !n.read));

final activitiesAsyncProvider = FutureProvider<List<ActivityItem>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(guruRepositoryProvider).fetchActivities();
});

final activitiesProvider = Provider<List<ActivityItem>>(
    (ref) => ref.watch(activitiesAsyncProvider).value ?? const []);

final classSummariesProvider = FutureProvider<List<ClassInfo>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final all = await ref.watch(guruRepositoryProvider).fetchClassSummaries();
  final mine = ref.watch(myClassesProvider).toSet();
  return [
    for (final c in all)
      if (mine.contains(c.code)) c,
  ];
});

final classSummaryMapProvider = Provider<Map<String, ClassInfo>>((ref) => {
      for (final c in ref.watch(classSummariesProvider).value ?? const <ClassInfo>[]) c.code: c,
    });

class ClassDataNotifier extends AsyncNotifier<ClassData> {
  ClassDataNotifier(this.classCode);

  final String classCode;

  GuruRepository get _repo => ref.read(guruRepositoryProvider);

  @override
  Future<ClassData> build() async {
    if (ref.watch(currentUserIdProvider) == null || classCode.isEmpty) return ClassData.empty;
    return ref.watch(guruRepositoryProvider).fetchClassData(classCode);
  }

  Future<void> _reload() async {
    state = AsyncData(await _repo.fetchClassData(classCode));
    ref.invalidate(classSummariesProvider);
    ref.invalidate(activitiesAsyncProvider);
    ref.invalidate(notificationsAsyncProvider);
  }

  Future<String?> _mutate(Future<void> Function() action) =>
      _guard(() async {
        await action();
        await _reload();
      });

  Future<String?> setStatus(int studentId, AttendanceStatus status, {String note = ''}) =>
      _mutate(() => _repo.setAttendance(
            classCode: classCode,
            studentId: studentId,
            status: status,
            note: note,
          ));

  Future<FaceScanResult> scanFace(Uint8List image) async {
    final result = await _repo.recognizeFace(classCode: classCode, image: image);
    if (result is FaceMatched) await _reload();
    return result;
  }

  Future<String?> finishAttendance() => _mutate(() => _repo.finishAttendance(classCode));

  Future<String?> addGrade(GradeInput input) =>
      _mutate(() => _repo.createGrade(classCode, input));

  Future<String?> updateGrade(int gradeId, GradeInput input) =>
      _mutate(() => _repo.updateGrade(gradeId, input));

  Future<String?> deleteGrade(int gradeId) => _mutate(() => _repo.deleteGrade(gradeId));

  Future<void> refresh() async {
    try {
      await _reload();
    } on ApiException catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final classDataAsyncProvider =
    AsyncNotifierProvider.family<ClassDataNotifier, ClassData, String>(ClassDataNotifier.new);

final currentClassAsyncProvider = Provider<AsyncValue<ClassData>>((ref) {
  final code = ref.watch(selectedClassProvider);
  if (code.isEmpty) return const AsyncData(ClassData.empty);
  return ref.watch(classDataAsyncProvider(code));
});

final currentClassDataProvider = Provider<ClassData>(
    (ref) => ref.watch(currentClassAsyncProvider).value ?? ClassData.empty);

final studentsProvider = Provider<List<Student>>(
    (ref) => ref.watch(currentClassDataProvider).students);

final gradesProvider = Provider<List<GradeEntry>>(
    (ref) => ref.watch(currentClassDataProvider).grades);

final attendanceSummaryProvider = Provider<AttendanceSummary>(
    (ref) => AttendanceSummary.fromStudents(ref.watch(studentsProvider)));

final distributionProvider = Provider<ClassificationDistribution>(
    (ref) => ClassificationDistribution.fromStudents(ref.watch(studentsProvider)));

final decliningCountProvider = Provider<int>(
    (ref) => ref.watch(studentsProvider).where((s) => s.declining).length);

final averageProvider = Provider.family<int, SubjectCategory>(
    (ref, category) => ref.watch(currentClassDataProvider).averageOf(category));

typedef IndexedStudent = ({int index, Student student});

final attendanceListProvider = Provider.autoDispose<List<IndexedStudent>>((ref) {
  final query = ref.watch(searchQueryProvider(Scopes.attendance)).toLowerCase();
  final filter = ref.watch(filterProvider(Scopes.attendance));
  final students = ref.watch(studentsProvider);
  return [
    for (var i = 0; i < students.length; i++)
      if (students[i].name.toLowerCase().contains(query) &&
          (filter == 'all' || students[i].status.code == filter))
        (index: i, student: students[i]),
  ];
});

final studentListProvider = Provider.autoDispose<List<IndexedStudent>>((ref) {
  final query = ref.watch(searchQueryProvider(Scopes.students)).toLowerCase();
  final filter = ref.watch(filterProvider(Scopes.students));
  final students = ref.watch(studentsProvider);
  return [
    for (var i = 0; i < students.length; i++)
      if (students[i].name.toLowerCase().contains(query) &&
          (filter == 'all' || students[i].classification.code == filter))
        (index: i, student: students[i]),
  ];
});
