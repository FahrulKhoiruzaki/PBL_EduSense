import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';
import '../data/school_info_models.dart';
import '../providers/school_info_providers.dart';

String calendarEntryRange(CalendarEntry e) {
  final end = e.end;
  return end == null ? formatDate(e.start) : '${formatDate(e.start)} – ${formatDate(end)}';
}

class CalendarAdminScreen extends ConsumerStatefulWidget {
  const CalendarAdminScreen({super.key});

  @override
  ConsumerState<CalendarAdminScreen> createState() => _CalendarAdminScreenState();
}

class _CalendarAdminScreenState extends ConsumerState<CalendarAdminScreen> {
  CalendarCategory? _category;

  Future<void> _openForm({CalendarEntry? existing}) {
    final notifier = ProviderScope.containerOf(context, listen: false)
        .read(calendarEntriesProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Kegiatan Kalender' : 'Edit Kegiatan Kalender',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsTextField('judul', 'Judul kegiatan', initial: existing?.title ?? '', required: true),
        CmsChoiceField(
          'kategori',
          'Kategori',
          initial: (existing?.category ?? CalendarCategory.kegiatan).label,
          options: [for (final c in CalendarCategory.values) (c.label, c.label)],
        ),
        CmsDateField('tanggal_mulai', 'Tanggal mulai', initial: existing?.start, required: true),
        CmsDateField(
          'tanggal_selesai',
          'Tanggal selesai (kosong = satu hari)',
          initial: existing?.end,
          clearable: true,
        ),
        CmsTextField('deskripsi', 'Keterangan', initial: existing?.description ?? '', lines: 3),
        CmsToggleField('tampil', 'Tampilkan di website', initial: existing?.visible ?? true),
      ],
      onSubmit: (v) async {
        await notifier.save(
          id: existing?.id,
          draft: CalendarEntryDraft(
            title: v.text('judul'),
            category: CalendarCategory.from(v.choice('kategori')),
            start: v.date('tanggal_mulai'),
            end: v.date('tanggal_selesai'),
            description: v.text('deskripsi'),
            visible: v.flag('tampil'),
          ),
        );
        AppToast.show(existing == null ? 'Kegiatan ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  void _delete(CalendarEntry entry) {
    cmsConfirmDelete(
      context,
      title: 'Hapus "${entry.title}"?',
      description: 'Kegiatan ini hilang dari kalender akademik di website.',
      onDelete: () => ref.read(calendarEntriesProvider.notifier).delete(entry.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Kalender Akademik',
          action: CustomButton(label: '+ Tambah', onPressed: () => _openForm()),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Jadwal kegiatan sekolah yang tampil di halaman Akademik website.',
            style: context.styleSoft,
          ),
        ),
        AdminChipBar<CalendarCategory?>(
          selected: _category,
          onSelected: (v) => setState(() => _category = v),
          options: [
            (null, 'Semua'),
            for (final c in CalendarCategory.values) (c, c.label),
          ],
        ),
        AsyncBody<List<CalendarEntry>>(
          value: ref.watch(calendarEntriesProvider),
          onRetry: () => ref.invalidate(calendarEntriesProvider),
          builder: (all) {
            final items = [
              for (final e in all)
                if (_category == null || e.category == _category) e,
            ];
            if (items.isEmpty) return const CmsEmpty('Belum ada kegiatan di kalender.');
            return AdminDataTable(
              columns: const [
                AdminColumn('Kegiatan', flex: 4),
                AdminColumn('Kategori', width: 110),
                AdminColumn('Tanggal', flex: 3),
                AdminColumn('Tampil', width: 80),
                AdminColumn('Aksi', width: 130),
              ],
              rows: [
                for (final e in items)
                  [
                    Text(
                      e.title,
                      style: context.styleBold,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(e.category.label, style: context.styleBody),
                    Text(calendarEntryRange(e), style: context.styleBody),
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
