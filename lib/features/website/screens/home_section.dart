import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class HomeSection extends ConsumerWidget {
  const HomeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeNavProvider.notifier);
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(top: 72, bottom: 56),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.su, c.fo],
            ),
          ),
          child: WebContainer(
            // WebContainer memusatkan anaknya dengan Center, sehingga Column menyusut selebar
            // anak terlebar lalu tampak di tengah. Lebar penuh menjaga tepi kiri sejajar dengan foto.
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageText('hero-kicker', style: context.webCap, hideIfMissing: true),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) => PageText(
                      'hero-title',
                      style: context.webH1,
                      fallback: ref.watch(schoolInfoValueProvider).nama,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: PageText(
                      'hero-subtitle',
                      style: context.webMuted.copyWith(fontSize: 19, height: 30 / 19),
                      hideIfMissing: true,
                    ),
                  ),
                  ButtonRow(
                    children: [
                      CustomButton(
                        label: 'Tentang Sekolah',
                        onPressed: () => nav.open(WebsiteNav.profil),
                      ),
                      CustomButton(
                        label: 'Informasi PPDB',
                        variant: ButtonVariant.secondary,
                        onPressed: () => nav.open(WebsiteNav.ppdb),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const _SchoolPhoto(),
        WebSection(
          child: ResponsiveGrid(
            minItemWidth: 300,
            gap: 32,
            equalHeight: false,
            children: [
              _IntroBlock(
                title: 'Sambutan Sekolah',
                pageKey: 'sambutan',
                buttonLabel: 'Selengkapnya',
                onPressed: () => nav.openProfil(ProfilSection.kepalaSekolah),
              ),
              _IntroBlock(
                title: 'Tentang Sekolah',
                pageKey: 'tentang',
                buttonLabel: 'Kenali Sekolah Kami',
                onPressed: () => nav.open(WebsiteNav.profil),
              ),
            ],
          ),
        ),
        _AsyncSection<Berita>(
          title: 'Informasi Terbaru',
          linkLabel: 'Lihat Semua Informasi',
          onLink: () => nav.open(WebsiteNav.informasi),
          value: ref.watch(newsProvider),
          onRetry: () => ref.invalidate(newsProvider),
          builder: (items) {
            final latest = [...items]..sort((a, b) => b.tanggal.compareTo(a.tanggal));
            return ResponsiveGrid(
              minItemWidth: 240,
              gap: 16,
              children: [for (final b in latest.take(4)) NewsCard(berita: b)],
            );
          },
        ),
        _AsyncSection<Kegiatan>(
          title: 'Kegiatan Sekolah',
          linkLabel: 'Lihat Semua Kegiatan',
          onLink: () => nav.open(WebsiteNav.kegiatan),
          value: ref.watch(activitiesProvider),
          onRetry: () => ref.invalidate(activitiesProvider),
          builder: (items) => _ActivityTiles(items: items.take(5).toList()),
        ),
        _AsyncSection<Fasilitas>(
          title: 'Fasilitas',
          linkLabel: 'Lihat Fasilitas',
          onLink: () => nav.open(WebsiteNav.fasilitas),
          value: ref.watch(facilitiesProvider),
          onRetry: () => ref.invalidate(facilitiesProvider),
          builder: (items) => ResponsiveGrid(
            minItemWidth: 240,
            gap: 16,
            children: [
              for (final f in items.take(4))
                CustomCard(
                  margin: EdgeInsets.zero,
                  onTap: () => nav.open(WebsiteNav.fasilitas),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ImagePlaceholder(height: 140, imageUrl: f.imageUrl),
                      const SizedBox(height: 12),
                      Text(f.nama, style: context.webH3),
                    ],
                  ),
                ),
            ],
          ),
        ),
        WebSection(
          topPadding: false,
          child: DarkPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PPDB', style: context.webCap.copyWith(color: AppColors.onDarkCardMuted)),
                const SizedBox(height: 8),
                Text(
                  'Penerimaan Peserta Didik Baru',
                  style: context.webH2.copyWith(color: AppColors.onDarkCard),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: PageText(
                    'ppdb-banner',
                    style: context.webBody.copyWith(color: AppColors.onDarkCardMuted),
                    hideIfMissing: true,
                  ),
                ),
                ButtonRow(
                  children: [
                    CustomButton(
                      label: 'Lihat Informasi PPDB',
                      onDark: true,
                      onPressed: () => nav.open(WebsiteNav.ppdb),
                    ),
                    const WhatsAppButton(
                      label: 'Hubungi Admin',
                      topic: WhatsAppTopic.ppdb,
                      variant: ButtonVariant.outline,
                      onDark: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _AsyncSection<Faq>(
          title: 'Pertanyaan Umum',
          linkLabel: 'Lihat Semua FAQ',
          onLink: () => nav.open(WebsiteNav.faq),
          value: ref.watch(faqProvider),
          onRetry: () => ref.invalidate(faqProvider),
          builder: (items) => FaqList(items.take(4).toList()),
        ),
        WebSection(
          topPadding: false,
          child: CustomCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
            child: Column(
              children: [
                Text(
                  'Ada pertanyaan tentang sekolah?',
                  textAlign: TextAlign.center,
                  style: context.webH2,
                ),
                const SizedBox(height: 12),
                PageText(
                  'kontak-ajakan',
                  style: context.webMuted,
                  hideIfMissing: true,
                  align: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const WhatsAppButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AsyncSection<T> extends StatelessWidget {
  const _AsyncSection({
    required this.title,
    required this.linkLabel,
    required this.onLink,
    required this.value,
    required this.onRetry,
    required this.builder,
  });

  final String title;
  final String linkLabel;
  final VoidCallback onLink;
  final AsyncValue<List<T>> value;
  final VoidCallback onRetry;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    Widget section(Widget body) => WebSection(
      topPadding: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, linkLabel: linkLabel, onLink: onLink),
          body,
        ],
      ),
    );

    return value.when(
      skipLoadingOnReload: true,
      data: (items) => items.isEmpty ? const SizedBox.shrink() : section(builder(items)),
      loading: () => section(const LoadingList(count: 2, height: 200)),
      error: (e, _) => section(ErrorRetry(error: e, onRetry: onRetry)),
    );
  }
}

class _IntroBlock extends StatelessWidget {
  const _IntroBlock({
    required this.title,
    required this.pageKey,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String pageKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.webH2),
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: PageText(pageKey)),
        CustomButton(label: buttonLabel, variant: ButtonVariant.outline, onPressed: onPressed),
      ],
    );
  }
}

class _ActivityTiles extends ConsumerWidget {
  const _ActivityTiles({required this.items});

  final List<Kegiatan> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tile(Kegiatan k, double height) => Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(activeNavProvider.notifier).openActivity(k.slug),
        child: ImagePlaceholder(height: height, label: k.judul, imageUrl: k.imageUrl),
      ),
    );

    if (items.length < 5) {
      return ResponsiveGrid(
        minItemWidth: 240,
        gap: 12,
        children: [for (final k in items) tile(k, 150)],
      );
    }

    Widget pair(Kegiatan a, Kegiatan b) => Row(
      children: [
        Expanded(child: tile(a, 150)),
        const SizedBox(width: 12),
        Expanded(child: tile(b, 150)),
      ],
    );

    final rest = Column(
      children: [pair(items[1], items[2]), const SizedBox(height: 12), pair(items[3], items[4])],
    );

    if (isNarrow(context)) {
      return Column(children: [tile(items[0], 312), const SizedBox(height: 12), rest]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: tile(items[0], 312)),
        const SizedBox(width: 12),
        Expanded(child: rest),
      ],
    );
  }
}

/// Foto sekolah besar tepat di bawah hero. Placeholder hanya tampil selama admin belum
/// mengunggah foto atau bila foto gagal dimuat.
class _SchoolPhoto extends ConsumerWidget {
  const _SchoolPhoto();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolInfoValueProvider);
    return WebSection(
      topPadding: false,
      bottomPadding: false,
      child: LayoutBuilder(
        builder: (context, box) {
          // Lebar penuh: layar sempit lebih tinggi (4:3), layar lebar lebih lebar (16:7).
          final ratio = box.maxWidth < 560 ? 4 / 3 : 16 / 7;
          final height = (box.maxWidth / ratio).clamp(180.0, 560.0);
          return Semantics(
            image: true,
            label: 'Foto ${school.nama}',
            child: ImagePlaceholder(
              height: height,
              label: 'Foto sekolah belum diunggah',
              imageUrl: school.fotoUrl,
            ),
          );
        },
      ),
    );
  }
}
