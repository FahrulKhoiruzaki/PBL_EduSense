import 'package:flutter/foundation.dart';

enum AccountType { guru, siswa, adm }

enum GuruRole { wali, mapel }

enum LogType {
  kelas('Kelas'),
  akun('Akun'),
  siswa('Siswa'),
  sistem('Sistem');

  const LogType(this.label);
  final String label;
}

@immutable
abstract class AdminAccount {
  const AdminAccount({
    required this.id,
    required this.name,
    required this.email,
    this.active = true,
    this.mustChangePassword = false,
  });

  final String id;
  final String name;
  final String email;
  final bool active;
  final bool mustChangePassword;
}

@immutable
class Guru extends AdminAccount {
  const Guru({
    required super.id,
    required super.name,
    required super.email,
    required this.role,
    super.active,
    super.mustChangePassword,
  });

  final GuruRole role;
}

@immutable
class Siswa extends AdminAccount {
  const Siswa({
    required super.id,
    required super.name,
    required super.email,
    required this.classCode,
    required this.parentName,
    super.active,
    super.mustChangePassword,
  });

  final String classCode;
  final String parentName;

  String get parentGivenName => parentName.replaceFirst('Orang tua ', '');
}

@immutable
class AdminUser extends AdminAccount {
  const AdminUser({
    required super.id,
    required super.name,
    required super.email,
    super.active,
    super.mustChangePassword,
  });
}

/// Penugasan guru mengajar satu mapel di satu kelas. [subjectId] null = penugasan lama tanpa
/// mapel: guru boleh mencatat absensi tetapi belum boleh memasukkan nilai.
@immutable
class MapelAssignment {
  const MapelAssignment({required this.guruId, this.subjectId, this.subjectName});

  final String guruId;
  final int? subjectId;
  final String? subjectName;
}

@immutable
class Kelas {
  const Kelas({
    required this.code,
    this.waliId,
    this.mapelIds = const [],
    this.assignments = const [],
  });

  final String code;
  final String? waliId;

  /// Guru mapel (unik) di kelas ini.
  final List<String> mapelIds;
  final List<MapelAssignment> assignments;

  /// Jenjang kelas dari kodenya ('5A' -> 5).
  int get level => int.tryParse(code.isEmpty ? '' : code[0]) ?? 0;

  List<MapelAssignment> get displayAssignments => assignments.isNotEmpty
      ? assignments
      : [for (final id in mapelIds) MapelAssignment(guruId: id)];
}

@immutable
class LogAktivitas {
  const LogAktivitas({required this.time, required this.type, required this.message});

  final DateTime time;
  final LogType type;
  final String message;
}

typedef GuruAssignment = ({List<String> wali, List<String> mapel});

@immutable
class AdminDataset {
  const AdminDataset({
    required this.guru,
    required this.siswa,
    required this.admins,
    required this.classes,
    required this.log,
    required this.academicYear,
    required this.lateLimit,
    this.activePeriod,
  });

  static const empty = AdminDataset(
    guru: [],
    siswa: [],
    admins: [],
    classes: {},
    log: [],
    academicYear: '',
    lateLimit: '',
  );

  final List<Guru> guru;
  final List<Siswa> siswa;
  final List<AdminUser> admins;
  final Map<String, Kelas> classes;
  final List<LogAktivitas> log;
  final String academicYear;
  final String lateLimit;

  /// Label periode akademik aktif; bila ada, tahun ajaran mengikuti periode ini.
  final String? activePeriod;

  List<String> get classCodes => classes.keys.toList()..sort();

  List<AdminAccount> get allAccounts => [...guru, ...siswa, ...admins];

  Guru? guruById(String? id) {
    if (id == null) return null;
    for (final g in guru) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<Siswa> studentsOf(String classCode) => siswa.where((s) => s.classCode == classCode).toList();

  GuruAssignment assignmentOf(String guruId) => (
    wali: [
      for (final code in classCodes)
        if (classes[code]!.waliId == guruId) code,
    ],
    mapel: [
      for (final code in classCodes)
        if (classes[code]!.mapelIds.contains(guruId)) code,
    ],
  );

  AdminAccount? accountById(AccountType type, String id) {
    final source = switch (type) {
      AccountType.guru => guru,
      AccountType.siswa => siswa,
      AccountType.adm => admins,
    };
    for (final a in source) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool emailTaken(String email, {String? exceptId}) {
    final target = email.toLowerCase();
    return allAccounts.any((a) => a.email.toLowerCase() == target && a.id != exceptId);
  }
}
