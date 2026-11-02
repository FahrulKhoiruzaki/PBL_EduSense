import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/form_fields.dart';
import '../../../widgets/sidebar_parts.dart';
import '../data/web_auth_models.dart';
import '../providers/web_session_provider.dart';
import 'web_forgot_password_screen.dart';

class AuthCardScaffold extends StatelessWidget {
  const AuthCardScaffold({
    super.key,
    required this.title,
    required this.children,
    this.logo,
  });

  final String title;
  final List<Widget> children;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: CustomCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ?logo,
                    Text(title, style: context.styleH1.copyWith(fontSize: 30, height: 1.1)),
                    const SizedBox(height: 8),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SidebarLogo(title: title, subtitle: subtitle),
      );
}

class TextLink extends StatelessWidget {
  const TextLink(this.text, {super.key, required this.onTap});

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
            fontSize: 13,
            color: context.colors.ink,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key, required this.role});

  final WebRole role;

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _obscure = true;
  var _busy = false;
  String? _emailError;
  String? _passwordError;
  String? _banner;

  bool get _isAdmin => widget.role == WebRole.admin;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

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
        .read(webSessionProvider.notifier)
        .signIn(email: email, password: password, role: widget.role);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _busy = false;
      _banner = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthCardScaffold(
      logo: AuthLogo(
        title: _isAdmin ? 'Panel Admin' : 'Portal Orang Tua',
        subtitle: 'SDN 02 Pakunden',
      ),
      title: 'Masuk',
      children: _body(context),
    );
  }

  List<Widget> _body(BuildContext context) {
    return [
      Text(
        _isAdmin
            ? 'Kelola struktur kelas dan akun sekolah.'
            : 'Pantau perkembangan belajar anak. Anda hanya dapat melihat data anak Anda.',
        style: context.styleSoft,
      ),
      LabeledField(
        label: 'Email',
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        error: _emailError,
      ),
      LabeledField(
        label: 'Password',
        controller: _password,
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        error: _passwordError,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 16,
        children: [
          if (!_isAdmin)
            TextLink(
              'Lupa password?',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WebForgotPasswordScreen()),
              ),
            ),
          TextLink(
            _obscure ? 'Lihat password' : 'Sembunyikan password',
            onTap: () => setState(() => _obscure = !_obscure),
          ),
        ],
      ),
      if (_banner != null) InfoBanner(_banner!, margin: const EdgeInsets.only(top: 10)),
      const SizedBox(height: 16),
      CustomButton(
        label: _busy ? 'Memuat…' : 'Masuk',
        expanded: true,
        onPressed: _busy ? null : _submit,
      ),
      const SizedBox(height: 8),
      CustomButton(
        label: 'Kembali ke Website',
        variant: ButtonVariant.outline,
        expanded: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }
}
