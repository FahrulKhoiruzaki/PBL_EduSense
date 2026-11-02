import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_overlays.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_dialogs.dart';
import 'guard_admin.dart';

Future<void> startAddAccount(BuildContext context, AccountType type) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final data = container.read(adminDatasetProvider);
  final notifier = container.read(adminDataProvider.notifier);

  void showCredentials(Credentials credentials, {bool classShortcut = false}) {
    if (!dialogContext.mounted) return;
    container.read(accountTabProvider.notifier).set(type);
    showCredentialDialog(
      dialogContext,
      email: credentials.email,
      password: credentials.password,
      onOpenClasses: classShortcut
          ? () => container.read(activeMenuProvider.notifier).select(AdminMenu.kelas)
          : null,
    );
  }

  if (type == AccountType.siswa) {
    if (data.classCodes.isEmpty) {
      AppToast.show('Buat kelas terlebih dahulu.');
      return Future.value();
    }
    return showAdminFormDialog(
      dialogContext,
      title: 'Tambah Siswa',
      subtitle: 'Akun orang tua dibuat otomatis untuk siswa ini.',
      submitLabel: 'Tambah Siswa',
      fields: [
        const AdminFormField(id: 'n', label: 'Nama siswa'),
        AdminFormField(
          id: 'k',
          label: 'Kelas',
          options: [for (final c in data.classCodes) (c, 'Kelas $c')],
        ),
        const AdminFormField(id: 'p', label: 'Nama orang tua/wali'),
      ],
      onSubmit: (v) async {
        final credentials = await guardAdmin(
          () => notifier.createSiswa(name: v['n']!, classCode: v['k']!, parent: v['p']!),
        );
        if (credentials != null) showCredentials(credentials);
      },
    );
  }

  final isGuru = type == AccountType.guru;
  return showAdminFormDialog(
    dialogContext,
    title: isGuru ? 'Tambah Akun Guru' : 'Tambah Akun Admin',
    submitLabel: 'Buat Akun',
    fields: [
      const AdminFormField(id: 'n', label: 'Nama lengkap'),
      AdminFormField(
        id: 'e',
        label: 'Email',
        isEmail: true,
        validator: (v, _) => container.read(adminDatasetProvider).emailTaken(v)
            ? 'Email sudah dipakai akun lain.'
            : null,
      ),
      if (isGuru)
        const AdminFormField(
          id: 'p',
          label: 'Peran awal',
          options: [('mapel', 'Guru Mapel'), ('wali', 'Wali Kelas')],
        ),
    ],
    onSubmit: (v) async {
      final credentials = await guardAdmin(
        () => isGuru
            ? notifier.createGuru(
                name: v['n']!,
                email: v['e']!,
                role: v['p'] == 'wali' ? GuruRole.wali : GuruRole.mapel,
              )
            : notifier.createAdmin(name: v['n']!, email: v['e']!),
      );
      if (credentials != null) showCredentials(credentials, classShortcut: isGuru);
    },
  );
}

Future<void> startEditAccount(BuildContext context, AccountType type, String id) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final data = container.read(adminDatasetProvider);
  final notifier = container.read(adminDataProvider.notifier);
  final account = data.accountById(type, id)!;

  if (account is Siswa) {
    return showAdminFormDialog(
      dialogContext,
      title: 'Edit Siswa',
      submitLabel: 'Simpan',
      fields: [
        AdminFormField(id: 'n', label: 'Nama siswa', initial: account.name),
        AdminFormField(
          id: 'k',
          label: 'Kelas',
          initial: account.classCode,
          options: [for (final c in data.classCodes) (c, 'Kelas $c')],
        ),
        AdminFormField(id: 'p', label: 'Nama orang tua/wali', initial: account.parentGivenName),
      ],
      onSubmit: (v) async {
        final done = await guardAdmin(() async {
          await notifier.updateSiswa(id, name: v['n']!, classCode: v['k']!, parent: v['p']!);
          return true;
        });
        if (done == true) AppToast.show('Data siswa berhasil diperbarui.');
      },
    );
  }

  return showAdminFormDialog(
    dialogContext,
    title: 'Edit Akun',
    submitLabel: 'Simpan',
    fields: [
      AdminFormField(id: 'n', label: 'Nama lengkap', initial: account.name),
      AdminFormField(
        id: 'e',
        label: 'Email',
        initial: account.email,
        isEmail: true,
        validator: (v, _) => container.read(adminDatasetProvider).emailTaken(v, exceptId: id)
            ? 'Email sudah dipakai akun lain.'
            : null,
      ),
    ],
    onSubmit: (v) async {
      final done = await guardAdmin(() async {
        await notifier.updateStaffAccount(type, id, name: v['n']!, email: v['e']!);
        return true;
      });
      if (done == true) AppToast.show('Akun berhasil diperbarui.');
    },
  );
}

Future<void> startResetPassword(BuildContext context, AccountType type, String id) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final account = container.read(adminDatasetProvider).accountById(type, id)!;

  return showAdminConfirm(
    dialogContext,
    title: 'Reset password ${account.name}?',
    description: 'Password sementara baru akan dibuat dan wajib diganti saat login berikutnya.',
    confirmLabel: 'Reset',
    destructive: false,
    onConfirm: () async {
      final credentials = await guardAdmin(
        () => container.read(adminDataProvider.notifier).resetPassword(type, id),
      );
      if (credentials == null || !dialogContext.mounted) return;
      showCredentialDialog(dialogContext, email: credentials.email, password: credentials.password);
    },
  );
}

Future<void> startToggleActive(BuildContext context, AccountType type, String id) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final account = container.read(adminDatasetProvider).accountById(type, id)!;

  Future<void> apply() async {
    final done = await guardAdmin(() async {
      await container.read(adminDataProvider.notifier).setActive(type, id, active: !account.active);
      return true;
    });
    if (done == true) {
      AppToast.show(account.active ? 'Akun dinonaktifkan.' : 'Akun diaktifkan.');
    }
  }

  if (!account.active) return apply();
  return showAdminConfirm(
    dialogContext,
    title: 'Nonaktifkan akun ${account.name}?',
    description: 'Pemilik akun tidak bisa masuk sampai diaktifkan kembali. Data tidak dihapus.',
    confirmLabel: 'Nonaktifkan',
    onConfirm: apply,
  );
}

Future<void> startDeleteAccount(BuildContext context, AccountType type, String id) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dialogContext = adminDialogContext(context);
  final account = container.read(adminDatasetProvider).accountById(type, id)!;

  final description = switch (type) {
    AccountType.siswa =>
      'Siswa dan akun orang tua (${account.email}) akan dihapus permanen beserta riwayatnya.',
    AccountType.guru =>
      'Akun dihapus dan penugasan wali/guru mapel ${account.name} dilepas dari semua kelas.',
    AccountType.adm => 'Akun admin ini dihapus permanen.',
  };

  return showAdminDeleteConfirm(
    dialogContext,
    title: 'Hapus ${account.name}?',
    description: description,
    onConfirm: () async {
      final done = await guardAdmin(() async {
        await container.read(adminDataProvider.notifier).deleteAccount(type, id);
        return true;
      });
      if (done == true) AppToast.show('Akun berhasil dihapus.');
    },
  );
}
