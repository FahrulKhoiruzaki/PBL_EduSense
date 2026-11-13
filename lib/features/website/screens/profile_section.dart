import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_common.dart';

class ProfileSection extends ConsumerWidget {
  const ProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(selectedProfilSectionProvider);
    final nav = ref.read(activeNavProvider.notifier);

    final menu = _ProfileMenu(selected: section, onSelect: nav.openProfil);
    final content = _ProfileContent(section: section, onSelect: nav.openProfil);

    return WebPage(
      title: 'Profil Sekolah',
      children: [
        Breadcrumb([('Beranda', () => nav.open(WebsiteNav.beranda)), ('Profil Sekolah', null)]),
        if (isNarrow(context))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [menu, const SizedBox(height: 32), content],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 230, child: menu),
              const SizedBox(width: 32),
              Expanded(child: content),
            ],
          ),
      ],
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.selected, required this.onSelect});

  final ProfilSection selected;
  final ValueChanged<ProfilSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget item(ProfilSection s) => Padding(
          padding: const EdgeInsets.only(bottom: 2, right: 2),
          child: Material(
            color: s == selected ? c.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelect(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  s.label,
                  softWrap: !isNarrow(context),
                  style: context.webBody.copyWith(color: s == selected ? c.su : c.sl),
                ),
              ),
            ),
          ),
        );

    if (isNarrow(context)) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [for (final s in ProfilSection.values) item(s)]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final s in ProfilSection.values) item(s)],
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.section, required this.onSelect});

  final ProfilSection section;
  final ValueChanged<ProfilSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget body = switch (section) {
      ProfilSection.identitas => _identity(context, ref),
      ProfilSection.guru => _staff(context, ref),
      _ => CustomCard(margin: EdgeInsets.zero, child: PageText(section.pageKey)),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.label, style: context.webH2),
        const SizedBox(height: 16),
        body,
        ButtonRow(
          children: [
            CustomButton(
              label: '← ${section.previous.label}',
              variant: ButtonVariant.outline,
              onPressed: () => onSelect(section.previous),
            ),
            CustomButton(
              label: '${section.next.label} →',
              variant: ButtonVariant.outline,
              onPressed: () => onSelect(section.next),
            ),
            CustomButton(
              label: 'Hubungi Sekolah',
              variant: ButtonVariant.secondary,
              onPressed: () => ref.read(activeNavProvider.notifier).open(WebsiteNav.kontak),
            ),
          ],
        ),
      ],
    );
  }

  Widget _identity(BuildContext context, WidgetRef ref) {
    return AsyncBody<SchoolInfo>(
      value: ref.watch(schoolInfoProvider),
      onRetry: () => ref.invalidate(schoolInfoProvider),
      loading: const LoadingList(count: 1, height: 200),
      builder: (info) => CustomCard(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (label, value) in [
              ('Nama sekolah', info.nama),
              ('Kota', info.kota),
              ('NPSN', info.npsn ?? '—'),
              ('Alamat', info.alamat ?? '—'),
              ('Akreditasi', info.akreditasi ?? '—'),
            ])
              LabeledRow(label: label, value: value),
          ],
        ),
      ),
    );
  }

  Widget _staff(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<StaffMember>>(
      value: ref.watch(staffProvider),
      onRetry: () => ref.invalidate(staffProvider),
      loading: const LoadingList(count: 2, height: 180),
      builder: (items) => items.isEmpty
          ? const WebEmpty('Belum ada data guru dan tenaga kependidikan.')
          : ResponsiveGrid(
              minItemWidth: 240,
              gap: 16,
              children: [
                for (final s in items)
                  CustomCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ImagePlaceholder(height: 120, label: 'Foto', imageUrl: s.fotoUrl),
                        const SizedBox(height: 12),
                        Text(s.nama, style: context.webBody.copyWith(fontWeight: FontWeight.w700)),
                        if (s.jabatan.isNotEmpty) Text(s.jabatan, style: context.webCap),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
