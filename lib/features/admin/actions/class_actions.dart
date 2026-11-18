import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/academic_models.dart';
import '../../../widgets/app_overlays.dart';
import '../data/admin_models.dart';
import '../providers/academic_providers.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_dialogs.dart';
import 'guard_admin.dart';

Future<void> startAddClass(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);

  return showAdminFormDialog(
    dialogContext,
    title: 'Tambah Kelas',
    submitLabel: 'Tambah Kelas',
    fields: [
      AdminFormField(
        id: 'k',
        label: 'Nama kelas',
        hint: 'Contoh: 5C',
        validator: (v, _) {
          final code = v.toUpperCase();
          if (!RegExp(r'^[1-6][A-Z]$').hasMatch(code)) return 'Gunakan format seperti 5C.';
          if (container.read(adminDatasetProvider).classes.containsKey(code)) {
            return 'Kelas sudah ada.';
          }
          return null;
        },
      ),
    ],
    onSubmit: (v) async {
      final code = v['k']!.toUpperCase();
      final done = await guardAdmin(() async {
        await container.read(adminDataProvider.notifier).addClass(code);
        return true;
      });
      if (done != true) return;
      AppToast.show('Kelas $code berhasil dibuat.');
      container.read(activeMenuProvider.notifier).openClass(code);
    },
  );
}

Future<void> startDeleteClass(BuildContext context, String code) {
  final container = ProviderScope.containerOf(context, listen: false);

  return showAdminConfirm(
    adminDialogContext(context),
    title: 'Hapus Kelas $code?',
    description: 'Kelas kosong ini akan dihapus. Wali kelas dan guru mapel dilepas dari kelas ini.',
    confirmLabel: 'Hapus Kelas',
    onConfirm: () async {
      final done = await guardAdmin(() async {
        await container.read(adminDataProvider.notifier).deleteClass(code);
        return true;
      });
      if (done != true) return;
      AppToast.show('Kelas $code dihapus.');
      container.read(activeMenuProvider.notifier).closeClass();
    },
  );
}

Future<void> startSetWali(BuildContext context, String code) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final data = container.read(adminDatasetProvider);
  final notifier = container.read(adminDataProvider.notifier);

  final options = <(String, String)>[
    ('', 'Pilih guru…'),
    for (final g in data.guru)
      if (g.active)
        (
          g.id,
          () {
            final others = data.assignmentOf(g.id).wali.where((x) => x != code).toList();
            return others.isEmpty ? g.name : '${g.name} (wali ${others.join(', ')})';
          }(),
        ),
  ];

  return showAdminFormDialog(
    dialogContext,
    title: 'Wali Kelas $code',
    submitLabel: 'Simpan',
    fields: [
      AdminFormField(
        id: 'g',
        label: 'Pilih guru',
        initial: data.classes[code]?.waliId ?? '',
        options: options,
      ),
    ],
    onSubmit: (v) async {
      final guruId = v['g']!;
      final fresh = container.read(adminDatasetProvider);
      if (guruId == fresh.classes[code]?.waliId) return;

      Future<void> apply() async {
        final done = await guardAdmin(() async {
          await notifier.setWali(code, guruId);
          return true;
        });
        if (done == true) AppToast.show('Wali kelas $code diperbarui.');
      }

      final others = fresh.assignmentOf(guruId).wali.where((x) => x != code).toList();
      if (others.isEmpty) {
        await apply();
        return;
      }
      await showAdminConfirm(
        dialogContext,
        title: '${fresh.guruById(guruId)!.name} sudah menjadi wali kelas ${others.join(', ')}',
        description: 'Jika dilanjutkan, kelas ${others.join(', ')} tidak akan punya wali kelas.',
        confirmLabel: 'Lanjutkan',
        destructive: false,
        onConfirm: apply,
      );
    },
  );
}

/// Menugaskan guru mengajar satu mata pelajaran di kelas ini. Mapel menentukan hak input nilai:
/// guru hanya dapat memasukkan nilai untuk mapel yang ditugaskan kepadanya.
Future<void> startAddMapel(BuildContext context, String code) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final data = container.read(adminDatasetProvider);
  final notifier = container.read(adminDataProvider.notifier);
  final kelas = data.classes[code]!;

  final guruOptions = [
    for (final g in data.guru)
      if (g.active) (g.id, g.name),
  ];
  if (guruOptions.isEmpty) {
    AppToast.show('Belum ada akun guru aktif.');
    return;
  }
  final subjects = await guardAdmin(() => container.read(adminSubjectsProvider.future));
  if (subjects == null) return;
  final subjectOptions = [
    for (final s in subjects)
      if (s.active && s.levels.contains(kelas.level))
        ('${s.id}', s.type == SubjectType.muatanLokal ? '${s.name} (Muatan Lokal)' : s.name),
  ];
  if (subjectOptions.isEmpty) {
    AppToast.show('Belum ada mata pelajaran aktif untuk kelas ${kelas.level}. Tambahkan di menu Mata Pelajaran.');
    return;
  }
  final taken = {
    for (final a in kelas.displayAssignments)
      if (a.subjectId != null) '${a.guruId}:${a.subjectId}',
  };
  if (!dialogContext.mounted) return;

  await showAdminFormDialog(
    dialogContext,
    title: 'Tambah Guru Mapel · $code',
    subtitle: 'Guru dapat mencatat absensi kelas ini dan memasukkan nilai mapel yang dipilih.',
    submitLabel: 'Tambah',
    fields: [
      AdminFormField(id: 'g', label: 'Pilih guru', options: [('', 'Pilih guru…'), ...guruOptions]),
      AdminFormField(
        id: 'm',
        label: 'Mata pelajaran',
        options: [('', 'Pilih mata pelajaran…'), ...subjectOptions],
        validator: (value, values) => taken.contains('${values['g']}:$value')
            ? 'Guru ini sudah ditugaskan untuk mapel tersebut di kelas ini.'
            : null,
      ),
    ],
    onSubmit: (v) async {
      final guruId = v['g']!;
      final subjectId = int.parse(v['m']!);
      final done = await guardAdmin(() async {
        await notifier.addMapel(code, guruId, subjectId: subjectId);
        return true;
      });
      if (done != true) return;
      final name = container.read(adminDatasetProvider).guruById(guruId)?.name ?? 'Guru';
      final subject = subjectOptions.firstWhere((o) => o.$1 == '$subjectId').$2;
      AppToast.show('$name ditugaskan mengajar $subject di kelas $code.');
    },
  );
}

Future<void> startRemoveMapel(BuildContext context, String code, MapelAssignment assignment) {
  final container = ProviderScope.containerOf(context, listen: false);
  final name = container.read(adminDatasetProvider).guruById(assignment.guruId)?.name ?? 'Guru';
  final subject = assignment.subjectName;

  return showAdminConfirm(
    adminDialogContext(context),
    title: subject == null
        ? 'Lepas $name dari kelas $code?'
        : 'Lepas $name dari mapel $subject di kelas $code?',
    description: subject == null
        ? 'Guru ini tidak lagi bisa mengisi absensi dan nilai di kelas $code.'
        : 'Guru ini tidak lagi bisa memasukkan nilai $subject di kelas $code. Nilai yang sudah '
            'tercatat tetap tersimpan.',
    confirmLabel: 'Lepas',
    onConfirm: () async {
      final done = await guardAdmin(() async {
        await container
            .read(adminDataProvider.notifier)
            .removeMapel(code, assignment.guruId, subjectId: assignment.subjectId);
        return true;
      });
      if (done == true) AppToast.show('Penugasan dilepas.');
    },
  );
}

Future<void> startMoveStudents(BuildContext context, List<String> ids) {
  if (ids.isEmpty) return Future.value();
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final data = container.read(adminDatasetProvider);
  final notifier = container.read(adminDataProvider.notifier);
  final source = data.siswa.firstWhere((s) => s.id == ids.first).classCode;

  return showAdminFormDialog(
    dialogContext,
    title: 'Pindahkan ${ids.length} siswa',
    submitLabel: 'Lanjut',
    fields: [
      AdminFormField(
        id: 't',
        label: 'Kelas tujuan',
        options: [
          ('', 'Pilih kelas…'),
          for (final c in data.classCodes)
            if (c != source) (c, 'Kelas $c (${data.studentsOf(c).length} siswa)'),
        ],
      ),
    ],
    onSubmit: (v) async {
      final target = v['t']!;
      final names = [for (final id in ids) data.siswa.firstWhere((s) => s.id == id).name];
      final shown = names.take(5).join(', ');
      final rest = names.length > 5 ? ' dan ${names.length - 5} lainnya' : '';

      await showAdminConfirm(
        dialogContext,
        title: 'Pindahkan ${ids.length} siswa dari $source ke $target?',
        description: '$shown$rest. Riwayat nilai dan absensi ikut pindah.',
        confirmLabel: 'Pindahkan',
        destructive: false,
        onConfirm: () async {
          final done = await guardAdmin(() async {
            await notifier.moveStudents(ids, target);
            return true;
          });
          if (done != true) return;
          container.read(selectedStudentsProvider.notifier).clear();
          AppToast.show('${ids.length} siswa dipindahkan ke kelas $target.');
        },
      );
    },
  );
}
