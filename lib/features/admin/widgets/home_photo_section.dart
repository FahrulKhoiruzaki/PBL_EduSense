import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media_picker.dart';
import '../../../core/network/media_url.dart';
import '../../../core/theme.dart';
import '../../../core/user_facing_error.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_button.dart';
import '../data/cms_models.dart';
import '../data/photo_validation.dart';
import '../providers/cms_providers.dart';
import 'cms_common.dart';

/// Foto sekolah di bawah hero beranda: pilih, validasi, pratinjau, lalu simpan.
class HomePhotoSection extends ConsumerWidget {
  const HomePhotoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CmsSection(
      title: 'Foto Beranda',
      subtitle:
          'Foto besar di bawah judul sekolah pada halaman beranda website. Format $kPhotoFormatsLabel, '
          'maksimal ${kMaxPhotoBytes ~/ (1024 * 1024)} MB.',
      child: AsyncBody<CmsSchool>(
        value: ref.watch(cmsSchoolProvider),
        onRetry: () => ref.invalidate(cmsSchoolProvider),
        builder: (school) => _PhotoEditor(currentUrl: school.fotoUrl),
      ),
    );
  }
}

class _PhotoEditor extends ConsumerStatefulWidget {
  const _PhotoEditor({required this.currentUrl});

  final String? currentUrl;

  @override
  ConsumerState<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends ConsumerState<_PhotoEditor> {
  PickedImage? _pending;
  String? _error;
  var _saving = false;

  Future<void> _pick() async {
    final picked = await ref.read(mediaPickerProvider).pick();
    if (picked == null || !mounted) return;
    final problem = validatePhoto(picked.bytes);
    setState(() {
      _error = problem;
      // Berkas yang ditolak tidak mengganti pratinjau maupun foto yang sedang dipakai.
      if (problem == null) _pending = picked;
    });
  }

  Future<void> _save() async {
    final image = _pending;
    if (image == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(cmsSchoolProvider.notifier).replacePhoto(image);
      if (!mounted) return;
      setState(() {
        _pending = null;
        _saving = false;
      });
      AppToast.show('Foto beranda berhasil diganti.');
    } on UserFacingError catch (e) {
      if (!mounted) return;
      // Foto lama tetap dipakai; berkas terpilih dipertahankan supaya bisa dicoba lagi.
      setState(() {
        _saving = false;
        _error = e.fieldErrors['file'] ?? e.message;
      });
    }
  }

  Widget _preview(BuildContext context) {
    final c = context.colors;
    final empty = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.mi, borderRadius: BorderRadius.circular(12)),
      child: Text('Belum ada foto.', style: context.styleMuted),
    );
    final Widget image;
    final pending = _pending;
    final url = resolveMediaUrl(widget.currentUrl);
    if (pending != null) {
      image = Image.memory(
        pending.bytes,
        key: const ValueKey('photo-preview-pending'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => empty,
      );
    } else if (url != null) {
      image = Image.network(
        url,
        key: const ValueKey('photo-preview-current'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => empty,
      );
    } else {
      image = empty;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final hasPhoto = widget.currentUrl != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _preview(context),
        if (pending != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pratinjau: ${pending.name} (${(pending.bytes.length / 1024).round()} KB). '
              'Belum disimpan.',
              style: context.styleCaption,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: context.styleError),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CustomButton(
              label: hasPhoto || pending != null ? 'Ganti Foto' : 'Pilih Foto',
              variant: ButtonVariant.secondary,
              onPressed: _saving ? null : _pick,
            ),
            if (pending != null) ...[
              CustomButton(
                label: _saving ? 'Mengunggah…' : 'Simpan Foto',
                onPressed: _saving ? null : _save,
              ),
              CustomButton(
                label: 'Batal',
                variant: ButtonVariant.outline,
                onPressed: _saving ? null : () => setState(() {
                  _pending = null;
                  _error = null;
                }),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
