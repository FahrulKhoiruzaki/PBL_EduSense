import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';
import '../widgets/parent_dialogs.dart';

class ParentProfileScreen extends ConsumerWidget {
  const ParentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kid = ref.watch(selectedKidProvider);

    final rows = <(String, Widget)>[
      ('Nama', Text(kid.nama, style: context.styleMedium)),
      ('Kelas', Text(kid.kelas, style: context.styleMedium)),
      ('NIS', Text(kid.nis ?? '—', style: context.styleMedium)),
      ('Wali kelas', Text(kid.waliKelas ?? '—', style: context.styleMedium)),
      ('Tahun ajaran', Text(kid.tahunAjaran ?? '—', style: context.styleMedium)),
      ('Klasifikasi saat ini', StatusBadge.classification(kid.klasifikasi)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ParentBackLink(
          '← Beranda',
          onTap: () => ref.read(activeTabProvider.notifier).back(),
        ),
        const ParentTitle('Profil Anak'),
        const SizedBox(height: 16),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: context.colors.mi),
                InfoRow(label: rows[i].$1, value: rows[i].$2, labelWidth: 150),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            'Data ini hanya bisa dilihat. Jika ada yang tidak sesuai, hubungi sekolah.',
            style: context.styleCaption.copyWith(fontSize: 13),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CustomButton(
            label: 'Data tidak sesuai? Hubungi sekolah via WhatsApp',
            onPressed: () => showParentWhatsAppDialog(
              context,
              childName: kid.nama,
              className: kid.kelas,
            ),
          ),
        ),
      ],
    );
  }
}
