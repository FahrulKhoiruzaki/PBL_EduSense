import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/form_fields.dart';
import '../data/cms_models.dart';
import '../providers/cms_providers.dart';
import '../widgets/admin_common.dart';
import '../widgets/cms_common.dart';
import '../widgets/cms_form.dart';

class CmsFaqContactScreen extends ConsumerWidget {
  const CmsFaqContactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Kelola FAQ & Kontak'),
        CmsSection(
          title: 'Kontak & Profil Sekolah',
          subtitle:
              'Tampil di halaman Kontak dan footer website. Nomor WhatsApp dipakai tombol '
              '"Hubungi Admin" di seluruh website.',
          child: AsyncBody<CmsSchool>(
            value: ref.watch(cmsSchoolProvider),
            onRetry: () => ref.invalidate(cmsSchoolProvider),
            builder: (school) => _ContactForm(school: school),
          ),
        ),
        const _FaqPanel(),
      ],
    );
  }
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({required this.school});

  final CmsSchool school;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  static const _ids = [
    'nama',
    'kota',
    'npsn',
    'akreditasi',
    'alamat',
    'telepon',
    'email',
    'media_sosial',
    'whatsapp',
  ];

  late final Map<String, TextEditingController> _controllers = {
    for (final id in _ids) id: TextEditingController(),
  };
  late CmsSchool _saved;
  String? _mapUrl;
  final Map<String, String> _errors = {};
  var _saving = false;
  var _uploading = false;

  @override
  void initState() {
    super.initState();
    _load(widget.school);
  }

  void _load(CmsSchool s) {
    _saved = s;
    _mapUrl = s.petaUrl;
    final values = {
      'nama': s.nama,
      'kota': s.kota,
      'npsn': s.npsn,
      'akreditasi': s.akreditasi,
      'alamat': s.alamat,
      'telepon': s.telepon,
      'email': s.email,
      'media_sosial': s.mediaSosial,
      'whatsapp': s.whatsapp,
    };
    for (final e in values.entries) {
      _controllers[e.key]!.text = e.value ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(String id) {
    final text = _controllers[id]!.text.trim();
    return text.isEmpty ? null : text;
  }

  CmsSchool get _current => CmsSchool(
    nama: _controllers['nama']!.text.trim(),
    kota: _controllers['kota']!.text.trim(),
    npsn: _opt('npsn'),
    akreditasi: _opt('akreditasi'),
    alamat: _opt('alamat'),
    telepon: _opt('telepon'),
    email: _opt('email'),
    mediaSosial: _opt('media_sosial'),
    whatsapp: _opt('whatsapp'),
    petaUrl: _mapUrl,
  );

  bool get _dirty {
    final c = _current, s = _saved;
    return c.nama != s.nama ||
        c.kota != s.kota ||
        c.npsn != s.npsn ||
        c.akreditasi != s.akreditasi ||
        c.alamat != s.alamat ||
        c.telepon != s.telepon ||
        c.email != s.email ||
        c.mediaSosial != s.mediaSosial ||
        c.whatsapp != s.whatsapp ||
        c.petaUrl != s.petaUrl;
  }

  Future<void> _save() async {
    final errors = <String, String>{
      for (final id in const ['nama', 'kota'])
        if (_controllers[id]!.text.trim().isEmpty) id: 'Kolom ini wajib diisi.',
    };
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }
    setState(() {
      _saving = true;
      _errors.clear();
    });
    try {
      final saved = await ref.read(cmsSchoolProvider.notifier).save(_current);
      if (!mounted) return;
      setState(() {
        _load(saved);
        _saving = false;
      });
      AppToast.show('Kontak sekolah berhasil disimpan.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors.addAll(e.fieldErrors);
      });
      AppToast.show(e.message);
    }
  }

  Widget _field(String id, String label, {String? hint, int lines = 1, TextInputType? type}) {
    return LabeledField(
      label: label,
      controller: _controllers[id],
      hint: hint,
      maxLines: lines,
      keyboardType: type,
      error: _errors[id],
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('nama', 'Nama sekolah'),
        _field('kota', 'Kota'),
        _field('npsn', 'NPSN'),
        _field('akreditasi', 'Akreditasi'),
        _field('alamat', 'Alamat', lines: 2),
        _field('telepon', 'Telepon', type: TextInputType.phone),
        _field('email', 'Email', type: TextInputType.emailAddress),
        _field('media_sosial', 'Media sosial', hint: 'Contoh: @sdn02pakunden'),
        _field(
          'whatsapp',
          'Nomor WhatsApp admin',
          hint: '08xx… atau +62xx…',
          type: TextInputType.phone,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Server menyimpannya dalam format 62xxxxxxxxxx; nilai itulah yang dipakai tombol WhatsApp.',
            style: context.styleCaption,
          ),
        ),
        CmsImageInput(
          label: 'Gambar peta lokasi',
          url: _mapUrl,
          error: _errors['peta_url'],
          onChanged: (url) => setState(() => _mapUrl = url),
          onBusy: (busy) => setState(() => _uploading = busy),
        ),
        const SizedBox(height: 16),
        CustomButton(
          label: _saving ? 'Menyimpan…' : 'Simpan Kontak',
          onPressed: _dirty && !_saving && !_uploading ? _save : null,
        ),
      ],
    );
  }
}

class _FaqPanel extends ConsumerWidget {
  const _FaqPanel();

  Future<void> _openForm(BuildContext context, {CmsFaq? existing}) {
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(cmsFaqProvider.notifier);

    return showCmsForm(
      context,
      title: existing == null ? 'Tambah Pertanyaan' : 'Edit Pertanyaan',
      submitLabel: existing == null ? 'Tambah' : 'Simpan',
      fields: [
        CmsChoiceField(
          'kategori',
          'Kategori',
          initial: existing?.kategori ?? kFaqCategories.first,
          options: [for (final c in kFaqCategories) (c, c)],
        ),
        CmsTextField(
          'pertanyaan',
          'Pertanyaan',
          initial: existing?.pertanyaan ?? '',
          required: true,
        ),
        CmsTextField(
          'jawaban',
          'Jawaban',
          initial: existing?.jawaban ?? '',
          lines: 5,
          required: true,
        ),
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
        final input = CmsFaqInput(
          kategori: v.choice('kategori'),
          pertanyaan: v.text('pertanyaan'),
          jawaban: v.text('jawaban'),
          urutan: v.number('urutan'),
          tampil: v.flag('tampil'),
        );
        if (existing == null) {
          await notifier.create(input);
        } else {
          await notifier.edit(existing.id, input);
        }
        AppToast.show(existing == null ? 'Pertanyaan ditambahkan.' : 'Perubahan disimpan.');
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CmsSection(
      title: 'Pertanyaan Umum (FAQ)',
      action: CustomButton(label: '+ Tambah Pertanyaan', onPressed: () => _openForm(context)),
      child: AsyncBody<List<CmsFaq>>(
        value: ref.watch(cmsFaqProvider),
        onRetry: () => ref.invalidate(cmsFaqProvider),
        builder: (items) {
          if (items.isEmpty) return const CmsEmpty('Belum ada pertanyaan.');
          return AdminDataTable(
            columns: const [
              AdminColumn('Pertanyaan', flex: 4),
              AdminColumn('Kategori', width: 110),
              AdminColumn('Urutan', width: 80),
              AdminColumn('Tampil', width: 80),
              AdminColumn('Aksi', width: 130),
            ],
            rows: [
              for (final f in items)
                [
                  Text(
                    f.pertanyaan,
                    style: context.styleBold,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(f.kategori, style: context.styleBody),
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
                          title: 'Hapus pertanyaan ini?',
                          description: f.pertanyaan,
                          onDelete: () => ref.read(cmsFaqProvider.notifier).delete(f.id),
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
