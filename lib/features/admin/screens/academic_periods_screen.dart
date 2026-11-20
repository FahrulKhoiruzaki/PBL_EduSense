import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../repositories/academic_admin_repository.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/status_badge.dart';
import '../actions/guard_admin.dart';
import '../data/academic_form.dart';
import '../providers/academic_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class AcademicPeriodsScreen extends ConsumerWidget {
  const AcademicPeriodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Periode Akademik',
          action: CustomButton(label: '+ Tambah Periode', onPressed: () => _openForm(context)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Satu periode = satu semester dalam satu tahun ajaran. Periode aktif menjadi acuan '
            'nilai, absensi, rekap, dan klasifikasi di semua halaman. Mengganti periode aktif tidak '
            'mengubah data periode lain.',
            style: context.styleSoft,
          ),
        ),
        AsyncBody<List<AdminPeriod>>(
          value: ref.watch(adminPeriodsProvider),
          onRetry: () => ref.invalidate(adminPeriodsProvider),
          builder: (periods) {
            if (periods.isEmpty) {
              return const CmsEmpty(
                'Belum ada periode akademik. Tambahkan periode, lalu jadikan aktif.',
              );
            }
            return AdminDataTable(
              columns: const [
                AdminColumn('Periode', flex: 3),
                AdminColumn('Rentang tanggal', flex: 3),
                AdminColumn('Data', flex: 2),
                AdminColumn('Aturan klasifikasi', flex: 2),
                AdminColumn('Aksi', width: 300),
              ],
              rows: [
                for (final p in periods)
                  [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(p.label, style: context.styleBold),
                        if (p.active) const StatusBadge(label: 'Aktif', variant: BadgeVariant.mahir),
                      ],
                    ),
                    Text(
                      '${formatDate(p.start)} – ${formatDate(p.end)}',
                      style: context.styleBody,
                    ),
                    Text('${p.gradeCount} nilai · ${p.componentCount} komponen', style: context.styleBody),
                    Text(p.hasRule ? 'Ditetapkan' : 'Belum ditetapkan', style: context.styleBody),
                    Wrap(
                      spacing: 14,
                      children: [
                        LinkText('Edit', onTap: () => _openForm(context, existing: p)),
                        if (!p.active) LinkText('Aktifkan', onTap: () => _activate(context, p)),
                        LinkText('Aturan', onTap: () => _openRule(context, p)),
                        LinkText('Hitung ulang', onTap: () => _recompute(context, p)),
                        if (p.deletable) LinkText('Hapus', onTap: () => _delete(context, p)),
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

Future<void> _openForm(BuildContext context, {AdminPeriod? existing}) {
  final notifier =
      ProviderScope.containerOf(context, listen: false).read(adminPeriodsProvider.notifier);
  return showCmsForm(
    context,
    title: existing == null ? 'Tambah Periode Akademik' : 'Edit ${existing.label}',
    subtitle: existing != null && existing.gradeCount > 0
        ? 'Periode ini sudah memiliki nilai: tahun ajaran dan semester tidak dapat diubah, dan '
            'rentang tanggal harus tetap memuat semua nilainya.'
        : 'Rentang tanggal tidak boleh bertumpang tindih dengan periode lain.',
    submitLabel: existing == null ? 'Tambah' : 'Simpan',
    fields: [
      CmsTextField(
        'tahun_ajaran',
        'Tahun ajaran',
        initial: existing?.academicYear ?? '',
        hint: 'Mis. 2026/2027',
        required: true,
      ),
      CmsChoiceField(
        'semester',
        'Semester',
        initial: '${existing?.semester ?? 1}',
        options: const [('1', 'Ganjil (1)'), ('2', 'Genap (2)')],
      ),
      CmsDateField('tanggal_mulai', 'Tanggal mulai', initial: existing?.start, required: true),
      CmsDateField('tanggal_selesai', 'Tanggal selesai', initial: existing?.end, required: true),
    ],
    onSubmit: (v) async {
      final input = PeriodInput(
        academicYear: v.text('tahun_ajaran'),
        semester: int.parse(v.choice('semester')),
        start: v.date('tanggal_mulai')!,
        end: v.date('tanggal_selesai')!,
      );
      if (!input.end.isAfter(input.start)) {
        throw AcademicFormError('tanggal_selesai', 'Tanggal selesai harus setelah tanggal mulai.');
      }
      existing == null ? await notifier.create(input) : await notifier.edit(existing.id, input);
      AppToast.show(existing == null ? 'Periode ditambahkan.' : 'Perubahan disimpan.');
    },
  );
}

void _activate(BuildContext context, AdminPeriod p) {
  final notifier =
      ProviderScope.containerOf(context, listen: false).read(adminPeriodsProvider.notifier);
  showAdminConfirm(
    adminDialogContext(context),
    title: 'Jadikan ${p.label} periode aktif?',
    description: 'Semua halaman guru, orang tua, dan admin akan memakai periode ini secara bawaan. '
        'Data periode lain tetap tersimpan dan tetap dapat dilihat lewat filter.',
    confirmLabel: 'Aktifkan',
    onConfirm: () async {
      final done = await guardAdmin(() async {
        await notifier.activate(p.id);
        return true;
      });
      if (done == true) AppToast.show('${p.label} sekarang periode aktif.');
    },
  );
}

void _delete(BuildContext context, AdminPeriod p) {
  final notifier =
      ProviderScope.containerOf(context, listen: false).read(adminPeriodsProvider.notifier);
  cmsConfirmDelete(
    context,
    title: 'Hapus ${p.label}?',
    description: 'Periode ini belum memiliki nilai, komponen, atau hasil klasifikasi.',
    onDelete: () => notifier.delete(p.id),
  );
}

Future<void> _openRule(BuildContext context, AdminPeriod p) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final rule = await guardAdmin(() => container.read(adminRuleProvider(p.id).future));
  if (!context.mounted) return;
  final notifier = container.read(adminPeriodsProvider.notifier);
  await showCmsForm(
    context,
    title: 'Aturan Klasifikasi · ${p.label}',
    subtitle: 'Belum ada ambang resmi bawaan sistem: isi sesuai keputusan sekolah. Menyimpan aturan '
        'langsung menghitung ulang klasifikasi seluruh siswa pada periode ini.',
    submitLabel: 'Simpan Aturan',
    fields: [
      CmsChoiceField(
        'metode',
        'Metode skor akhir',
        initial: (rule?.method ?? ClassificationMethod.average).code,
        options: [for (final m in ClassificationMethod.values) (m.code, m.label)],
      ),
      CmsTextField(
        'batas_mahir',
        'Batas Mahir (skor ≥)',
        initial: scoreText(rule?.mahirMin),
        hint: 'Angka 0–100',
        required: true,
      ),
      CmsTextField(
        'batas_cukup',
        'Batas Cukup (skor ≥)',
        initial: scoreText(rule?.cukupMin),
        hint: 'Angka 0–100, lebih rendah dari batas Mahir',
        required: true,
      ),
    ],
    onSubmit: (v) async {
      final mahir = parseScore(v.text('batas_mahir'), field: 'batas_mahir')!;
      final cukup = parseScore(v.text('batas_cukup'), field: 'batas_cukup')!;
      if (cukup >= mahir) {
        throw AcademicFormError('batas_cukup', 'Batas Cukup harus lebih rendah dari batas Mahir.');
      }
      await notifier.saveRule(
        p.id,
        ClassificationRule(
          method: ClassificationMethod.fromCode(v.choice('metode')),
          mahirMin: mahir,
          cukupMin: cukup,
        ),
      );
      AppToast.show('Aturan disimpan dan klasifikasi dihitung ulang.');
    },
  );
}

void _recompute(BuildContext context, AdminPeriod p) {
  final notifier =
      ProviderScope.containerOf(context, listen: false).read(adminPeriodsProvider.notifier);
  showAdminConfirm(
    adminDialogContext(context),
    title: 'Hitung ulang klasifikasi ${p.label}?',
    description: p.hasRule
        ? 'Skor dan klasifikasi semua siswa pada periode ini dihitung ulang dari nilai terbaru.'
        : 'Aturan klasifikasi periode ini belum ditetapkan: skor dihitung, tetapi siswa belum '
            'dimasukkan ke kategori mana pun.',
    confirmLabel: 'Hitung ulang',
    onConfirm: () async {
      final result = await guardAdmin(() => notifier.recompute(p.id));
      if (result != null) {
        AppToast.show('${result.$1} siswa dihitung, ${result.$2} terklasifikasi.');
      }
    },
  );
}
