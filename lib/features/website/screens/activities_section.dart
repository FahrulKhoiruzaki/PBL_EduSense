import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class ActivitiesSection extends ConsumerWidget {
  const ActivitiesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = ref.watch(activityDetailSlugProvider);
    return slug == null ? const _ActivityGallery() : _ActivityDetail(slug: slug);
  }
}

class _ActivityGallery extends ConsumerWidget {
  const _ActivityGallery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(activityCategoryProvider);
    final items = ref.watch(filteredActivitiesProvider);

    return WebPage(
      title: 'Kegiatan',
      children: [
        WebChipBar<KegiatanKategori?>(
          options: [
            (null, 'Semua'),
            for (final k in KegiatanKategori.values) (k, k.label),
          ],
          selected: category,
          onSelected: (v) => ref.read(activityCategoryProvider.notifier).set(v),
        ),
        AsyncBody<List<Kegiatan>>(
          value: ref.watch(activitiesProvider),
          onRetry: () => ref.invalidate(activitiesProvider),
          loading: const LoadingList(count: 3, height: 260),
          builder: (_) => items.isEmpty
              ? const WebEmpty('Belum ada kegiatan pada kategori ini.')
              : ResponsiveGrid(
                  minItemWidth: 240,
                  gap: 16,
                  children: [for (final k in items) ActivityCard(kegiatan: k)],
                ),
        ),
      ],
    );
  }
}

class _ActivityDetail extends ConsumerWidget {
  const _ActivityDetail({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(activeNavProvider.notifier);

    return WebPage(
      children: [
        Breadcrumb([
          ('Beranda', () => nav.open(WebsiteNav.beranda)),
          ('Kegiatan', nav.closeDetail),
          ('Detail', null),
        ]),
        AsyncBody<Kegiatan>(
          value: ref.watch(activityDetailProvider(slug)),
          onRetry: () => ref.invalidate(activityDetailProvider(slug)),
          loading: const LoadingList(count: 2, height: 220),
          builder: (kegiatan) => _content(context, ref, kegiatan),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, Kegiatan kegiatan) {
    final nav = ref.read(activeNavProvider.notifier);
    final others = [
      for (final k in ref.watch(activitiesProvider).value ?? const <Kegiatan>[])
        if (k.slug != kegiatan.slug) k,
    ].take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TagLabel(kegiatan.kategori.label),
            Text(formatDateLong(kegiatan.tanggal), style: context.webCap),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          child: Text(kegiatan.judul, style: context.webDetailTitle),
        ),
        if (kegiatan.fotoUrls.isNotEmpty)
          ResponsiveGrid(
            minItemWidth: 240,
            gap: 16,
            children: [
              for (var i = 0; i < kegiatan.fotoUrls.length; i++)
                Semantics(
                  button: true,
                  label: 'Foto ${i + 1}',
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => showPhotoLightbox(context, kegiatan.fotoUrls, i),
                      child: ImagePlaceholder(
                        height: 200,
                        label: 'Foto ${i + 1}',
                        imageUrl: kegiatan.fotoUrls[i],
                      ),
                    ),
                  ),
                ),
            ],
          )
        else
          ImagePlaceholder(height: 260, imageUrl: kegiatan.imageUrl),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            kegiatan.deskripsi.isEmpty ? kInfoUnavailable : kegiatan.deskripsi,
            style: context.webMuted,
          ),
        ),
        ButtonRow(
          top: 0,
          children: [
            CustomButton(
              label: 'Kembali',
              variant: ButtonVariant.outline,
              onPressed: nav.closeDetail,
            ),
          ],
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 40),
          Text('Kegiatan Lainnya', style: context.webH2),
          const SizedBox(height: 16),
          ResponsiveGrid(
            minItemWidth: 240,
            gap: 16,
            children: [for (final k in others) ActivityCard(kegiatan: k)],
          ),
        ],
      ],
    );
  }
}
