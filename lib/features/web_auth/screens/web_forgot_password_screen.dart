import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme.dart';
import '../../../repositories/web_auth_repository.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/form_fields.dart';
import 'web_login_screen.dart';

class WebForgotPasswordScreen extends ConsumerStatefulWidget {
  const WebForgotPasswordScreen({super.key});

  @override
  ConsumerState<WebForgotPasswordScreen> createState() => _WebForgotPasswordScreenState();
}

class _WebForgotPasswordScreenState extends ConsumerState<WebForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error;
  String? _banner;
  var _busy = false;
  var _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    setState(() {
      _error = email.isEmpty ? 'Kolom ini wajib diisi.' : null;
      _banner = null;
    });
    if (email.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(webAuthRepositoryProvider).requestPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _banner = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthCardScaffold(
        title: 'Tautan pemulihan telah dikirim',
        children: [
          Text('Periksa email Anda dan ikuti petunjuknya.', style: context.styleSoft),
          const SizedBox(height: 20),
          CustomButton(
            label: 'Kembali ke Login',
            expanded: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return AuthCardScaffold(
      title: 'Lupa password',
      children: [
        Text('Masukkan email Anda. Tautan pemulihan akan dikirim.', style: context.styleSoft),
        LabeledField(
          label: 'Email',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          error: _error,
        ),
        if (_banner != null) InfoBanner(_banner!, margin: const EdgeInsets.only(top: 10)),
        const SizedBox(height: 16),
        CustomButton(
          label: _busy ? 'Mengirim…' : 'Kirim Tautan',
          expanded: true,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 8),
        CustomButton(
          label: 'Kembali ke Login',
          variant: ButtonVariant.outline,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
