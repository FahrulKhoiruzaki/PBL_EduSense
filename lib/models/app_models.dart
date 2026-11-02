import 'package:flutter/foundation.dart';

enum TeacherRole { waliKelas, guruMapel }

enum AttendanceStatus {
  hadir('H', 'Hadir'),
  terlambat('T', 'Terlambat'),
  izin('I', 'Izin'),
  sakit('S', 'Sakit'),
  alpa('A', 'Alpa');

  const AttendanceStatus(this.code, this.label);
  final String code;
  final String label;

  bool get isPresent => this == hadir || this == terlambat;
}

enum Classification {
  mahir('M', 'Mahir'),
  cukup('C', 'Cukup'),
  perlu('P', 'Perlu Pendampingan');

  const Classification(this.code, this.label);
  final String code;
  final String label;
}

enum SubjectCategory {
  literasi('Literasi'),
  numerasi('Numerasi');

  const SubjectCategory(this.label);
  final String label;
}

enum NotificationGroup {
  today('Hari ini'),
  earlier('Sebelumnya');

  const NotificationGroup(this.label);
  final String label;
}

enum AppRoute { attendanceClass, gradeDetail, needAttention, stats, grades }

@immutable
class NavTarget {
  const NavTarget(this.route, {this.arg});
  final AppRoute route;
  final int? arg;
}

@immutable
class ClassInfo {
  const ClassInfo({
    required this.code,
    required this.studentCount,
    required this.attendancePercent,
  });

  final String code;
  final int studentCount;
  final int attendancePercent;
}

@immutable
class Student {
  const Student({
    required this.id,
    required this.name,
    required this.classification,
    required this.status,
    required this.literasi,
    required this.numerasi,
    this.time = '',
    this.declining = false,
  });

  final int id;
  final String name;
  final Classification classification;
  final AttendanceStatus status;
  final String time;
  final int literasi;
  final int numerasi;
  final bool declining;

  Student copyWith({AttendanceStatus? status, String? time}) => Student(
        id: id,
        name: name,
        classification: classification,
        status: status ?? this.status,
        time: time ?? this.time,
        literasi: literasi,
        numerasi: numerasi,
        declining: declining,
      );
}

@immutable
class GradeEntry {
  const GradeEntry({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.category,
    required this.assessment,
    required this.value,
    required this.previous,
    required this.date,
    required this.note,
  });

  final int id;
  final int studentId;
  final String studentName;
  final SubjectCategory category;
  final String assessment;
  final int value;
  final int previous;
  final DateTime date;
  final String note;
}

@immutable
class ClassData {
  const ClassData({
    required this.students,
    required this.grades,
    required this.averageLiterasi,
    required this.averageNumerasi,
    required this.literasiTrend,
    required this.numerasiTrend,
    required this.attendanceTrend,
  });

  static const empty = ClassData(
    students: [],
    grades: [],
    averageLiterasi: 0,
    averageNumerasi: 0,
    literasiTrend: [],
    numerasiTrend: [],
    attendanceTrend: [],
  );

  final List<Student> students;
  final List<GradeEntry> grades;
  final int averageLiterasi;
  final int averageNumerasi;
  final List<int> literasiTrend;
  final List<int> numerasiTrend;
  final List<int> attendanceTrend;

  int averageOf(SubjectCategory category) =>
      category == SubjectCategory.literasi ? averageLiterasi : averageNumerasi;
}

@immutable
class AttendanceSummary {
  const AttendanceSummary({
    required this.total,
    required this.counts,
    required this.percent,
  });

  factory AttendanceSummary.fromStudents(List<Student> students) {
    final counts = {for (final s in AttendanceStatus.values) s: 0};
    for (final s in students) {
      counts[s.status] = counts[s.status]! + 1;
    }
    final present =
        counts[AttendanceStatus.hadir]! + counts[AttendanceStatus.terlambat]!;
    final total = students.length;
    return AttendanceSummary(
      total: total,
      counts: counts,
      percent: total == 0 ? 0 : (present / total * 100).round(),
    );
  }

  final int total;
  final Map<AttendanceStatus, int> counts;
  final int percent;

  int countOf(AttendanceStatus s) => counts[s]!;
  int get present =>
      countOf(AttendanceStatus.hadir) + countOf(AttendanceStatus.terlambat);
  int get absent => total - present;
}

@immutable
class ClassificationDistribution {
  const ClassificationDistribution(this.counts);

  factory ClassificationDistribution.fromStudents(List<Student> students) {
    final counts = {for (final k in Classification.values) k: 0};
    for (final s in students) {
      counts[s.classification] = counts[s.classification]! + 1;
    }
    return ClassificationDistribution(counts);
  }

  final Map<Classification, int> counts;
  int countOf(Classification k) => counts[k]!;
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.group,
    required this.target,
    this.read = false,
  });

  final int id;
  final String title;
  final NotificationGroup group;
  final NavTarget target;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        group: group,
        target: target,
        read: read ?? this.read,
      );
}

@immutable
class ActivityItem {
  const ActivityItem({
    required this.title,
    required this.when,
    required this.target,
  });

  final String title;
  final String when;
  final NavTarget target;
}

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.mustChangePassword,
    this.nip,
  });

  final int id;
  final String email;
  final String name;
  final bool mustChangePassword;
  final String? nip;
}

@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    required this.waliClasses,
    required this.mapelClasses,
    this.lateLimit,
  });

  final String token;
  final AuthUser user;
  final List<String> waliClasses;
  final List<String> mapelClasses;
  final String? lateLimit;

  List<String> classesFor(TeacherRole role) {
    final list = role == TeacherRole.waliKelas ? waliClasses : mapelClasses;
    return [...list]..sort();
  }
}

sealed class FaceScanResult {
  const FaceScanResult();
}

class FaceMatched extends FaceScanResult {
  const FaceMatched({required this.studentId, required this.studentName, required this.time});

  final int studentId;
  final String studentName;
  final String time;
}

class FaceDuplicate extends FaceScanResult {
  const FaceDuplicate({required this.studentName, required this.time});

  final String studentName;
  final String time;
}

class FaceNotRecognized extends FaceScanResult {
  const FaceNotRecognized();
}

class FaceOtherClass extends FaceScanResult {
  const FaceOtherClass();
}
