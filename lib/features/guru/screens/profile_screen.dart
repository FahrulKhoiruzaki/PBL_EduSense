import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final classes = ref.watch(myClassesProvider);
    final summaries = ref.watch(classSummaryMapProvider);

    return ScreenScaffold(
      title: 'Profil Guru',
      children: [
        CustomCard(
          child: Column(
            children: [
              Avatar(name: session.displayName, size: 64, fontSize: 20),
              const SizedBox(height: 8),
              Text(session.displayName, style: context.styleH2),
              Text(session.contactEmail, style: context.styleMuted),
              const SizedBox(height: 8),
              StatusBadge(
                label: session.isWali
                    ? 'Wali Kelas ${ref.watch(selectedClassProvider)}'
                    : 'Guru Mapel',
              ),
              const SizedBox(height: 4),
              Text('NIP: ${session.user?.nip ?? '—'}', style: context.styleCaption),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Kelas yang diampu'),
              RowList(
                children: [
                  for (final code in classes)
                    NavRow(
                      title: 'Kelas $code',
                      subtitle: summaries[code] == null
                          ? null
                          : '${summaries[code]!.studentCount} siswa',
                      onTap: () {
                        ref.read(selectedClassProvider.notifier).select(code);
                        AppToast.show('Kelas aktif: $code');
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Pengaturan'),
              RowList(
                children: [
                  NavRow(
                    title: 'Batas jam terlambat',
                    subtitle: session.lateLimit == null
                        ? 'Belum diatur'
                        : 'Pukul ${session.lateLimit}',
                    onTap: () => AppToast.show('Diatur oleh sekolah.'),
                  ),
                  NavRow(
                    title: 'Persetujuan data wajah',
                    subtitle: 'Wajah hanya dipakai untuk identitas dan absensi',
                    onTap: () => AppToast.show('Informasi dikelola sekolah.'),
                  ),
                ],
              ),
            ],
          ),
        ),
        CustomButton(
          label: 'Keluar',
          variant: ButtonVariant.danger,
          expanded: true,
          onPressed: () => showConfirmDialog(
            context,
            message: 'Apakah Anda yakin ingin keluar?',
            confirmLabel: 'Keluar',
            onConfirm: () {
              AppToast.show('Anda telah keluar');
              ref.read(sessionProvider.notifier).signOut();
            },
          ),
        ),
      ],
    );
  }
}
