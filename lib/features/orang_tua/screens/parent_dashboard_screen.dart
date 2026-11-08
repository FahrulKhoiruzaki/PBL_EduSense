import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/responsive_grid.dart';
import '../../../widgets/status_badge.dart';
import '../providers/parent_providers.dart';
import '../widgets/parent_common.dart';

class ParentDashboardScreen extends ConsumerWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kid = ref.watch(selectedKidProvider);
    final nav = ref.read(activeTabProvider.notifier);

    final lit = kid.trenLiterasi;
    final num = kid.trenNumerasi;
    final literasiTrend = lit.length > 1 && lit.last > lit.first ? 'meningkat' : 'stabil';
    final numerasiTrend =
        num.length < 2 || num.last >= num[num.length - 2] ? 'stabil' : 'perlu sedikit latihan';
    final attendanceLabel = kid.persenKehadiran >= 95 ? 'sangat baik' : 'cukup baik';

    final stats = <(String, String, ParentTab)>[
      ('Literasi', '${kid.literasi}', ParentTab.nilai),
      ('Numerasi', '${kid.numerasi}', ParentTab.nilai),
      ('Kehadiran', '${kid.persenKehadiran}%', ParentTab.hadir),
      ('Keterlambatan', '${kid.jumlahTerlambat} kali', ParentTab.hadir),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ParentTitle('Perkembangan Anak'),
        const SizedBox(height: 16),
        CustomCard(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kid.nama, style: context.styleH2.copyWith(fontSize: 20, height: 28 / 20)),
                    Text(
                      'Kelas ${kid.kelas}${kid.waliKelas == null ? '' : ' · Wali kelas ${kid.waliKelas}'}',
                      style: context.styleSoft,
                    ),
                  ],
                ),
              ),
              StatusBadge.classification(kid.klasifikasi),
              if (kid.diperbarui != null)
                Text(
                  'Diperbarui: ${formatDateLong(kid.diperbarui!)}',
                  style: context.styleCaption.copyWith(fontSize: 13),
                ),
            ],
          ),
        ),
        ResponsiveGrid(
          minItemWidth: 160,
          children: [
            for (final (label, value, target) in stats)
              CustomCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(18),
                onTap: () => nav.openTab(target),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kick(label),
                    Text(value, style: context.styleBig.copyWith(fontSize: 32, height: 44 / 40)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kick('Ringkasan perkembangan'),
              Text(
                '${kid.namaDepan} menunjukkan perkembangan yang baik. Nilai literasi $literasiTrend dalam beberapa penilaian terakhir, numerasi $numerasiTrend, dan kehadiran $attendanceLabel.',
                style: context.styleBody.copyWith(fontSize: 15, height: 22 / 15),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CustomButton(
                    label: 'Lihat Statistik',
                    onPressed: () => nav.openSubPage(ParentSubPage.statistik),
                  ),
                  CustomButton(
                    label: 'Lihat Riwayat',
                    variant: ButtonVariant.secondary,
                    onPressed: () => nav.openTab(ParentTab.riwayat),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  expandedAlignment: Alignment.centerLeft,
                  title: Text(
                    'Dasar penilaian klasifikasi',
                    style: context.styleBold.copyWith(fontWeight: FontWeight.w600),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Klasifikasi memakai nilai literasi, nilai numerasi, kehadiran, dan keterlambatan. Ini alat bantu bagi guru, bukan penilaian akhir.',
                        style: context.styleSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
