import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/form_fields.dart';
import '../providers/web_session_provider.dart';
import 'web_login_screen.dart';

class WebChangePasswordScreen extends ConsumerStatefulWidget {
  const WebChangePasswordScreen({super.key});

  @override
  ConsumerState<WebChangePasswordScreen> createState() => _WebChangePasswordScreenState();
}

class _WebChangePasswordScreenState extends ConsumerState<WebChangePasswordScreen> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _firstError;
  String? _secondError;
  var _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final a = _first.text;
    final b = _second.text;
    final firstError = a.isEmpty
        ? 'Kolom ini wajib diisi.'
        : a.length < 8
            ? 'Minimal 8 karakter.'
            : null;
    final secondError = b.isEmpty
        ? 'Kolom ini wajib diisi.'
        : b != a
            ? 'Password tidak sama.'
            : null;
    setState(() {
      _firstError = firstError;
      _secondError = secondError;
    });
    if (firstError != null || secondError != null) return;

    setState(() => _busy = true);
    final error = await ref.read(webSessionProvider.notifier).completePasswordChange(a);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _secondError = error;
    });
    if (error == null) AppToast.show('Password berhasil diganti.');
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      logo: const AuthLogo(title: 'SDN 02 Pakunden'),
      title: 'Ganti password',
      children: [
        Text(
          'Akun Anda memakai password sementara dari admin sekolah. Buat password baru untuk melanjutkan.',
          style: context.styleSoft,
        ),
        LabeledField(
          label: 'Password baru',
          controller: _first,
          obscureText: true,
          textInputAction: TextInputAction.next,
          error: _firstError,
        ),
        LabeledField(
          label: 'Ulangi password baru',
          controller: _second,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          error: _secondError,
        ),
        const SizedBox(height: 16),
        CustomButton(
          label: _busy ? 'Menyimpan…' : 'Simpan dan Lanjut',
          expanded: true,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 8),
        CustomButton(
          label: 'Batal dan Keluar',
          variant: ButtonVariant.outline,
          expanded: true,
          onPressed: _busy
              ? null
              : () {
                  ref.read(webSessionProvider.notifier).signOut();
                },
        ),
      ],
    );
  }
}
