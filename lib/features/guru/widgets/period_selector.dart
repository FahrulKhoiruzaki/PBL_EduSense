import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/academic_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/common_widgets.dart';

/// Filter tahun ajaran dan semester. Nilai `null` = periode aktif (ditentukan admin).
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(periodsProvider);
    final selected = ref.watch(selectedPeriodProvider);

    return periods.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => InfoBanner(
        'Daftar periode akademik gagal dimuat.',
        child: Row(
          children: [
            Expanded(child: Text('Daftar periode gagal dimuat.', style: context.styleMedium)),
            TextButton(
              onPressed: () => ref.invalidate(periodsProvider),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const InfoBanner(
            'Periode akademik belum ditetapkan admin. Data ditampilkan tanpa filter semester.',
          );
        }
        final active = list.where((p) => p.active).firstOrNull;
        final value = list.any((p) => p.id == selected) ? selected : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int?>(
            key: ValueKey('periode-$value'),
            initialValue: value,
            isExpanded: true,
            style: context.styleBody,
            decoration: const InputDecoration(labelText: 'Tahun ajaran & semester'),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(
                  active == null ? 'Periode aktif (belum ditetapkan)' : '${_label(active)} (aktif)',
                ),
              ),
              for (final p in list)
                if (!p.active) DropdownMenuItem<int?>(value: p.id, child: Text(_label(p))),
            ],
            onChanged: (v) => ref.read(selectedPeriodProvider.notifier).select(v),
          ),
        );
      },
    );
  }
}

String _label(AcademicPeriod p) => 'Semester ${p.semesterLabel} ${p.academicYear}';
