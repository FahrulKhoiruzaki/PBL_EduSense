import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../models/app_models.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../actions/guard_admin.dart';
import '../data/academic_form.dart';
import '../providers/academic_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class GradeComponentsScreen extends ConsumerWidget {
  const GradeComponentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodId = ref.watch(effectivePeriodIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Komponen Penilaian'),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Komponen (mis. Tugas, Ulangan Harian) ditetapkan per mapel per periode. Guru hanya '
            'dapat memasukkan nilai ke komponen aktif. Kategori Literasi/Numerasi menentukan '
            'komponen yang dihitung untuk klasifikasi. Bobot opsional: bila semua komponen yang '
            'dinilai berbobot, nilai akhir = rata-rata berbobot; bila tidak, rata-rata biasa.',
            style: context.styleSoft,
          ),
        ),
        AsyncBody<List<AdminPeriod>>(
          value: ref.watch(adminPeriodsProvider),
          onRetry: () => ref.invalidate(adminPeriodsProvider),
          builder: (periods) {
            if (periods.isEmpty || periodId == null) {
              return const CmsEmpty(
                'Belum ada periode akademik. Buat periode di menu Periode Akademik terlebih dahulu.',
              );
            }
            final period = periods.firstWhere((p) => p.id == periodId);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AcademicPeriodPicker(periods: periods, selected: periodId),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CustomButton(
                      label: '+ Tambah Komponen',
                      onPressed: () => _openForm(context, period: period),
                    ),
                    if (periods.length > 1)
                      CustomButton(
                        label: 'Salin dari periode lain',
                        variant: ButtonVariant.outline,
                        onPressed: () => _copy(context, periods, period),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _ComponentList(period: period),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Dropdown periode bersama untuk layar komponen dan klasifikasi.
class AcademicPeriodPicker extends ConsumerWidget {
  const AcademicPeriodPicker({super.key, required this.periods, required this.selected});

  final List<AdminPeriod> periods;
  final int selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: 360,
        child: AdminDropdown<int>(
          semanticLabel: 'Periode akademik',
          value: selected,
          items: [for (final p in periods) p.id],
          itemLabel: (id) {
            final p = periods.firstWhere((p) => p.id == id);
            return p.active ? '${p.label} (aktif)' : p.label;
          },
          onChanged: (id) => ref.read(academicPeriodFilterProvider.notifier).set(id),
        ),
      ),
    );
  }
}

class _ComponentList extends ConsumerWidget {
  const _ComponentList({required this.period});

  final AdminPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<AdminComponent>>(
      value: ref.watch(adminComponentsProvider(period.id)),
      onRetry: () => ref.invalidate(adminComponentsProvider(period.id)),
      builder: (components) {
        if (components.isEmpty) {
          return CmsEmpty('Belum ada komponen penilaian untuk ${period.label}.');
        }
        final bySubject = <int, List<AdminComponent>>{};
        for (final c in components) {
          bySubject.putIfAbsent(c.subjectId, () => []).add(c);
        }
        return Column(
          children: [
            for (final group in bySubject.values)
              CmsSection(
                title: group.first.subjectName,
                subtitle: _weightSummary(group),
                child: AdminDataTable(
                  columns: const [
                    AdminColumn('Komponen', flex: 3),
                    AdminColumn('Kategori', width: 150),
                    AdminColumn('Bobot', width: 80),
                    AdminColumn('Nilai', width: 80),
                    AdminColumn('Status', width: 90),
                    AdminColumn('Aksi', width: 200),
                  ],
                  rows: [
                    for (final c in group)
                      [
                        Text(c.name, style: context.styleBold),
                        Text(c.category?.label ?? 'Tidak dihitung', style: context.styleBody),
                        Text(c.weight == null ? '—' : formatScore(c.weight), style: context.styleBody),
                        Text('${c.gradeCount}', style: context.styleBody),
                        Text(c.active ? 'Aktif' : 'Nonaktif', style: context.styleBody),
                        Wrap(
                          spacing: 14,
                          children: [
                            LinkText(
                              'Edit',
                              onTap: () => _openForm(context, period: period, existing: c),
                            ),
                            LinkText(
                              c.active ? 'Nonaktifkan' : 'Aktifkan',
                              onTap: () => _toggle(context, c),
                            ),
                            if (c.gradeCount == 0)
                              LinkText('Hapus', onTap: () => _delete(context, c)),
                          ],
                        ),
                      ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

String _weightSummary(List<AdminComponent> group) {
  final active = [
    for (final c in group)
      if (c.active) c,
  ];
  if (active.isEmpty) return 'Tidak ada komponen aktif.';
  final weighted = active.where((c) => c.weight != null).toList();
  if (weighted.isEmpty) return 'Tanpa bobot: nilai akhir = rata-rata komponen yang dinilai.';
  final total = weighted.fold<double>(0, (sum, c) => sum + c.weight!);
  final note = weighted.length < active.length
      ? ' Ada komponen aktif tanpa bobot, sehingga nilai akhir memakai rata-rata biasa.'
      : '';
  return 'Total bobot komponen aktif: ${formatScore(total)} (maksimal 100).$note';
}

Future<void> _openForm(
  BuildContext context, {
  required AdminPeriod period,
  AdminComponent? existing,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final subjects = await guardAdmin(() => container.read(adminSubjectsProvider.future));
  if (subjects == null || !context.mounted) return;
  final choices = [
    for (final s in subjects)
      if (s.active || s.id == existing?.subjectId) s,
  ];
  if (choices.isEmpty) {
    AppToast.show('Belum ada mata pelajaran aktif. Tambahkan di menu Mata Pelajaran.');
    return;
  }
  final actions = container.read(adminComponentsActionsProvider);
  final locked = (existing?.gradeCount ?? 0) > 0;
  await showCmsForm(
    context,
    title: existing == null ? 'Tambah Komponen · ${period.label}' : 'Edit ${existing.name}',
    subtitle: locked
        ? 'Komponen ini sudah memiliki ${existing!.gradeCount} nilai: mapel tidak dapat diubah. '
            'Mengubah kategori atau bobot menghitung ulang klasifikasi periode ini.'
        : null,
    submitLabel: existing == null ? 'Tambah' : 'Simpan',
    fields: [
      CmsChoiceField(
        'mapel_id',
        'Mata pelajaran',
        initial: '${existing?.subjectId ?? choices.first.id}',
        options: [
          for (final s in choices)
            if (!locked || s.id == existing!.subjectId)
              ('${s.id}', s.type == SubjectType.muatanLokal ? '${s.name} (Muatan Lokal)' : s.name),
        ],
      ),
      CmsTextField(
        'nama',
        'Nama komponen',
        initial: existing?.name ?? '',
        hint: 'Mis. Tugas, Ulangan Harian, Asesmen Sumatif',
        required: true,
      ),
      CmsChoiceField(
        'kategori',
        'Dihitung untuk klasifikasi',
        initial: existing?.category?.label ?? '',
        options: [
          ('', 'Tidak (komponen biasa)'),
          for (final k in SubjectCategory.values) (k.label, 'Ya, sebagai ${k.label}'),
        ],
      ),
      CmsTextField(
        'bobot',
        'Bobot (opsional)',
        initial: scoreText(existing?.weight),
        hint: 'Angka > 0 sampai 100. Kosongkan bila tanpa bobot.',
      ),
      CmsTextField('deskripsi', 'Keterangan', initial: existing?.description ?? '', lines: 2),
    ],
    onSubmit: (v) async {
      final weight = parseScore(v.text('bobot'), field: 'bobot', optional: true);
      if (weight != null && weight <= 0) {
        throw AcademicFormError('bobot', 'Bobot harus lebih dari 0.');
      }
      final input = ComponentInput(
        periodId: period.id,
        subjectId: int.parse(v.choice('mapel_id')),
        name: v.text('nama'),
        category: subjectCategoryFromLabel(v.choice('kategori')),
        weight: weight,
        description: v.text('deskripsi'),
      );
      existing == null ? await actions.create(input) : await actions.edit(existing.id, input);
      AppToast.show(existing == null ? 'Komponen ditambahkan.' : 'Perubahan disimpan.');
    },
  );
}

Future<void> _toggle(BuildContext context, AdminComponent c) async {
  final actions = ProviderScope.containerOf(context, listen: false).read(adminComponentsActionsProvider);
  final done = await guardAdmin(() async {
    await actions.setActive(c.id, active: !c.active);
    return true;
  });
  if (done == true) {
    AppToast.show(c.active
        ? '${c.name} dinonaktifkan. Nilai yang sudah ada tetap dihitung.'
        : '${c.name} diaktifkan.');
  }
}

void _delete(BuildContext context, AdminComponent c) {
  final actions = ProviderScope.containerOf(context, listen: false).read(adminComponentsActionsProvider);
  cmsConfirmDelete(
    context,
    title: 'Hapus komponen ${c.name} (${c.subjectName})?',
    description: 'Komponen ini belum memiliki nilai siswa.',
    onDelete: () => actions.delete(c.id),
  );
}

void _copy(BuildContext context, List<AdminPeriod> periods, AdminPeriod target) {
  final actions = ProviderScope.containerOf(context, listen: false).read(adminComponentsActionsProvider);
  final sources = [
    for (final p in periods)
      if (p.id != target.id) p,
  ];
  showAdminFormDialog(
    adminDialogContext(context),
    title: 'Salin komponen ke ${target.label}',
    subtitle: 'Komponen dengan nama yang sama di mapel yang sama dilewati. Nilai tidak ikut disalin.',
    submitLabel: 'Salin',
    fields: [
      AdminFormField(
        id: 'dari',
        label: 'Salin dari periode',
        options: [for (final p in sources) ('${p.id}', p.label)],
      ),
    ],
    onSubmit: (v) async {
      final result = await guardAdmin(
        () => actions.copy(from: int.parse(v['dari']!), to: target.id),
      );
      if (result != null) {
        AppToast.show('${result.$1} komponen disalin, ${result.$2} dilewati (sudah ada).');
      }
    },
  );
}
