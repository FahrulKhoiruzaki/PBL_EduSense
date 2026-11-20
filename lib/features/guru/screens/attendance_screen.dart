import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_router.dart';
import '../../../core/formatters.dart';
import '../navigation/tab_navigation.dart';
import '../../../core/theme.dart';
import 'face_recognition_screen.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/form_fields.dart';
import '../../../widgets/status_badge.dart';

const _viewOnlyMessage = 'Wali Kelas hanya dapat melihat.';

class AttendancePickerScreen extends ConsumerWidget {
  const AttendancePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(myClassesProvider);
    final summaryAsync = ref.watch(classSummariesProvider);
    final summaries = ref.watch(classSummaryMapProvider);

    if (summaryAsync.isLoading && !summaryAsync.hasValue) {
      return const ScreenScaffold(children: [LoadingList()]);
    }
    if (summaryAsync.hasError && !summaryAsync.hasValue) {
      return ScreenScaffold(children: [
        ErrorRetry(
          error: summaryAsync.error!,
          onRetry: () => ref.invalidate(classSummariesProvider),
        ),
      ]);
    }
    return ScreenScaffold(
      children: [
        Text('Pilih Kelas', style: context.styleH1),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Pilih kelas yang akan melakukan absensi.', style: context.styleMuted),
        ),
        CustomCard(
          child: RowList(
            children: [
              for (final code in classes)
                InkWell(
                  onTap: () {
                    ref.read(selectedClassProvider.notifier).select(code);
                    pushPage(context, const AttendanceClassScreen());
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Kelas $code', style: context.styleBold),
                                if (summaries[code] != null)
                                  Text(
                                    '${summaries[code]!.studentCount} siswa',
                                    style: context.styleCaption,
                                  ),
                              ],
                            ),
                          ),
                          if (summaries[code] != null)
                            Text(
                              '${summaries[code]!.attendancePercent}% hadir',
                              style: context.styleBold,
                            ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, size: 20, color: context.colors.ink),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AttendanceClassScreen extends ConsumerWidget {
  const AttendanceClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = ref.watch(selectedClassProvider);
    final summary = ref.watch(attendanceSummaryProvider);
    final isWali = ref.watch(isWaliProvider);
    final filter = ref.watch(filterProvider(Scopes.attendance));
    final list = ref.watch(attendanceListProvider);
    final async = ref.watch(currentClassAsyncProvider);
    final today = ref.watch(todayProvider);

    if (async.isLoading && !async.hasValue) {
      return const ScreenScaffold(backBar: true, children: [LoadingList()]);
    }
    if (async.hasError && !async.hasValue) {
      return ScreenScaffold(backBar: true, children: [
        ErrorRetry(
          error: async.error!,
          onRetry: () => ref.invalidate(classDataAsyncProvider(cls)),
        ),
      ]);
    }

    return ScreenScaffold(
      backBar: true,
      banner: ref.watch(waliBannerProvider),
      children: [
        Text('Absensi Kelas $cls', style: context.styleH1),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Text(
            '${formatFullDate(today)} · ${summary.total} siswa',
            style: context.styleCaption,
          ),
        ),
        const ClassPill(),
        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FiveStats(summary, topMargin: 0),
              ProgressBar(percent: summary.percent),
              const SizedBox(height: 6),
              Text('${summary.percent}% kehadiran', style: context.styleCaption),
            ],
          ),
        ),
        if (!isWali) ...[
          CustomCard(
            dark: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kick('Face Recognition', color: AppColors.onDarkCardMuted),
                Text(
                  'Catat kehadiran siswa menggunakan pengenalan wajah.',
                  style: context.styleH2.copyWith(color: AppColors.onDarkCard),
                ),
                const SizedBox(height: 14),
                CustomButton(
                  label: 'Mulai Face Recognition',
                  expanded: true,
                  onDark: true,
                  onPressed: () {
                    final granted = ref.read(cameraPermissionProvider);
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute<void>(
                        builder: (routeContext) => FaceRecognitionScreen(
                          startAtPermission: !granted,
                          onManualInput: () => showManualAttendanceSheet(routeContext, ref),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: 'Input Manual',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => showManualAttendanceSheet(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: 'Selesaikan Absensi',
                    variant: ButtonVariant.secondary,
                    expanded: true,
                    onPressed: () => showConfirmDialog(
                      context,
                      message: 'Selesaikan absensi Kelas $cls?',
                      confirmLabel: 'Selesaikan',
                      confirmVariant: ButtonVariant.primary,
                      onConfirm: () async {
                        final error =
                            await ref.read(classDataAsyncProvider(cls).notifier).finishAttendance();
                        if (error != null) {
                          AppToast.show(error);
                          return;
                        }
                        AppToast.show('Absensi Kelas $cls selesai.');
                        goTab(ref, 0);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Kick('Daftar kehadiran — Kelas $cls', bottom: 6),
        const SearchField(scope: Scopes.attendance, hint: 'Cari nama siswa'),
        FilterChips(
          options: [
            ('all', 'Semua'),
            for (final s in AttendanceStatus.values) (s.code, s.label),
          ],
          selected: filter,
          onSelected: (v) => ref.read(filterProvider(Scopes.attendance).notifier).set(v),
        ),
        CustomCard(
          child: list.isEmpty
              ? const EmptyState('Siswa tidak ditemukan.')
              : RowList(
                  children: [
                    for (final e in list)
                      PersonRow(
                        name: e.student.name,
                        subtitle: e.student.time.isEmpty ? '—' : e.student.time,
                        trailing: StatusBadge.attendance(e.student.status),
                        onTap: () => showManualAttendanceSheet(context, ref, studentIndex: e.index),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

void showManualAttendanceSheet(BuildContext context, WidgetRef ref, {int? studentIndex}) {
  if (ref.read(isWaliProvider)) {
    AppToast.show(_viewOnlyMessage);
    return;
  }
  showAppSheet<void>(
    context,
    builder: (_) => _ManualAttendanceSheet(initialIndex: studentIndex),
  );
}

class _ManualAttendanceSheet extends ConsumerStatefulWidget {
  const _ManualAttendanceSheet({this.initialIndex});

  final int? initialIndex;

  @override
  ConsumerState<_ManualAttendanceSheet> createState() => _ManualAttendanceSheetState();
}

class _ManualAttendanceSheetState extends ConsumerState<_ManualAttendanceSheet> {
  late int _index = widget.initialIndex ?? 0;
  final _note = TextEditingController();

  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(AttendanceStatus status) async {
    final cls = ref.read(selectedClassProvider);
    final student = ref.read(studentsProvider)[_index];
    setState(() => _saving = true);
    final error = await ref
        .read(classDataAsyncProvider(cls).notifier)
        .setStatus(student.id, status, note: _note.text.trim());
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      AppToast.show(error);
      return;
    }
    Navigator.of(context).pop();
    AppToast.show('Absensi berhasil dicatat.');
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final statuses = AttendanceStatus.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.initialIndex == null ? 'Input Manual' : 'Ubah Status',
                style: context.styleH2,
              ),
            ),
            IconButton(
              tooltip: 'Tutup',
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        Text(
          'Pilih siswa lalu ketuk status. Langsung tersimpan.',
          style: context.styleCaption,
        ),
        LabeledDropdown<int>(
          label: 'Pilih siswa',
          value: _index,
          items: [for (var i = 0; i < students.length; i++) i],
          itemLabel: (i) => students[i].name,
          onChanged: (v) => setState(() => _index = v),
        ),
        LabeledField(label: 'Catatan (opsional)', controller: _note, maxLines: 2),
        const FieldLabel('Status'),
        TwoColumnGrid(
          spacing: 8,
          children: [
            for (final s in statuses)
              CustomButton(
                label: s.label,
                icon: s.icon,
                variant: ButtonVariant.outline,
                expanded: true,
                onPressed: _saving ? null : () => _save(s),
              ),
          ],
        ),
      ],
    );
  }
}

