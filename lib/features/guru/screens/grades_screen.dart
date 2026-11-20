import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../widgets/period_selector.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/guru_repository.dart';
import '../../../widgets/academic_charts.dart';
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
    final subjects = [
      for (final label in {for (final g in grades) g.subjectLabel}) label,
    ]..sort();
    final visible = [
      for (final g in grades)
        if (filter == 'all' || g.subjectLabel == filter) g,
    ];

    if (async.isLoading && !async.hasValue) {
      return const ScreenScaffold(title: 'Nilai', children: [PeriodSelector(), LoadingList()]);
    }
    if (async.hasError && !async.hasValue) {
      return ScreenScaffold(title: 'Nilai', children: [
        const PeriodSelector(),
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
        const PeriodSelector(),
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              if (!isWali) ...[
                Expanded(
                  child: CustomButton(
                    label: '+ Tambah Nilai',
                    expanded: true,
                    onPressed: () => showGradeFormSheet(context),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: CustomButton(
                  label: 'Rekap per Mapel',
                  variant: ButtonVariant.outline,
                  expanded: true,
                  onPressed: () => pushPage(context, const SubjectRecapScreen()),
                ),
              ),
            ],
          ),
        ),
        if (subjects.length > 1)
          FilterChips(
            options: [
              ('all', 'Semua'),
              for (final s in subjects) (s, s),
            ],
            selected: subjects.contains(filter) ? filter : 'all',
            onSelected: (v) => ref.read(filterProvider(Scopes.grades).notifier).set(v),
          ),
        if (visible.isEmpty)
          EmptyState(
            data.period == null
                ? 'Belum ada data nilai.'
                : 'Belum ada nilai pada ${data.period!.label}.',
          )
        else
          CustomCard(
            child: RowList(
              children: [
                for (final g in visible)
                  PersonRow(
                    name: g.studentName,
                    subtitle: '${g.subjectLabel} · ${g.assessment} · ${formatDate(g.date)}',
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
                Kick(grade.subjectLabel),
                Text('${grade.value}', style: context.styleBig),
                Text(
                  '${grade.value >= grade.previous ? '▲' : '▼'} ${(grade.value - grade.previous).abs()} dari nilai sebelumnya (${grade.previous})',
                  style: context.styleCaption,
                ),
                RowList(
                  dividerBeforeFirst: false,
                  children: [
                    DetailRow(label: 'Siswa', value: grade.studentName, labelWidth: 96),
                    DetailRow(
                      label: 'Komponen',
                      value: grade.componentName ?? 'Data lama (tanpa komponen)',
                      labelWidth: 96,
                    ),
                    if (grade.category != null)
                      DetailRow(label: 'Kategori', value: grade.category!.label, labelWidth: 96),
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
    builder: (_) => _GradeFormLoader(gradeId: gradeId),
  ).then((saved) {
    if (saved == true && openGradesAfter && context.mounted) {
      pushPage(context, const GradesScreen());
    }
  });
}

/// Memuat mapel dan komponen yang boleh dinilai guru sebelum menampilkan form.
class _GradeFormLoader extends ConsumerWidget {
  const _GradeFormLoader({this.gradeId});

  final int? gradeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final subjects = ref.watch(classSubjectsProvider(cls));
    final students = ref.watch(studentsProvider);

    Widget closeOnly(String message) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(gradeId == null ? 'Tambah Nilai' : 'Edit Nilai', style: context.styleH2),
            EmptyState(message),
            CustomButton(
              label: 'Tutup',
              variant: ButtonVariant.outline,
              expanded: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );

    return subjects.when(
      loading: () => const LoadingList(count: 3, height: 56),
      error: (e, _) => ErrorRetry(
        error: e,
        onRetry: () => ref.invalidate(classSubjectsProvider(cls)),
      ),
      data: (list) {
        final inputtable = [
          for (final s in list)
            if (s.canInput && s.activeComponents.isNotEmpty) s,
        ];
        if (students.isEmpty) return closeOnly('Belum ada siswa di kelas ini.');
        if (inputtable.isEmpty) {
          return closeOnly(
            list.any((s) => s.canInput)
                ? 'Komponen penilaian untuk mapel Anda pada periode ini belum ditetapkan admin.'
                : 'Anda belum ditugaskan mengajar mata pelajaran di kelas ini. Hubungi admin sekolah.',
          );
        }
        return _GradeForm(gradeId: gradeId, subjects: inputtable);
      },
    );
  }
}

class _GradeForm extends ConsumerStatefulWidget {
  const _GradeForm({this.gradeId, required this.subjects});

  final int? gradeId;
  final List<ClassSubject> subjects;

  @override
  ConsumerState<_GradeForm> createState() => _GradeFormState();
}

class _GradeFormState extends ConsumerState<_GradeForm> {
  late final List<Student> _students = ref.read(studentsProvider);
  late final GradeEntry? _existing = ref
      .read(gradesProvider)
      .where((g) => g.id == widget.gradeId)
      .firstOrNull;
  late final AcademicPeriod? _period = ref.read(currentClassDataProvider).period;

  late int _studentId = _students.any((s) => s.id == _existing?.studentId)
      ? _existing!.studentId
      : _students.first.id;
  late int _subjectId = widget.subjects.any((s) => s.id == _existing?.subjectId)
      ? _existing!.subjectId!
      : widget.subjects.first.id;
  late int _componentId = _initialComponent();
  late DateTime _date = _initialDate();
  late final _value = TextEditingController(text: _existing?.value.toString() ?? '');
  late final _assessment = TextEditingController(
    text: _existing == null || _existing.assessment == _existing.componentName
        ? ''
        : _existing.assessment,
  );
  late final _note = TextEditingController(text: _existing?.note ?? '');
  late final _dateText = TextEditingController(text: formatDate(_date));

  String? _valueError;
  var _saving = false;

  ClassSubject get _subject => widget.subjects.firstWhere((s) => s.id == _subjectId);

  int _initialComponent() {
    final components = _subject.activeComponents;
    return components.any((c) => c.id == _existing?.componentId)
        ? _existing!.componentId!
        : components.first.id;
  }

  DateTime _initialDate() {
    final DateTime day = _existing?.date ?? ref.read(todayProvider);
    final p = _period;
    if (p == null || p.contains(day)) return day;
    return day.isBefore(p.start) ? p.start : p.end;
  }

  @override
  void dispose() {
    _value.dispose();
    _assessment.dispose();
    _note.dispose();
    _dateText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _period?.start ?? DateTime(2020),
      lastDate: _period?.end ?? DateTime(2100),
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
      componentId: _componentId,
      assessment: _assessment.text.trim(),
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
    final components = _subject.activeComponents;
    final component = components.firstWhere((c) => c.id == _componentId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_existing == null ? 'Tambah Nilai' : 'Edit Nilai', style: context.styleH2),
        if (_existing?.isLegacy ?? false)
          const InfoBanner(
            'Nilai ini data lama tanpa mata pelajaran. Pilih mapel dan komponennya untuk menyimpan.',
          ),
        LabeledDropdown<int>(
          label: 'Pilih siswa',
          value: _studentId,
          items: [for (final s in _students) s.id],
          itemLabel: (id) => _students.firstWhere((s) => s.id == id).name,
          onChanged: (v) => setState(() => _studentId = v),
        ),
        LabeledDropdown<int>(
          label: 'Mata pelajaran',
          value: _subjectId,
          items: [for (final s in widget.subjects) s.id],
          itemLabel: (id) {
            final s = widget.subjects.firstWhere((s) => s.id == id);
            return s.type == SubjectType.muatanLokal ? '${s.name} (Muatan Lokal)' : s.name;
          },
          onChanged: (v) => setState(() {
            _subjectId = v;
            _componentId = _subject.activeComponents.first.id;
          }),
        ),
        LabeledDropdown<int>(
          key: ValueKey('komponen-$_subjectId'),
          label: 'Komponen penilaian',
          value: _componentId,
          items: [for (final c in components) c.id],
          itemLabel: (id) => _componentLabel(components.firstWhere((c) => c.id == id)),
          onChanged: (v) => setState(() => _componentId = v),
        ),
        if (component.category == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Komponen ini tidak dihitung untuk klasifikasi Literasi/Numerasi.',
              style: context.styleCaption,
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
          label: 'Keterangan penilaian (opsional)',
          controller: _assessment,
          hint: 'Mis. Tugas Bab 2. Kosong = nama komponen.',
        ),
        LabeledField(
          label: 'Tanggal',
          controller: _dateText,
          readOnly: true,
          onTap: _pickDate,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        if (_period != null)
          Text(
            'Tanggal harus di dalam ${_period.label} '
            '(${formatDate(_period.start)} – ${formatDate(_period.end)}).',
            style: context.styleCaption,
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

String _componentLabel(GradeComponent c) {
  final parts = [
    if (c.category != null) c.category!.label,
    if (c.weight != null) 'bobot ${formatScore(c.weight)}',
  ];
  return parts.isEmpty ? c.name : '${c.name} (${parts.join(', ')})';
}

/// Rekap nilai satu mapel di kelas ini: rata-rata per komponen dan nilai akhir.
class SubjectRecapScreen extends ConsumerStatefulWidget {
  const SubjectRecapScreen({super.key});

  @override
  ConsumerState<SubjectRecapScreen> createState() => _SubjectRecapScreenState();
}

class _SubjectRecapScreenState extends ConsumerState<SubjectRecapScreen> {
  int? _subjectId;

  @override
  Widget build(BuildContext context) {
    final cls = ref.watch(selectedClassProvider);
    final subjects = ref.watch(classSubjectsProvider(cls));

    return ScreenScaffold(
      title: 'Rekap per Mapel',
      children: [
        const PeriodSelector(),
        subjects.when(
          loading: () => const LoadingList(count: 2),
          error: (e, _) =>
              ErrorRetry(error: e, onRetry: () => ref.invalidate(classSubjectsProvider(cls))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState('Belum ada mata pelajaran yang dapat Anda lihat di kelas ini.');
            }
            final selected = list.any((s) => s.id == _subjectId) ? _subjectId! : list.first.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledDropdown<int>(
                  key: ValueKey('rekap-${list.length}-$selected'),
                  label: 'Mata pelajaran',
                  value: selected,
                  items: [for (final s in list) s.id],
                  itemLabel: (id) => list.firstWhere((s) => s.id == id).name,
                  onChanged: (v) => setState(() => _subjectId = v),
                ),
                const SizedBox(height: 12),
                _RecapTable(classCode: cls, subjectId: selected),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecapTable extends ConsumerWidget {
  const _RecapTable({required this.classCode, required this.subjectId});

  final String classCode;
  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (classCode, subjectId);
    return ref.watch(subjectRecapProvider(key)).when(
          loading: () => const LoadingList(count: 2),
          error: (e, _) =>
              ErrorRetry(error: e, onRetry: () => ref.invalidate(subjectRecapProvider(key))),
          data: (recap) {
            if (recap.components.isEmpty) {
              return EmptyState(
                'Komponen penilaian ${recap.subjectName} untuk ${recap.period.label} '
                'belum ditetapkan admin.',
              );
            }
            if (recap.rows.isEmpty) return const EmptyState('Belum ada siswa di kelas ini.');
            int count(GradeStatus s) => recap.rows.where((r) => r.status == s).length;
            final finals = [
              for (final r in recap.rows)
                if (r.finalScore != null) r.finalScore!,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kick('${recap.subjectName} · ${recap.period.label}'),
                      Text(
                        recap.weighted
                            ? 'Nilai akhir = rata-rata berbobot seluruh komponen, hanya bila semua '
                                'komponen aktif sudah dinilai.'
                            : 'Nilai akhir = rata-rata komponen (belum semua komponen berbobot), hanya '
                                'bila semua komponen aktif sudah dinilai.',
                        style: context.styleCaption,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${count(GradeStatus.lengkap)} lengkap · ${count(GradeStatus.belumLengkap)} belum '
                        'lengkap · ${count(GradeStatus.belumDinilai)} belum dinilai '
                        '(${recap.rows.length} siswa)',
                        style: context.styleBold,
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 18,
                          columns: [
                            const DataColumn(label: Text('Siswa')),
                            for (final c in recap.components)
                              DataColumn(
                                numeric: true,
                                label: Text(
                                  [
                                    c.name,
                                    if (c.weight != null) 'bobot ${formatScore(c.weight)}',
                                    if (!c.active) 'nonaktif',
                                  ].join('\n'),
                                ),
                              ),
                            const DataColumn(numeric: true, label: Text('Nilai akhir')),
                            const DataColumn(label: Text('Status')),
                          ],
                          rows: [
                            for (final r in recap.rows)
                              DataRow(cells: [
                                DataCell(Text(r.name)),
                                for (final v in r.componentScores) DataCell(Text(formatScore(v))),
                                DataCell(Text(formatScore(r.finalScore), style: context.styleBold)),
                                DataCell(GradeStatusBadge(r.status, filled: r.filled, required: r.required)),
                              ]),
                          ],
                        ),
                      ),
                      Text(
                        '— = belum ada nilai. Nilai akhir kosong bila penilaian belum lengkap.',
                        style: context.styleCaption,
                      ),
                    ],
                  ),
                ),
                gradeDistributionPanel(
                  finals: finals,
                  students: recap.rows.length,
                  context: '${recap.subjectName} pada ${recap.period.label}',
                ),
                subjectProgressPanel(recap.subjectName, recap.progress),
              ],
            );
          },
        );
  }
}
