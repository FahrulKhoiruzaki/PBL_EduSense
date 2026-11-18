import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../actions/guard_admin.dart';
import '../providers/academic_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class SubjectsScreen extends ConsumerStatefulWidget {
  const SubjectsScreen({super.key});

  @override
  ConsumerState<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends ConsumerState<SubjectsScreen> {
  SubjectType? _type;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Mata Pelajaran',
          action: CustomButton(label: '+ Tambah Mapel', onPressed: () => _openForm(context)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Mata pelajaran umum dan muatan lokal. Daftar awal mapel umum hanyalah template: '
            'sesuaikan nama dan jenjangnya dengan kurikulum sekolah. Mapel yang sudah dipakai '
            'tidak dapat dihapus, hanya dinonaktifkan, agar data nilai lama tetap utuh.',
            style: context.styleSoft,
          ),
        ),
        AdminChipBar<SubjectType?>(
          selected: _type,
          onSelected: (v) => setState(() => _type = v),
          options: [
            (null, 'Semua'),
            for (final t in SubjectType.values) (t, t.label),
          ],
        ),
        AsyncBody<List<Subject>>(
          value: ref.watch(adminSubjectsProvider),
          onRetry: () => ref.invalidate(adminSubjectsProvider),
          builder: (all) {
            final items = [
              for (final s in all)
                if (_type == null || s.type == _type) s,
            ];
            if (items.isEmpty) {
              return CmsEmpty(
                _type == SubjectType.muatanLokal
                    ? 'Belum ada muatan lokal. Tambahkan sesuai ketetapan sekolah.'
                    : 'Belum ada mata pelajaran.',
              );
            }
            return AdminDataTable(
              columns: const [
                AdminColumn('Kode', width: 90),
                AdminColumn('Mata pelajaran', flex: 4),
                AdminColumn('Jenis', width: 120),
                AdminColumn('Jenjang', flex: 2),
                AdminColumn('Status', width: 90),
                AdminColumn('Aksi', width: 200),
              ],
              rows: [
                for (final s in items)
                  [
                    Text(s.code, style: context.styleBold),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: context.styleBold),
                        if (s.description.isNotEmpty)
                          Text(
                            s.description,
                            style: context.styleAdminCaption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    Text(s.type.label, style: context.styleBody),
                    Text(s.levelsLabel, style: context.styleBody),
                    Text(s.active ? 'Aktif' : 'Nonaktif', style: context.styleBody),
                    Wrap(
                      spacing: 14,
                      children: [
                        LinkText('Edit', onTap: () => _openForm(context, existing: s)),
                        LinkText(
                          s.active ? 'Nonaktifkan' : 'Aktifkan',
                          onTap: () => _toggle(s),
                        ),
                        if (!s.used) LinkText('Hapus', onTap: () => _delete(s)),
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

  Future<void> _toggle(Subject s) async {
    final done = await guardAdmin(() async {
      await ref.read(adminSubjectsProvider.notifier).setActive(s.id, active: !s.active);
      return true;
    });
    if (done == true) AppToast.show('${s.name} ${s.active ? 'dinonaktifkan' : 'diaktifkan'}.');
  }

  void _delete(Subject s) {
    cmsConfirmDelete(
      context,
      title: 'Hapus ${s.name}?',
      description: 'Mapel ini belum dipakai penugasan guru, komponen, atau nilai.',
      onDelete: () => ref.read(adminSubjectsProvider.notifier).delete(s.id),
    );
  }
}

Future<void> _openForm(BuildContext context, {Subject? existing}) {
  final notifier =
      ProviderScope.containerOf(context, listen: false).read(adminSubjectsProvider.notifier);
  return showCmsForm(
    context,
    title: existing == null ? 'Tambah Mata Pelajaran' : 'Edit ${existing.name}',
    submitLabel: existing == null ? 'Tambah' : 'Simpan',
    fields: [
      CmsTextField(
        'kode',
        'Kode',
        initial: existing?.code ?? '',
        hint: '2–12 huruf kapital/angka, mis. BJAWA',
        required: true,
      ),
      CmsTextField('nama', 'Nama mata pelajaran', initial: existing?.name ?? '', required: true),
      CmsChoiceField(
        'jenis',
        'Jenis',
        initial: (existing?.type ?? SubjectType.umum).code,
        options: [for (final t in SubjectType.values) (t.code, t.label)],
      ),
      CmsMultiChoiceField(
        'tingkat',
        'Diajarkan di kelas',
        initial: [for (final l in existing?.levels ?? const [1, 2, 3, 4, 5, 6]) '$l'],
        options: [for (var l = 1; l <= 6; l++) ('$l', 'Kelas $l')],
        required: true,
      ),
      CmsTextField('deskripsi', 'Keterangan', initial: existing?.description ?? '', lines: 2),
    ],
    onSubmit: (v) async {
      final input = SubjectInput(
        code: v.text('kode').toUpperCase(),
        name: v.text('nama'),
        description: v.text('deskripsi'),
        type: SubjectType.fromCode(v.choice('jenis')),
        levels: [for (final l in v.choices('tingkat')) int.parse(l)],
      );
      existing == null ? await notifier.create(input) : await notifier.edit(existing.id, input);
      AppToast.show(existing == null ? 'Mata pelajaran ditambahkan.' : 'Perubahan disimpan.');
    },
  );
}
