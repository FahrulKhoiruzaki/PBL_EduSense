import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/form_fields.dart';
import '../actions/guard_admin.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_common.dart';

List<String> academicYearOptions(String current) {
  final start = int.tryParse(current.split('/').first) ?? DateTime.now().year;
  return [for (var y = start - 1; y <= start + 1; y++) '$y/${y + 1}'];
}

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  late String _year = ref.read(adminDatasetProvider).academicYear;
  late final _lateLimit = TextEditingController(text: ref.read(adminDatasetProvider).lateLimit);
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _repeatPassword = TextEditingController();

  String? _oldError;
  String? _newError;
  String? _repeatError;
  var _savingSettings = false;
  var _savingPassword = false;

  @override
  void dispose() {
    _lateLimit.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    _repeatPassword.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _savingSettings = true);
    final done = await guardAdmin(() async {
      await ref
          .read(adminDataProvider.notifier)
          .saveSettings(academicYear: _year, lateLimit: _lateLimit.text.trim());
      return true;
    });
    if (!mounted) return;
    setState(() => _savingSettings = false);
    if (done == true) AppToast.show('Pengaturan berhasil disimpan.');
  }

  Future<void> _changePassword() async {
    final oldValue = _oldPassword.text;
    final newValue = _newPassword.text;
    final repeatValue = _repeatPassword.text;

    final oldError = oldValue.isEmpty ? 'Kolom ini wajib diisi.' : null;
    final newError = newValue.isEmpty
        ? 'Kolom ini wajib diisi.'
        : newValue.length < 8
        ? 'Minimal 8 karakter.'
        : null;
    final repeatError = repeatValue.isEmpty
        ? 'Kolom ini wajib diisi.'
        : repeatValue != newValue
        ? 'Password tidak sama.'
        : null;

    setState(() {
      _oldError = oldError;
      _newError = newError;
      _repeatError = repeatError;
    });
    if (oldError != null || newError != null || repeatError != null) return;

    setState(() => _savingPassword = true);
    try {
      await ref
          .read(adminDataProvider.notifier)
          .changeMyPassword(oldPassword: oldValue, newPassword: newValue);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
        final wrongOld = e.type == ApiErrorType.validation || e.type == ApiErrorType.forbidden;
        if (wrongOld) {
          _oldError = e.fieldErrors['old_password'] ?? 'Password lama tidak sesuai.';
          _newError = e.fieldErrors['new_password'];
        } else {
          AppToast.show(e.message);
        }
      });
      return;
    }
    if (!mounted) return;
    setState(() => _savingPassword = false);
    AppToast.show('Password berhasil diganti.');
    _oldPassword.clear();
    _newPassword.clear();
    _repeatPassword.clear();
  }

  Widget _card(String title, List<Widget> children) {
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.styleH2),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      adminDatasetProvider.select((d) => (d.academicYear, d.lateLimit)),
      (_, next) => setState(() {
        _year = next.$1;
        _lateLimit.text = next.$2;
      }),
    );
    final years = academicYearOptions(_year);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Pengaturan'),
        ResponsiveGrid(
          minItemWidth: 320,
          equalHeight: false,
          children: [
            _card('Data sekolah', [
              LabeledDropdown<String>(
                key: ValueKey(_year),
                label: 'Tahun ajaran',
                value: years.contains(_year) ? _year : years[1],
                items: years,
                itemLabel: (v) => v,
                onChanged: (v) => _year = v,
              ),
              LabeledField(
                label: 'Batas jam terlambat',
                controller: _lateLimit,
                hint: 'Contoh: 07:15',
              ),
              const SizedBox(height: 16),
              CustomButton(
                label: 'Simpan Pengaturan',
                onPressed: _savingSettings ? null : _saveSettings,
              ),
            ]),
            _card('Ganti password admin', [
              LabeledField(
                label: 'Password lama',
                controller: _oldPassword,
                obscureText: true,
                error: _oldError,
              ),
              LabeledField(
                label: 'Password baru',
                controller: _newPassword,
                obscureText: true,
                error: _newError,
              ),
              LabeledField(
                label: 'Ulangi password baru',
                controller: _repeatPassword,
                obscureText: true,
                error: _repeatError,
              ),
              const SizedBox(height: 16),
              CustomButton(
                label: 'Ganti Password',
                onPressed: _savingPassword ? null : _changePassword,
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
