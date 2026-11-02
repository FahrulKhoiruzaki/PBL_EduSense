import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';
import '../data/school_info_models.dart';
import '../providers/school_info_providers.dart';

class ClassInfoAdminScreen extends ConsumerStatefulWidget {
  const ClassInfoAdminScreen({super.key});

  @override
  ConsumerState<ClassInfoAdminScreen> createState() => _ClassInfoAdminScreenState();
}

class _ClassInfoAdminScreenState extends ConsumerState<ClassInfoAdminScreen> {
  int? _level;

  Future<void> _openForm({ClassEntry? existing}) {
    final notifier = ProviderScope.containerOf(context, listen: false)
        .read(classEntriesProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Informasi Kelas' : 'Edit Informasi Kelas',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsChoiceField(
          'tingkat',
          'Kelas',
          initial: '${existing?.level ?? _level ?? kClassLevels.first}',
          options: [for (final l in kClassLevels) ('$l', 'Kelas $l')],
        ),
        CmsChoiceField(
          'jenis',
          'Jenis',
          initial: (existing?.kind ?? ClassEntryKind.pembelajaran).label,
          options: [for (final k in ClassEntryKind.values) (k.label, k.label)],
        ),
        CmsTextField('judul', 'Judul', initial: existing?.title ?? '', required: true),
        CmsTextField('deskripsi', 'Deskripsi', initial: existing?.description ?? '', lines: 5),
        CmsTextField(
          'urutan',
          'Urutan tampil',
          initial: existing == null ? '' : '${existing.order}',
          hint: 'Kosongkan agar ditaruh paling akhir',
          number: true,
        ),
        CmsToggleField('tampil', 'Tampilkan di website', initial: existing?.visible ?? true),
      ],
      onSubmit: (v) async {
        await notifier.save(
          id: existing?.id,
          draft: ClassEntryDraft(
            level: int.parse(v.choice('tingkat')),
            kind: ClassEntryKind.from(v.choice('jenis')),
            title: v.text('judul'),
            description: v.text('deskripsi'),
            order: v.number('urutan'),
            visible: v.flag('tampil'),
          ),
        );
        AppToast.show(existing == null ? 'Informasi kelas ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  void _delete(ClassEntry entry) {
    cmsConfirmDelete(
      context,
      title: 'Hapus "${entry.title}"?',
      description: 'Informasi ini hilang dari halaman Akademik kelas ${entry.level}.',
      onDelete: () => ref.read(classEntriesProvider.notifier).delete(entry.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Informasi Kelas',
          action: CustomButton(label: '+ Tambah', onPressed: () => _openForm()),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Informasi pembelajaran dan kegiatan tiap kelas. Tampil di halaman Akademik website.',
            style: context.styleSoft,
          ),
        ),
        AdminChipBar<int?>(
          selected: _level,
          onSelected: (v) => setState(() => _level = v),
          options: [(null, 'Semua'), for (final l in kClassLevels) (l, 'Kelas $l')],
        ),
        AsyncBody<List<ClassEntry>>(
          value: ref.watch(classEntriesProvider),
          onRetry: () => ref.invalidate(classEntriesProvider),
          builder: (all) {
            final items = [
              for (final e in all)
                if (_level == null || e.level == _level) e,
            ];
            if (items.isEmpty) return const CmsEmpty('Belum ada informasi kelas.');
            return AdminDataTable(
              columns: const [
                AdminColumn('Kelas', width: 80),
                AdminColumn('Jenis', width: 120),
                AdminColumn('Judul', flex: 4),
                AdminColumn('Urutan', width: 80),
                AdminColumn('Tampil', width: 80),
                AdminColumn('Aksi', width: 130),
              ],
              rows: [
                for (final e in items)
                  [
                    Text('${e.level}', style: context.styleBold),
                    Text(e.kind.label, style: context.styleBody),
                    Text(
                      e.title,
                      style: context.styleBold,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('${e.order}', style: context.styleBody),
                    Text(e.visible ? 'Ya' : 'Tidak', style: context.styleBody),
                    Row(
                      children: [
                        LinkText('Edit', onTap: () => _openForm(existing: e)),
                        const SizedBox(width: 14),
                        LinkText('Hapus', onTap: () => _delete(e)),
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
