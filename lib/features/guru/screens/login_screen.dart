import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/form_fields.dart';

class _Monogram extends StatelessWidget {
  const _Monogram();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      margin: const EdgeInsets.only(bottom: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment(-0.34, -0.94),
          end: Alignment(0.34, 0.94),
          colors: [AppColors.darkCardStart, AppColors.darkCardEnd],
        ),
      ),
      child: Text(
        '02',
        style: context.styleBold.copyWith(color: AppColors.onDarkCard),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.initialRole = TeacherRole.waliKelas,
    this.allowRoleSwitch = true,
    this.onAuthenticated,
    this.onCancel,
  });

  /// Peran awal untuk form login. Aplikasi guru tetap menampilkan toggle peran.
  final TeacherRole initialRole;

  /// Website dapat mengunci peran yang dipilih dari halaman pemilihan role.
  final bool allowRoleSwitch;

  /// Dipanggil setelah kredensial guru diterima oleh provider.
  final VoidCallback? onAuthenticated;

  /// Aksi kembali opsional, hanya ditampilkan pada flow website.
  final VoidCallback? onCancel;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late TeacherRole _role;
  var _obscure = true;
  var _remember = false;
  var _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _banner;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setRole(TeacherRole role) => setState(() {
        _role = role;
        _banner = null;
      });

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    setState(() {
      _emailError = email.isEmpty ? 'Kolom ini wajib diisi.' : null;
      _passwordError = password.isEmpty ? 'Kolom ini wajib diisi.' : null;
      _banner = null;
    });
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _busy = true);
    final error = await ref
        .read(sessionProvider.notifier)
        .signIn(email: email, password: password, role: _role);
    if (!mounted) return;
    if (error == null) {
      widget.onAuthenticated?.call();
      return;
    }
    setState(() {
      _busy = false;
      _banner = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notice = ref.watch(sessionProvider.select((s) => s.notice));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              children: [
                const Align(alignment: Alignment.centerLeft, child: _Monogram()),
                Text(
                  widget.allowRoleSwitch
                      ? 'Masuk'
                      : 'Login ${_role == TeacherRole.waliKelas ? 'Wali Kelas' : 'Guru Mapel'}',
                  style: context.styleH1,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pantau perkembangan belajar siswa dengan lebih mudah.',
                  style: context.styleMuted,
                ),
                Text(
                  widget.allowRoleSwitch
                      ? 'Masuk sebagai'
                      : 'Masuk sebagai ${_role == TeacherRole.waliKelas ? 'Wali Kelas' : 'Guru Mapel'}',
                  style: context.styleBold,
                ),
                if (widget.allowRoleSwitch) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          label: 'Wali Kelas',
                          expanded: true,
                          variant: _role == TeacherRole.waliKelas
                              ? ButtonVariant.primary
                              : ButtonVariant.outline,
                          onPressed: () => _setRole(TeacherRole.waliKelas),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomButton(
                          label: 'Guru Mapel',
                          expanded: true,
                          variant: _role == TeacherRole.guruMapel
                              ? ButtonVariant.primary
                              : ButtonVariant.outline,
                          onPressed: () => _setRole(TeacherRole.guruMapel),
                        ),
                      ),
                    ],
                  ),
                ],
                LabeledField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  error: _emailError,
                ),
                LabeledField(
                  label: 'Password',
                  controller: _password,
                  obscureText: _obscure,
                  error: _passwordError,
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _remember,
                            onChanged: (v) => setState(() => _remember = v ?? false),
                            activeColor: c.primary,
                            checkColor: c.su,
                            side: BorderSide(color: c.si, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('Ingat saya', style: context.styleCaption),
                      ],
                    ),
                    _LinkText(
                      'Lupa password?',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                    ),
                    _LinkText(
                      'Lihat password',
                      onTap: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
                if (_banner != null || notice != null)
                  InfoBanner(_banner ?? notice!, margin: const EdgeInsets.only(top: 8)),
                const SizedBox(height: 16),
                CustomButton(
                  label: _busy ? 'Memuat data…' : 'Masuk',
                  expanded: true,
                  onPressed: _busy ? null : _submit,
                ),
                if (widget.onCancel != null) ...[
                  const SizedBox(height: 8),
                  CustomButton(
                    label: 'Kembali ke Pilihan Role',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: _busy ? null : widget.onCancel,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Akun dibuat oleh admin sekolah. Data siswa hanya untuk keperluan sekolah.',
                  style: context.styleCaption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.text, {required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: context.styleCaption.copyWith(
            color: context.colors.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              children: [
                const Align(alignment: Alignment.centerLeft, child: _Monogram()),
                Text('Lupa password', style: context.styleH1Small),
                const SizedBox(height: 16),
                CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reset lewat admin sekolah', style: context.styleH2),
                      const SizedBox(height: 8),
                      Text(
                        'Password akun guru diatur oleh admin sekolah. Hubungi admin untuk meminta password sementara, lalu masuk dan buat password baru.',
                        style: context.styleMuted,
                      ),
                      const SizedBox(height: 16),
                      CustomButton(
                        label: 'Kembali ke Login',
                        expanded: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
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
    final error = await ref.read(sessionProvider.notifier).completePasswordChange(a);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _secondError = error;
    });
    if (error == null) AppToast.show('Password berhasil diganti.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              children: [
                const Align(alignment: Alignment.centerLeft, child: _Monogram()),
                Text('Ganti password', style: context.styleH1Small),
                const SizedBox(height: 6),
                Text(
                  'Akun Anda memakai password sementara dari admin. Buat password baru untuk melanjutkan.',
                  style: context.styleMuted,
                ),
                LabeledField(
                  label: 'Password baru',
                  controller: _first,
                  obscureText: true,
                  error: _firstError,
                ),
                LabeledField(
                  label: 'Ulangi password baru',
                  controller: _second,
                  obscureText: true,
                  error: _secondError,
                ),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'Simpan dan Lanjut',
                  expanded: true,
                  onPressed: _busy ? null : _submit,
                ),
                if (widget.onSignOut != null) ...[
                  const SizedBox(height: 8),
                  CustomButton(
                    label: 'Batal dan Keluar',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: _busy ? null : widget.onSignOut,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
