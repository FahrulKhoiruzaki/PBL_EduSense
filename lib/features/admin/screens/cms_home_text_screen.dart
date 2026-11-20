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
import '../widgets/home_photo_section.dart';

class CmsHomeTextScreen extends ConsumerWidget {
  const CmsHomeTextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Pengaturan Beranda & Teks'),
        const HomePhotoSection(),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Teks di bawah ini tampil langsung di website. Kolom yang dikosongkan akan '
            'menampilkan "Informasi belum tersedia" di website (atau tidak tampil untuk teks hiasan).',
            style: context.styleSoft,
          ),
        ),
        AsyncBody<List<CmsPage>>(
          value: ref.watch(cmsPagesProvider),
          onRetry: () => ref.invalidate(cmsPagesProvider),
          builder: (pages) => _PagesForm(pages: pages),
        ),
      ],
    );
  }
}

class _PagesForm extends ConsumerStatefulWidget {
  const _PagesForm({required this.pages});

  final List<CmsPage> pages;

  @override
  ConsumerState<_PagesForm> createState() => _PagesFormState();
}

class _PagesFormState extends ConsumerState<_PagesForm> {
  late final Map<String, TextEditingController> _controllers = {
    for (final p in widget.pages) p.kunci: TextEditingController(text: p.isi),
  };
  late Map<String, String> _saved = {for (final p in widget.pages) p.kunci: p.isi.trim()};
  final Map<String, String> _errors = {};
  var _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _changed => {
    for (final e in _controllers.entries)
      if (e.value.text.trim() != _saved[e.key]) e.key: e.value.text.trim(),
  };

  Future<void> _save() async {
    final changed = _changed;
    if (changed.isEmpty) return;
    setState(() {
      _saving = true;
      _errors.clear();
    });
    try {
      await ref.read(cmsPagesProvider.notifier).save(changed);
      if (!mounted) return;
      final fresh = ref.read(cmsPagesProvider).requireValue;
      setState(() {
        _saved = {for (final p in fresh) p.kunci: p.isi.trim()};
        for (final p in fresh) {
          _controllers[p.kunci]?.text = p.isi;
        }
        _saving = false;
      });
      AppToast.show('Teks website berhasil disimpan.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors.addAll(e.fieldErrors);
      });
      AppToast.show(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CmsPage>>{};
    for (final p in widget.pages) {
      groups.putIfAbsent(p.grup, () => []).add(p);
    }
    final dirty = _changed.isNotEmpty;

    Widget saveButton() => CustomButton(
      label: _saving ? 'Menyimpan…' : 'Simpan Perubahan',
      onPressed: dirty && !_saving ? _save : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(alignment: Alignment.centerRight, child: saveButton()),
        const SizedBox(height: 12),
        for (final (index, entry) in groups.entries.indexed)
          CmsSection(
            title: entry.key,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: ValueKey('cms-group-${entry.key}'),
                initiallyExpanded: index == 0,
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('${entry.value.length} teks', style: context.styleSoft),
                children: [
                  for (final p in entry.value)
                    LabeledField(
                      label: p.label,
                      controller: _controllers[p.kunci],
                      maxLines: p.baris.clamp(1, 10),
                      error: _errors[p.kunci],
                      onChanged: (_) => setState(() {}),
                    ),
                ],
              ),
            ),
          ),
        Align(alignment: Alignment.centerRight, child: saveButton()),
      ],
    );
  }
}
