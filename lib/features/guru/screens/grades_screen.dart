import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/guru_repository.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/form_fields.dart';

class GradesScreen extends ConsumerWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider(Scopes.grades));
    final grades = ref.watch(gradesProvider);
    final isWali = ref.watch(isWaliProvider);
    final cls = ref.watch(selectedClassProvider);
    final async = ref.watch(currentClassAsyncProvider);
    final data = ref.watch(currentClassDataProvider);
    final visible = [
      for (final g in grades)
        if (filter == 'all' || g.category.label == filter) g,
    ];

    if (async.isLoading && !async.hasValue) {
      return const ScreenScaffold(title: 'Nilai', children: [LoadingList()]);
    }
    if (async.hasError && !async.hasValue) {
      return ScreenScaffold(title: 'Nilai', children: [
        ErrorRetry(
          error: async.error!,
          onRetry: () => ref.invalidate(classDataAsyncProvider(cls)),
        ),
      ]);
    }

    return ScreenScaffold(
      title: 'Nilai',
      banner: ref.watch(waliBannerProvider),
      children: [
        TwoColumnGrid(
          children: [
            _AverageCard(
              label: 'Literasi',
              value: ref.watch(averageProvider(SubjectCategory.literasi)),
              series: data.literasiTrend,
            ),
            _AverageCard(
              label: 'Numerasi',
              value: ref.watch(averageProvider(SubjectCategory.numerasi)),
              series: data.numerasiTrend,
            ),
          ],
        ),
        if (!isWali)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: CustomButton(
              label: '+ Tambah Nilai',
              expanded: true,
              onPressed: () => showGradeFormSheet(context),
            ),
          )
        else
          const SizedBox(height: 12),
        FilterChips(
          options: [
            ('all', 'Semua'),
            for (final k in SubjectCategory.values) (k.label, k.label),
          ],
          selected: filter,
          onSelected: (v) => ref.read(filterProvider(Scopes.grades).notifier).set(v),
        ),
        if (visible.isEmpty)
          const EmptyState('Belum ada data nilai.')
        else
          CustomCard(
            child: RowList(
              children: [
                for (final g in visible)
                  PersonRow(
                    name: g.studentName,
                    subtitle: '${g.category.label} · ${g.assessment} · ${formatDate(g.date)}',
                    trailing: Text('${g.value}', style: context.styleNum),
                    onTap: () => pushPage(context, GradeDetailScreen(gradeId: g.id)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AverageCard extends StatelessWidget {
  const _AverageCard({required this.label, required this.value, required this.series});

  final String label;
  final int value;
  final List<int> series;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kick(label),
          Text('$value', style: context.styleBig),
          Sparkline(series, height: 30),
        ],
      ),
    );
  }
}

class GradeDetailScreen extends ConsumerStatefulWidget {
  const GradeDetailScreen({super.key, required this.gradeId});

  final int gradeId;

  @override
  ConsumerState<GradeDetailScreen> createState() => _GradeDetailScreenState();
}

class _GradeDetailScreenState extends ConsumerState<GradeDetailScreen> {
  GradeEntry? _lastKnown;

  @override
  Widget build(BuildContext context) {
    final current = ref
        .watch(gradesProvider)
        .where((g) => g.id == widget.gradeId)
        .firstOrNull;
    final grade = current ?? _lastKnown;
    _lastKnown = grade;
    final isWali = ref.watch(isWaliProvider);

    return ScreenScaffold(
      title: 'Detail Nilai',
      banner: ref.watch(waliBannerProvider),
      children: [
        if (grade == null)
          const EmptyState('Nilai tidak ditemukan.')
        else ...[
          CustomCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Kick(grade.category.label),
                Text('${grade.value}', style: context.styleBig),
                Text(
                  '${grade.value >= grade.previous ? '▲' : '▼'} ${(grade.value - grade.previous).abs()} dari nilai sebelumnya (${grade.previous})',
                  style: context.styleCaption,
                ),
                RowList(
                  dividerBeforeFirst: false,
                  children: [
                    DetailRow(label: 'Siswa', value: grade.studentName, labelWidth: 96),
                    DetailRow(label: 'Penilaian', value: grade.assessment, labelWidth: 96),
                    DetailRow(label: 'Tanggal', value: formatDate(grade.date), labelWidth: 96),
                    DetailRow(
                      label: 'Catatan guru',
                      value: grade.note.isEmpty ? '—' : grade.note,
                      labelWidth: 96,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isWali)
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: 'Edit',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => showGradeFormSheet(context, gradeId: grade.id),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: 'Hapus',
                    variant: ButtonVariant.danger,
                    expanded: true,
                    onPressed: () => showConfirmDialog(
                      context,
                      message: 'Apakah Anda yakin ingin menghapus nilai ini?',
                      confirmLabel: 'Hapus',
                      onConfirm: () async {
                        final error = await ref
                            .read(classDataAsyncProvider(ref.read(selectedClassProvider)).notifier)
                            .deleteGrade(grade.id);
                        if (error != null) {
                          AppToast.show(error);
                          return;
                        }
                        AppToast.show('Nilai berhasil dihapus.');
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

void showGradeFormSheet(
  BuildContext context, {
  int? gradeId,
  bool openGradesAfter = false,
}) {
  final container = ProviderScope.containerOf(context);
  if (container.read(isWaliProvider)) {
    AppToast.show('Wali Kelas hanya dapat melihat.');
    return;
  }

  showAppSheet<bool>(
    context,
    builder: (_) => _GradeForm(gradeId: gradeId),
  ).then((saved) {
    if (saved == true && openGradesAfter && context.mounted) {
      pushPage(context, const GradesScreen());
    }
  });
}

class _GradeForm extends ConsumerStatefulWidget {
  const _GradeForm({this.gradeId});

  final int? gradeId;

  @override
  ConsumerState<_GradeForm> createState() => _GradeFormState();
}

class _GradeFormState extends ConsumerState<_GradeForm> {
  late final List<Student> _students = ref.read(studentsProvider);
  late final GradeEntry? _existing = ref
      .read(gradesProvider)
      .where((g) => g.id == widget.gradeId)
      .firstOrNull;

  late int _studentId = _existing?.studentId ?? _students.first.id;
  late String _assessment = _existing?.assessment ?? AssessmentTypes.all.first;
  late SubjectCategory _category = _existing?.category ?? SubjectCategory.literasi;
  late DateTime _date = _existing?.date ?? ref.read(todayProvider);
  late final _value = TextEditingController(text: _existing?.value.toString() ?? '');
  late final _note = TextEditingController(text: _existing?.note ?? '');
  late final _dateText = TextEditingController(text: formatDate(_date));

  String? _valueError;
  var _saving = false;

  List<String> get _assessmentOptions => [
        ...AssessmentTypes.all,
        if (!AssessmentTypes.all.contains(_assessment)) _assessment,
      ];

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _dateText.text = formatDate(picked);
    });
  }

  Future<void> _save() async {
    final raw = _value.text.trim();
    final value = int.tryParse(raw);
    setState(() {
      _valueError = raw.isEmpty
          ? 'Nilai wajib diisi.'
          : (value == null || value < 0 || value > 100)
              ? 'Masukkan nilai antara 0–100.'
              : null;
    });
    if (_valueError != null) return;

    final cls = ref.read(selectedClassProvider);
    final notifier = ref.read(classDataAsyncProvider(cls).notifier);
    final isEdit = _existing != null;
    final input = GradeInput(
      studentId: _studentId,
      category: _category,
      assessment: _assessment,
      value: value!,
      date: _date,
      note: _note.text.trim(),
    );

    setState(() => _saving = true);
    final error =
        isEdit ? await notifier.updateGrade(_existing.id, input) : await notifier.addGrade(input);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      AppToast.show(error);
      return;
    }

    Navigator.of(context).pop(!isEdit);
    AppToast.show(isEdit ? 'Nilai berhasil diperbarui.' : 'Nilai berhasil ditambahkan.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_existing == null ? 'Tambah Nilai' : 'Edit Nilai', style: context.styleH2),
        LabeledDropdown<int>(
          label: 'Pilih siswa',
          value: _studentId,
          items: [for (final s in _students) s.id],
          itemLabel: (id) => _students.firstWhere((s) => s.id == id).name,
          onChanged: (v) => setState(() => _studentId = v),
        ),
        LabeledDropdown<String>(
          label: 'Jenis penilaian',
          value: _assessment,
          items: _assessmentOptions,
          itemLabel: (n) => n,
          onChanged: (v) => setState(() => _assessment = v),
        ),
        const FieldLabel('Kategori'),
        RadioGroup<SubjectCategory>(
          groupValue: _category,
          onChanged: (v) => setState(() => _category = v ?? _category),
          child: Row(
            children: [
              for (final k in SubjectCategory.values) ...[
                if (k != SubjectCategory.values.first) const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => setState(() => _category = k),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: c.si),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Radio<SubjectCategory>(
                            value: k,
                            activeColor: c.ink,
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(k.label, style: context.styleBadge),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        LabeledField(
          label: 'Nilai (0–100)',
          controller: _value,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          error: _valueError,
        ),
        LabeledField(
          label: 'Tanggal',
          controller: _dateText,
          readOnly: true,
          onTap: _pickDate,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        LabeledField(label: 'Catatan', controller: _note, maxLines: 2),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: CustomButton(
                label: 'Batal',
                variant: ButtonVariant.outline,
                expanded: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomButton(
                label: 'Simpan Nilai',
                expanded: true,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
