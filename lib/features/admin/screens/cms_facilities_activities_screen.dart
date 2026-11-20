import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../data/cms_models.dart';
import '../providers/cms_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class CmsFacilitiesActivitiesScreen extends ConsumerStatefulWidget {
  const CmsFacilitiesActivitiesScreen({super.key});

  @override
  ConsumerState<CmsFacilitiesActivitiesScreen> createState() =>
      _CmsFacilitiesActivitiesScreenState();
}

class _CmsFacilitiesActivitiesScreenState extends ConsumerState<CmsFacilitiesActivitiesScreen> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Kelola Fasilitas & Kegiatan'),
        AdminChipBar<int>(
          selected: _tab,
          onSelected: (v) => setState(() => _tab = v),
          options: const [(0, 'Fasilitas'), (1, 'Kegiatan & Galeri')],
        ),
        if (_tab == 0) const _FacilitiesPanel() else const _ActivitiesPanel(),
      ],
    );
  }
}

class _FacilitiesPanel extends ConsumerWidget {
  const _FacilitiesPanel();

  Future<void> _openForm(BuildContext context, {CmsFacility? existing}) {
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(cmsFacilitiesProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Fasilitas' : 'Edit Fasilitas',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsTextField('nama', 'Nama fasilitas', initial: existing?.nama ?? '', required: true),
        CmsTextField('deskripsi', 'Deskripsi', initial: existing?.deskripsi ?? '', lines: 3),
        CmsImageField('gambar_url', 'Gambar', initial: existing?.gambarUrl),
        CmsTextField(
          'urutan',
          'Urutan tampil',
          initial: existing == null ? '' : '${existing.urutan}',
          hint: 'Kosongkan agar ditaruh paling akhir',
          number: true,
        ),
        CmsToggleField('tampil', 'Tampilkan di website', initial: existing?.tampil ?? true),
      ],
      onSubmit: (v) async {
        final input = CmsFacilityInput(
          nama: v.text('nama'),
          deskripsi: v.text('deskripsi'),
          gambarUrl: v.image('gambar_url'),
          urutan: v.number('urutan'),
          tampil: v.flag('tampil'),
        );
        if (existing == null) {
          await notifier.create(input);
        } else {
          await notifier.edit(existing.id, input);
        }
        AppToast.show(existing == null ? 'Fasilitas ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CmsSection(
      title: 'Fasilitas Sekolah',
      action: CustomButton(label: '+ Tambah Fasilitas', onPressed: () => _openForm(context)),
      child: AsyncBody<List<CmsFacility>>(
        value: ref.watch(cmsFacilitiesProvider),
        onRetry: () => ref.invalidate(cmsFacilitiesProvider),
        builder: (items) {
          if (items.isEmpty) return const CmsEmpty('Belum ada fasilitas.');
          return AdminDataTable(
            columns: const [
              AdminColumn('Gambar', width: 80),
              AdminColumn('Nama', flex: 3),
              AdminColumn('Urutan', width: 80),
              AdminColumn('Tampil', width: 90),
              AdminColumn('Aksi', width: 130),
            ],
            rows: [
              for (final f in items)
                [
                  f.gambarUrl == null
                      ? const SizedBox(width: 44, height: 44)
                      : CmsThumb(f.gambarUrl!, size: 44),
                  Text(f.nama, style: context.styleBold),
                  Text('${f.urutan}', style: context.styleBody),
                  Text(f.tampil ? 'Ya' : 'Tidak', style: context.styleBody),
                  Row(
                    children: [
                      LinkText('Edit', onTap: () => _openForm(context, existing: f)),
                      const SizedBox(width: 14),
                      LinkText(
                        'Hapus',
                        onTap: () => cmsConfirmDelete(
                          context,
                          title: 'Hapus fasilitas "${f.nama}"?',
                          description: 'Fasilitas ini hilang dari website.',
                          onDelete: () => ref.read(cmsFacilitiesProvider.notifier).delete(f.id),
                        ),
                      ),
                    ],
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ActivitiesPanel extends ConsumerWidget {
  const _ActivitiesPanel();

  Future<void> _openForm(BuildContext context, {CmsActivity? existing}) {
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(cmsActivitiesProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Kegiatan' : 'Edit Kegiatan',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsTextField('judul', 'Judul kegiatan', initial: existing?.judul ?? '', required: true),
        CmsChoiceField(
          'kategori',
          'Kategori',
          initial: existing?.kategori ?? kActivityCategories.first,
          options: [for (final c in kActivityCategories) (c, c)],
        ),
        CmsDateField('tanggal', 'Tanggal kegiatan (kosong = hari ini)', initial: existing?.tanggal),
        CmsChoiceField(
          'status',
          'Status',
          initial: (existing?.status ?? ContentStatus.draft).code,
          options: [for (final s in ContentStatus.values) (s.code, s.label)],
        ),
        CmsTextField('deskripsi', 'Deskripsi', initial: existing?.deskripsi ?? '', lines: 6),
        CmsImagesField('foto_urls', 'Foto galeri', initial: existing?.fotoUrls ?? const []),
      ],
      onSubmit: (v) async {
        final input = CmsActivityInput(
          judul: v.text('judul'),
          kategori: v.choice('kategori'),
          tanggal: v.date('tanggal'),
          status: ContentStatus.from(v.choice('status')),
          deskripsi: v.text('deskripsi'),
          fotoUrls: v.images('foto_urls'),
        );
        if (existing == null) {
          await notifier.create(input);
        } else {
          await notifier.edit(existing.slug, input);
        }
        AppToast.show(existing == null ? 'Kegiatan ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CmsSection(
      title: 'Kegiatan & Galeri',
      action: CustomButton(label: '+ Tambah Kegiatan', onPressed: () => _openForm(context)),
      child: AsyncBody<List<CmsActivity>>(
        value: ref.watch(cmsActivitiesProvider),
        onRetry: () => ref.invalidate(cmsActivitiesProvider),
        builder: (items) {
          if (items.isEmpty) return const CmsEmpty('Belum ada kegiatan.');
          return AdminDataTable(
            columns: const [
              AdminColumn('Judul', flex: 3),
              AdminColumn('Kategori', width: 140),
              AdminColumn('Tanggal', width: 120),
              AdminColumn('Foto', width: 70),
              AdminColumn('Status', width: 100),
              AdminColumn('Aksi', width: 130),
            ],
            rows: [
              for (final a in items)
                [
                  Text(
                    a.judul,
                    style: context.styleBold,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(a.kategori, style: context.styleBody),
                  Text(formatDate(a.tanggal), style: context.styleBody),
                  Text('${a.fotoUrls.length}', style: context.styleBody),
                  cmsStatusBadge(a.status),
                  Row(
                    children: [
                      LinkText('Edit', onTap: () => _openForm(context, existing: a)),
                      const SizedBox(width: 14),
                      LinkText(
                        'Hapus',
                        onTap: () => cmsConfirmDelete(
                          context,
                          title: 'Hapus kegiatan "${a.judul}"?',
                          description: 'Kegiatan dan seluruh foto galerinya hilang dari website.',
                          onDelete: () => ref.read(cmsActivitiesProvider.notifier).delete(a.slug),
                        ),
                      ),
                    ],
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}
