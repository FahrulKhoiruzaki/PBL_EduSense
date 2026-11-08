import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/media_picker.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/media_url.dart';
import '../../../core/user_facing_error.dart';
import '../../../core/theme.dart';
import '../../../repositories/admin_repository.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/form_fields.dart';
import 'admin_dialogs.dart';

const kMaxActivityPhotos = 20;

sealed class CmsField {
  const CmsField(this.id, this.label);

  /// Sama dengan nama kolom di API agar galat server langsung menunjuk ke kolom yang tepat.
  final String id;
  final String label;
}

class CmsTextField extends CmsField {
  const CmsTextField(
    super.id,
    super.label, {
    this.initial = '',
    this.lines = 1,
    this.hint,
    this.required = false,
    this.number = false,
  });

  final String initial;
  final int lines;
  final String? hint;
  final bool required;
  final bool number;
}

class CmsChoiceField extends CmsField {
  const CmsChoiceField(super.id, super.label, {required this.options, required this.initial});

  final List<(String value, String label)> options;
  final String initial;
}

class CmsToggleField extends CmsField {
  const CmsToggleField(super.id, super.label, {this.initial = true});

  final bool initial;
}

class CmsDateField extends CmsField {
  const CmsDateField(
    super.id,
    super.label, {
    this.initial,
    this.required = false,
    this.clearable = false,
  });

  final DateTime? initial;
  final bool required;

  /// Menampilkan tombol untuk mengosongkan tanggal yang sudah dipilih.
  final bool clearable;
}

class CmsImageField extends CmsField {
  const CmsImageField(super.id, super.label, {this.initial});

  final String? initial;
}

class CmsImagesField extends CmsField {
  const CmsImagesField(super.id, super.label, {this.initial = const []});

  final List<String> initial;
}

class CmsValues {
  const CmsValues(this._values);

  final Map<String, Object?> _values;

  String text(String id) => ((_values[id] as String?) ?? '').trim();

  int? number(String id) => int.tryParse(text(id));

  String choice(String id) => _values[id]! as String;

  bool flag(String id) => _values[id]! as bool;

  DateTime? date(String id) => _values[id] as DateTime?;

  String? image(String id) => _values[id] as String?;

  List<String> images(String id) => List<String>.of(_values[id]! as List<String>);
}

Future<void> showCmsForm(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<CmsField> fields,
  required String submitLabel,
  required Future<void> Function(CmsValues values) onSubmit,
}) {
  return showDialog<void>(
    context: adminDialogContext(context),
    barrierColor: scrimColor,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _CmsFormBody(
            title: title,
            subtitle: subtitle,
            fields: fields,
            submitLabel: submitLabel,
            onSubmit: onSubmit,
          ),
        ),
      ),
    ),
  );
}

class _CmsFormBody extends StatefulWidget {
  const _CmsFormBody({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String? subtitle;
  final List<CmsField> fields;
  final String submitLabel;
  final Future<void> Function(CmsValues values) onSubmit;

  @override
  State<_CmsFormBody> createState() => _CmsFormBodyState();
}

class _CmsFormBodyState extends State<_CmsFormBody> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      if (f is CmsTextField) f.id: TextEditingController(text: f.initial),
  };
  late final Map<String, Object?> _state = _initialState();
  final Map<String, String> _errors = {};
  String? _general;
  var _saving = false;
  var _uploading = 0;

  Map<String, Object?> _initialState() {
    final state = <String, Object?>{};
    for (final f in widget.fields) {
      switch (f) {
        case CmsTextField():
          break;
        case CmsChoiceField():
          state[f.id] = f.options.any((o) => o.$1 == f.initial) ? f.initial : f.options.first.$1;
        case CmsToggleField():
          state[f.id] = f.initial;
        case CmsDateField():
          state[f.id] = f.initial;
        case CmsImageField():
          state[f.id] = f.initial;
        case CmsImagesField():
          state[f.id] = List<String>.of(f.initial);
      }
    }
    return state;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  CmsValues get _values =>
      CmsValues({..._state, for (final e in _controllers.entries) e.key: e.value.text});

  Future<void> _submit() async {
    final errors = <String, String>{
      for (final f in widget.fields)
        if (f is CmsTextField && f.required && _controllers[f.id]!.text.trim().isEmpty)
          f.id: 'Kolom ini wajib diisi.'
        else if (f is CmsDateField && f.required && _state[f.id] == null)
          f.id: 'Kolom ini wajib diisi.',
    };
    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
        _general = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _errors.clear();
      _general = null;
    });
    try {
      await widget.onSubmit(_values);
      if (mounted) Navigator.of(context).pop();
    } on UserFacingError catch (e) {
      if (!mounted) return;
      final ids = {for (final f in widget.fields) f.id};
      setState(() {
        _saving = false;
        _errors.addAll({
          for (final entry in e.fieldErrors.entries)
            if (ids.contains(entry.key)) entry.key: entry.value,
        });
        final unmapped = e.fieldErrors.keys.any((k) => !ids.contains(k));
        if (_errors.isEmpty || unmapped) _general = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.title, style: context.styleH2)),
            IconButton(
              tooltip: 'Tutup',
              icon: const Icon(Icons.close, size: 20),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        if (widget.subtitle != null) Text(widget.subtitle!, style: context.styleSoft),
        for (final f in widget.fields) _field(context, f),
        if (_general != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_general!, style: context.styleError),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Row(
            children: [
              Expanded(
                child: CustomButton(
                  label: 'Batal',
                  variant: ButtonVariant.outline,
                  expanded: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomButton(
                  label: _saving ? 'Menyimpan…' : widget.submitLabel,
                  expanded: true,
                  onPressed: _saving || _uploading > 0 ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(BuildContext context, CmsField f) {
    final error = _errors[f.id];
    switch (f) {
      case CmsTextField():
        return LabeledField(
          label: f.label,
          controller: _controllers[f.id],
          hint: f.hint,
          maxLines: f.lines,
          keyboardType: f.number ? TextInputType.number : null,
          inputFormatters: f.number ? [FilteringTextInputFormatter.digitsOnly] : null,
          error: error,
        );
      case CmsChoiceField():
        return LabeledDropdown<String>(
          label: f.label,
          value: _state[f.id]! as String,
          items: [for (final o in f.options) o.$1],
          itemLabel: (v) => f.options.firstWhere((o) => o.$1 == v).$2,
          onChanged: (v) => setState(() => _state[f.id] = v),
        );
      case CmsToggleField():
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.label, style: context.styleMedium),
            value: _state[f.id]! as bool,
            onChanged: (v) => setState(() => _state[f.id] = v),
          ),
        );
      case CmsDateField():
        final date = _state[f.id] as DateTime?;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(f.label),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                CustomButton(
                  label: date == null ? 'Pilih tanggal' : formatDateLong(date),
                  variant: ButtonVariant.outline,
                  icon: Icons.calendar_today,
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? now,
                      firstDate: DateTime(now.year - 10),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) setState(() => _state[f.id] = picked);
                  },
                ),
                if (f.clearable && date != null)
                  CustomButton(
                    label: 'Hapus tanggal',
                    variant: ButtonVariant.secondary,
                    onPressed: () => setState(() => _state[f.id] = null),
                  ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(error, style: context.styleError),
              ),
          ],
        );
      case CmsImageField():
        return CmsImageInput(
          label: f.label,
          url: _state[f.id] as String?,
          error: error,
          onChanged: (url) => setState(() => _state[f.id] = url),
          onBusy: (busy) => setState(() => _uploading += busy ? 1 : -1),
        );
      case CmsImagesField():
        return CmsImagesInput(
          label: f.label,
          urls: List<String>.of(_state[f.id]! as List<String>),
          error: error,
          onChanged: (urls) => setState(() => _state[f.id] = urls),
          onBusy: (busy) => setState(() => _uploading += busy ? 1 : -1),
        );
    }
  }
}

class CmsThumb extends StatelessWidget {
  const CmsThumb(this.url, {super.key, this.size = 72});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolved = resolveMediaUrl(url);
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.mi, borderRadius: BorderRadius.circular(10)),
      child: Icon(Icons.image_not_supported_outlined, size: size / 3, color: c.sl),
    );
    if (resolved == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

Future<String?> _pickAndUpload(
  WidgetRef ref, {
  required void Function(String message) onError,
}) async {
  final picked = await ref.read(mediaPickerProvider).pick();
  if (picked == null) return null;
  try {
    return await ref
        .read(adminRepositoryProvider)
        .uploadMedia(filename: picked.name, bytes: picked.bytes);
  } on ApiException catch (e) {
    onError(e.fieldErrors['file'] ?? e.message);
    return null;
  }
}

class CmsImageInput extends ConsumerStatefulWidget {
  const CmsImageInput({
    super.key,
    required this.label,
    required this.url,
    required this.onChanged,
    this.onBusy,
    this.error,
  });

  final String label;
  final String? url;
  final ValueChanged<String?> onChanged;
  final ValueChanged<bool>? onBusy;
  final String? error;

  @override
  ConsumerState<CmsImageInput> createState() => _CmsImageInputState();
}

class _CmsImageInputState extends ConsumerState<CmsImageInput> {
  var _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    final url = await _pickAndUploadGuarded();
    if (url != null) widget.onChanged(url);
  }

  Future<String?> _pickAndUploadGuarded() async {
    widget.onBusy?.call(true);
    setState(() => _busy = true);
    try {
      return await _pickAndUpload(ref, onError: (m) => _error = m);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusy?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final error = _error ?? widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(widget.label),
        Row(
          children: [
            if (url != null) ...[CmsThumb(url, size: 88), const SizedBox(width: 12)],
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CustomButton(
                    label: _busy ? 'Mengunggah…' : (url == null ? 'Pilih Gambar' : 'Ganti Gambar'),
                    variant: ButtonVariant.secondary,
                    compact: true,
                    onPressed: _busy ? null : _pick,
                  ),
                  if (url != null)
                    CustomButton(
                      label: 'Hapus Gambar',
                      variant: ButtonVariant.outline,
                      compact: true,
                      onPressed: _busy ? null : () => widget.onChanged(null),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error, style: context.styleError),
          ),
      ],
    );
  }
}

class CmsImagesInput extends ConsumerStatefulWidget {
  const CmsImagesInput({
    super.key,
    required this.label,
    required this.urls,
    required this.onChanged,
    this.onBusy,
    this.error,
  });

  final String label;
  final List<String> urls;
  final ValueChanged<List<String>> onChanged;
  final ValueChanged<bool>? onBusy;
  final String? error;

  @override
  ConsumerState<CmsImagesInput> createState() => _CmsImagesInputState();
}

class _CmsImagesInputState extends ConsumerState<CmsImagesInput> {
  var _busy = false;
  String? _error;

  Future<void> _add() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    widget.onBusy?.call(true);
    try {
      final url = await _pickAndUpload(ref, onError: (m) => _error = m);
      if (url != null) widget.onChanged([...widget.urls, url]);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusy?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error ?? widget.error;
    final full = widget.urls.length >= kMaxActivityPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel('${widget.label} (${widget.urls.length}/$kMaxActivityPhotos)'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < widget.urls.length; i++)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CmsThumb(widget.urls[i], size: 80),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton.filled(
                      tooltip: 'Hapus foto ${i + 1}',
                      iconSize: 14,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close),
                      onPressed: _busy
                          ? null
                          : () => widget.onChanged([...widget.urls]..removeAt(i)),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        CustomButton(
          label: _busy ? 'Mengunggah…' : 'Tambah Foto',
          variant: ButtonVariant.secondary,
          compact: true,
          onPressed: _busy || full ? null : _add,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error, style: context.styleError),
          ),
      ],
    );
  }
}
