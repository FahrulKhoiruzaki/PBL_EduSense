import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class InformationSection extends ConsumerWidget {
  const InformationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = ref.watch(newsDetailSlugProvider);
    return slug == null ? const _NewsList() : _NewsDetail(slug: slug);
  }
}

class _NewsList extends ConsumerWidget {
  const _NewsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(newsCategoryProvider);
    final order = ref.watch(newsOrderProvider);
    final items = ref.watch(filteredNewsProvider);

    return WebPage(
      title: 'Informasi',
      children: [
        WebSearchField(provider: newsSearchQueryProvider, hint: 'Cari informasi'),
        WebChipBar<BeritaKategori?>(
          options: [
            (null, 'Semua'),
            for (final k in BeritaKategori.values) (k, k.label),
          ],
          selected: category,
          onSelected: (v) => ref.read(newsCategoryProvider.notifier).set(v),
          trailing: WebDropdown<NewsOrder>(
            semanticLabel: 'Urutan',
            value: order,
            items: NewsOrder.values,
            itemLabel: (o) => o.label,
            onChanged: (v) => ref.read(newsOrderProvider.notifier).set(v),
          ),
        ),
        AsyncBody<List<Berita>>(
          value: ref.watch(newsProvider),
          onRetry: () => ref.invalidate(newsProvider),
          loading: const LoadingList(count: 3, height: 260),
          builder: (all) {
            if (items.isEmpty) {
              return WebEmpty(
                all.isEmpty ? 'Belum ada informasi.' : 'Informasi tidak ditemukan.',
                action: all.isEmpty
                    ? null
                    : CustomButton(
                        label: 'Reset Filter',
                        variant: ButtonVariant.secondary,
                        onPressed: () => resetNewsFilters(ref),
                      ),
              );
            }
            return ResponsiveGrid(
              minItemWidth: 240,
              gap: 16,
              children: [for (final b in items) NewsCard(berita: b)],
            );
          },
        ),
      ],
    );
  }
}

class _NewsDetail extends ConsumerWidget {
  const _NewsDetail({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeNavProvider.notifier);

    return WebPage(
      children: [
        Breadcrumb([
          ('Beranda', () => nav.open(WebsiteNav.beranda)),
          ('Informasi', nav.closeDetail),
          ('Detail', null),
        ]),
        AsyncBody<Berita>(
          value: ref.watch(newsDetailProvider(slug)),
          onRetry: () => ref.invalidate(newsDetailProvider(slug)),
          loading: const LoadingList(count: 2, height: 220),
          builder: (berita) => _article(context, ref, berita),
        ),
      ],
    );
  }

  Widget _article(BuildContext context, WidgetRef ref, Berita berita) {
    final nav = ref.read(activeNavProvider.notifier);
    final related = [
      for (final b in ref.watch(newsProvider).value ?? const <Berita>[])
        if (b.slug != berita.slug) b,
    ].take(3).toList();
    final body = berita.isi.isNotEmpty ? berita.isi : berita.ringkasan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TagLabel(berita.kategori.label),
            Text(formatDateLong(berita.tanggal), style: context.webCap),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: Text(berita.judul, style: context.webDetailTitle),
        ),
        ImagePlaceholder(height: 340, imageUrl: berita.imageUrl),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(body.isEmpty ? kInfoUnavailable : body, style: context.webMuted),
          ),
        ),
        ButtonRow(
          top: 0,
          children: [
            CustomButton(
              label: 'Bagikan',
              variant: ButtonVariant.secondary,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: berita.judul));
                AppToast.show('Judul disalin.');
              },
            ),
            CustomButton(
              label: 'Kembali ke Informasi',
              variant: ButtonVariant.outline,
              onPressed: nav.closeDetail,
            ),
          ],
        ),
        if (related.isNotEmpty) ...[
          const SizedBox(height: 40),
          Text('Informasi Terkait', style: context.webH2),
          const SizedBox(height: 16),
          ResponsiveGrid(
            minItemWidth: 240,
            gap: 16,
            children: [for (final b in related) NewsCard(berita: b)],
          ),
        ],
      ],
    );
  }
}
