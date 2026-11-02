import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../repositories/admin_repository.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../actions/guard_admin.dart';
import '../data/cms_models.dart';
import '../providers/cms_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class CmsPostsScreen extends ConsumerStatefulWidget {
  const CmsPostsScreen({super.key});

  @override
  ConsumerState<CmsPostsScreen> createState() => _CmsPostsScreenState();
}

class _CmsPostsScreenState extends ConsumerState<CmsPostsScreen> {
  ContentStatus? _status;
  String? _category;

  Future<void> _openForm({CmsPost? existing}) {
    final container = ProviderScope.containerOf(context, listen: false);
    final notifier = container.read(cmsPostsProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Berita / Pengumuman' : 'Edit Berita / Pengumuman',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsTextField('judul', 'Judul', initial: existing?.judul ?? '', required: true),
        CmsChoiceField(
          'kategori',
          'Kategori',
          initial: existing?.kategori ?? kPostCategories[1],
          options: [for (final c in kPostCategories) (c, c)],
        ),
        CmsDateField('tanggal', 'Tanggal terbit (kosong = hari ini)', initial: existing?.tanggal),
        CmsChoiceField(
          'status',
          'Status',
          initial: (existing?.status ?? ContentStatus.draft).code,
          options: [for (final s in ContentStatus.values) (s.code, s.label)],
        ),
        CmsTextField(
          'ringkasan',
          'Ringkasan',
          initial: existing?.ringkasan ?? '',
          lines: 2,
          hint: 'Kosongkan agar dibuat otomatis dari isi',
        ),
        CmsTextField('isi', 'Isi', initial: existing?.isi ?? '', lines: 8),
        CmsImageField('gambar_url', 'Gambar', initial: existing?.gambarUrl),
      ],
      onSubmit: (v) async {
        final input = CmsPostInput(
          judul: v.text('judul'),
          kategori: v.choice('kategori'),
          tanggal: v.date('tanggal'),
          status: ContentStatus.from(v.choice('status')),
          ringkasan: v.text('ringkasan'),
          isi: v.text('isi'),
          gambarUrl: v.image('gambar_url'),
        );
        if (existing == null) {
          await notifier.create(input);
        } else {
          await notifier.edit(existing.slug, input);
        }
        AppToast.show(existing == null ? 'Berhasil ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  Future<void> _edit(CmsPostSummary summary) async {
    final post = await guardAdmin(() => ref.read(adminRepositoryProvider).fetchPost(summary.slug));
    if (post == null || !mounted) return;
    await _openForm(existing: post);
  }

  void _delete(CmsPostSummary post) {
    cmsConfirmDelete(
      context,
      title: 'Hapus "${post.judul}"?',
      description: 'Berita atau pengumuman ini hilang dari website dan tidak dapat dikembalikan.',
      onDelete: () => ref.read(cmsPostsProvider.notifier).delete(post.slug),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Kelola Berita & Pengumuman',
          action: CustomButton(label: '+ Tambah', onPressed: () => _openForm()),
        ),
        AdminToolbar(
          search: AdminChipBar<ContentStatus?>(
            selected: _status,
            onSelected: (v) => setState(() => _status = v),
            options: [(null, 'Semua'), for (final s in ContentStatus.values) (s, s.label)],
          ),
          filters: [
            AdminDropdown<String?>(
              semanticLabel: 'Filter kategori',
              value: _category,
              items: [null, ...kPostCategories],
              itemLabel: (v) => v ?? 'Semua kategori',
              onChanged: (v) => setState(() => _category = v),
            ),
          ],
        ),
        AsyncBody<List<CmsPostSummary>>(
          value: ref.watch(cmsPostsProvider),
          onRetry: () => ref.invalidate(cmsPostsProvider),
          builder: (all) {
            final posts = [
              for (final p in all)
                if ((_status == null || p.status == _status) &&
                    (_category == null || p.kategori == _category))
                  p,
            ];
            if (posts.isEmpty) return const CmsEmpty('Belum ada berita atau pengumuman.');
            return AdminDataTable(
              columns: const [
                AdminColumn('Judul', flex: 4),
                AdminColumn('Kategori', width: 120),
                AdminColumn('Tanggal', width: 120),
                AdminColumn('Status', width: 100),
                AdminColumn('Aksi', width: 130),
              ],
              rows: [
                for (final p in posts)
                  [
                    Text(
                      p.judul,
                      style: context.styleBold,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(p.kategori, style: context.styleBody),
                    Text(formatDate(p.tanggal), style: context.styleBody),
                    cmsStatusBadge(p.status),
                    Row(
                      children: [
                        LinkText('Edit', onTap: () => _edit(p)),
                        const SizedBox(width: 14),
                        LinkText('Hapus', onTap: () => _delete(p)),
                      ],
                    ),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}
