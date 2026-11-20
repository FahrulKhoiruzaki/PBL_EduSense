import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/theme.dart';
import '../../../widgets/sidebar_parts.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import 'website_cards.dart';
import 'website_common.dart';

class WebsiteFooter extends ConsumerWidget {
  const WebsiteFooter({super.key, required this.onBackToTop});

  final VoidCallback onBackToTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final nav = ref.read(activeNavProvider.notifier);
    final info = ref.watch(schoolInfoValueProvider);
    final year = ref.watch(todayProvider).year;

    final lines = <String>[
      info.kota,
      if (info.alamat != null) 'Alamat: ${info.alamat}',
      if (info.telepon != null) 'Telepon: ${info.telepon}',
      if (info.email != null) 'Email: ${info.email}',
      if (info.mediaSosial != null) 'Media sosial: ${info.mediaSosial}',
    ];

    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarLogo(title: info.nama),
        const SizedBox(height: 12),
        Text(lines.join('\n'), style: context.webCap),
      ],
    );

    final navigation = _FooterColumn('Navigasi', [
      for (final n in WebsiteNav.values.take(5)) (n.label, () => nav.open(n)),
    ]);

    final information = _FooterColumn('Informasi', [
      ('PPDB', () => nav.open(WebsiteNav.ppdb)),
      ('FAQ', () => nav.open(WebsiteNav.faq)),
      ('Kontak', () => nav.open(WebsiteNav.kontak)),
      ('Login Orang Tua', () => openParentLogin(context)),
    ]);

    final others = _FooterColumn('Lainnya', [
      ('Fasilitas', () => nav.open(WebsiteNav.fasilitas)),
      ('Pengaduan', () => nav.open(WebsiteNav.kontak)),
      ('Login Admin', () => openAdminLogin(context)),
      (
        'Kembali ke atas',
        () {
          nav.open(WebsiteNav.beranda);
          onBackToTop();
        },
      ),
    ]);

    return Container(
      margin: const EdgeInsets.only(top: 64),
      padding: const EdgeInsets.only(top: 48, bottom: 24),
      decoration: BoxDecoration(
        color: c.su,
        border: Border(top: BorderSide(color: c.mi)),
      ),
      child: WebContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrow(context)) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: about), const SizedBox(width: 32), Expanded(child: navigation)],
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: information), const SizedBox(width: 32), Expanded(child: others)],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: about),
                  const SizedBox(width: 32),
                  Expanded(child: navigation),
                  const SizedBox(width: 32),
                  Expanded(child: information),
                  const SizedBox(width: 32),
                  Expanded(child: others),
                ],
              ),
            const SizedBox(height: 32),
            Text(
              '© $year ${info.nama} Kota ${info.kota}.',
              style: context.webCap,
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn(this.title, this.links);

  final String title;
  final List<(String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.webBody.copyWith(fontWeight: FontWeight.w700)),
        for (final (label, onTap) in links)
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(label, style: context.webMuted),
            ),
          ),
      ],
    );
  }
}
