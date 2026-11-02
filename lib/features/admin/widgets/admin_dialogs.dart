import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/form_fields.dart';

BuildContext adminDialogContext(BuildContext fallback) =>
    rootNavigatorKey.currentContext ?? fallback;

Future<T?> _showAdminDialog<T>(BuildContext context, Widget child) {
  return showDialog<T>(
    context: context,
    barrierColor: scrimColor,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child),
      ),
    ),
  );
}

class _DialogButtons extends StatelessWidget {
  const _DialogButtons({required this.cancel, required this.confirm});

  final Widget cancel;
  final Widget confirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Expanded(child: cancel),
          const SizedBox(width: 8),
          Expanded(child: confirm),
        ],
      ),
    );
  }
}

Future<void> showAdminConfirm(
  BuildContext context, {
  required String title,
  String? description,
  required String confirmLabel,
  required VoidCallback onConfirm,
  bool destructive = true,
}) async {
  final confirmed = await _showAdminDialog<bool>(
    context,
    Builder(
      builder: (dialogContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: dialogContext.styleH2),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(description, style: dialogContext.styleSoft),
            ),
          _DialogButtons(
            cancel: CustomButton(
              label: 'Batal',
              variant: ButtonVariant.outline,
              expanded: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            confirm: CustomButton(
              label: confirmLabel,
              variant: destructive ? ButtonVariant.danger : ButtonVariant.primary,
              expanded: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) onConfirm();
}

Future<void> showAdminDeleteConfirm(
  BuildContext context, {
  required String title,
  required String description,
  required VoidCallback onConfirm,
}) async {
  final confirmed = await _showAdminDialog<bool>(
    context,
    _DeleteConfirmBody(title: title, description: description),
  );
  if (confirmed == true) onConfirm();
}

class _DeleteConfirmBody extends StatefulWidget {
  const _DeleteConfirmBody({required this.title, required this.description});

  final String title;
  final String description;

  @override
  State<_DeleteConfirmBody> createState() => _DeleteConfirmBodyState();
}

class _DeleteConfirmBodyState extends State<_DeleteConfirmBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _controller.text == 'HAPUS';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: context.styleH2),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(widget.description, style: context.styleSoft),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Ketik '),
                TextSpan(
                  text: 'HAPUS',
                  style: context.styleBold.copyWith(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' untuk melanjutkan'),
              ],
            ),
            style: context.styleMedium,
          ),
        ),
        TextField(
          controller: _controller,
          autocorrect: false,
          style: context.styleBody,
          onChanged: (_) => setState(() {}),
        ),
        _DialogButtons(
          cancel: CustomButton(
            label: 'Batal',
            variant: ButtonVariant.outline,
            expanded: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          confirm: CustomButton(
            label: 'Hapus Permanen',
            variant: ButtonVariant.danger,
            expanded: true,
            onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
          ),
        ),
      ],
    );
  }
}

class AdminFormField {
  const AdminFormField({
    required this.id,
    required this.label,
    this.hint,
    this.initial = '',
    this.options,
    this.isEmail = false,
    this.validator,
  });

  final String id;
  final String label;
  final String? hint;
  final String initial;
  final List<(String, String)>? options;
  final bool isEmail;
  final String? Function(String value, Map<String, String> values)? validator;
}

Future<void> showAdminFormDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<AdminFormField> fields,
  required String submitLabel,
  required void Function(Map<String, String> values) onSubmit,
}) async {
  final values = await _showAdminDialog<Map<String, String>>(
    context,
    _FormBody(title: title, subtitle: subtitle, fields: fields, submitLabel: submitLabel),
  );
  if (values != null) onSubmit(values);
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$', caseSensitive: false);

class _FormBody extends StatefulWidget {
  const _FormBody({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.submitLabel,
  });

  final String title;
  final String? subtitle;
  final List<AdminFormField> fields;
  final String submitLabel;

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      if (f.options == null) f.id: TextEditingController(text: f.initial),
  };
  late final Map<String, String> _selected = {
    for (final f in widget.fields)
      if (f.options != null)
        f.id: f.options!.any((o) => o.$1 == f.initial) ? f.initial : f.options!.first.$1,
  };
  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = {
      for (final f in widget.fields)
        f.id: (f.options == null ? _controllers[f.id]!.text : _selected[f.id]!).trim(),
    };
    final errors = <String, String?>{};
    for (final f in widget.fields) {
      final value = values[f.id]!;
      if (value.isEmpty) {
        errors[f.id] = 'Kolom ini wajib diisi.';
      } else if (f.isEmail && !_emailPattern.hasMatch(value)) {
        errors[f.id] = 'Format email tidak valid.';
      } else {
        errors[f.id] = f.validator?.call(value, values);
      }
    }
    setState(
      () => _errors
        ..clear()
        ..addAll(errors),
    );
    if (errors.values.every((e) => e == null)) {
      Navigator.of(context).pop(values);
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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        if (widget.subtitle != null) Text(widget.subtitle!, style: context.styleSoft),
        for (final f in widget.fields) _buildField(context, f),
        _DialogButtons(
          cancel: CustomButton(
            label: 'Batal',
            variant: ButtonVariant.outline,
            expanded: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          confirm: CustomButton(label: widget.submitLabel, expanded: true, onPressed: _submit),
        ),
      ],
    );
  }

  Widget _buildField(BuildContext context, AdminFormField f) {
    final options = f.options;
    if (options == null) {
      return LabeledField(
        label: f.label,
        controller: _controllers[f.id],
        hint: f.hint,
        keyboardType: f.isEmail ? TextInputType.emailAddress : null,
        error: _errors[f.id],
      );
    }
    final error = _errors[f.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LabeledDropdown<String>(
          label: f.label,
          value: _selected[f.id]!,
          items: [for (final o in options) o.$1],
          itemLabel: (v) => options.firstWhere((o) => o.$1 == v).$2,
          onChanged: (v) => setState(() => _selected[f.id] = v),
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

Future<void> showCredentialDialog(
  BuildContext context, {
  required String email,
  required String password,
  VoidCallback? onOpenClasses,
}) {
  return _showAdminDialog<void>(
    context,
    Builder(
      builder: (dialogContext) {
        final c = dialogContext.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Akun siap dipakai', style: dialogContext.styleH2),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                'Berikan data ini kepada pemilik akun. Password sementara wajib diganti saat login pertama.',
                style: dialogContext.styleSoft,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: c.mi, borderRadius: BorderRadius.circular(10)),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Email: '),
                    TextSpan(text: email, style: dialogContext.styleBold),
                    const TextSpan(text: '\nPassword sementara: '),
                    TextSpan(text: password, style: dialogContext.styleBold),
                  ],
                ),
                style: dialogContext.styleMedium,
              ),
            ),
            if (onOpenClasses != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CustomButton(
                  label: 'Atur penugasan kelas',
                  variant: ButtonVariant.secondary,
                  expanded: true,
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onOpenClasses();
                  },
                ),
              ),
            _DialogButtons(
              cancel: CustomButton(
                label: 'Salin',
                variant: ButtonVariant.outline,
                expanded: true,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$email / $password'));
                  AppToast.show('Disalin.');
                },
              ),
              confirm: CustomButton(
                label: 'Selesai',
                expanded: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        );
      },
    ),
  );
}
