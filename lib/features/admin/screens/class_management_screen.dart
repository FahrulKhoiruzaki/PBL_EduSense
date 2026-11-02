import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import '../actions/class_actions.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_common.dart';

class ClassManagementScreen extends ConsumerWidget {
  const ClassManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(selectedClassCodeProvider);
    return code == null ? const _ClassListView() : _ClassDetailView(code: code);
  }
}

class _ClassListView extends ConsumerWidget {
  const _ClassListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminDatasetProvider);
    final classes = ref.watch(filteredClassesProvider);
    final filter = ref.watch(classFilterProvider);
    final withoutWali = data.classes.values.where((k) => k.waliId == null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Struktur Kelas',
          action: CustomButton(label: '+ Tambah Kelas', onPressed: () => startAddClass(context)),
        ),
        const AdminToolbar(search: AdminSearchField(hint: 'Cari kelas atau wali kelas')),
        AdminChipBar<ClassFilter>(
          options: [
            (ClassFilter.all, 'Semua (${data.classes.length})'),
            (ClassFilter.noWali, 'Tanpa wali kelas ($withoutWali)'),
          ],
          selected: filter,
          onSelected: (v) => ref.read(classFilterProvider.notifier).set(v),
        ),
        if (classes.isEmpty)
          const EmptyState('Kelas tidak ditemukan.')
        else
          ResponsiveGrid(
            minItemWidth: 250,
            collapseEmpty: false,
            children: [
              for (final k in classes)
                _ClassCard(
                  kelas: k,
                  waliName: data.guruById(k.waliId)?.name,
                  studentCount: data.studentsOf(k.code).length,
                ),
            ],
          ),
      ],
    );
  }
}

class _ClassCard extends ConsumerWidget {
  const _ClassCard({required this.kelas, required this.waliName, required this.studentCount});

  final Kelas kelas;
  final String? waliName;
  final int studentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      onTap: () => ref.read(activeMenuProvider.notifier).openClass(kelas.code),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('Kelas ${kelas.code}', style: context.styleH2)),
              if (waliName == null)
                const StatusBadge(
                  label: 'Tanpa wali',
                  icon: Icons.flag,
                  variant: BadgeVariant.perlu,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Wali kelas: ${waliName ?? 'Belum ada'}', style: context.styleSoft),
          const SizedBox(height: 4),
          Text(
            '${kelas.mapelIds.length} guru mapel · $studentCount siswa',
            style: context.styleAdminCaption,
          ),
        ],
      ),
    );
  }
}

class _ClassDetailView extends ConsumerWidget {
  const _ClassDetailView({required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminDatasetProvider);
    final nav = ref.read(activeMenuProvider.notifier);
    final kelas = data.classes[code];

    final back = LinkText('← Struktur Kelas', onTap: nav.closeClass);

    if (kelas == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [back, const EmptyState('Kelas tidak ditemukan.')],
      );
    }

    final studentCount = data.studentsOf(code).length;
    final wali = data.guruById(kelas.waliId);

    final leftColumn = Column(
      children: [
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                title: 'Wali kelas',
                action: CustomButton(
                  label: wali == null ? 'Tetapkan' : 'Ganti',
                  variant: ButtonVariant.secondary,
                  compact: true,
                  onPressed: () => startSetWali(context, code),
                ),
              ),
              if (wali == null)
                const StatusBadge(
                  label: 'Belum ada wali kelas',
                  icon: Icons.flag,
                  variant: BadgeVariant.perlu,
                )
              else ...[
                Text(wali.name, style: context.styleH2),
                Text(wali.email, style: context.styleAdminCaption),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        CustomCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                title: 'Guru mapel',
                action: CustomButton(
                  label: '+ Tambah',
                  variant: ButtonVariant.secondary,
                  compact: true,
                  onPressed: () => startAddMapel(context, code),
                ),
              ),
              if (kelas.mapelIds.isEmpty)
                const EmptyState('Belum ada guru mapel.')
              else
                RowList(
                  children: [
                    for (final id in kelas.mapelIds)
                      _MapelRow(
                        name: data.guruById(id)?.name ?? id,
                        email: data.guruById(id)?.email ?? '',
                        onRemove: () => startRemoveMapel(context, code, id),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: back),
        PageHeader(
          title: 'Kelas $code',
          action: Tooltip(
            message: studentCount > 0 ? 'Kosongkan kelas terlebih dahulu' : '',
            child: CustomButton(
              label: 'Hapus Kelas',
              variant: ButtonVariant.danger,
              onPressed: studentCount > 0 ? null : () => startDeleteClass(context, code),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final studentsCard = _StudentsCard(code: code, total: studentCount);
            if (box.maxWidth < 760) {
              return Column(children: [leftColumn, const SizedBox(height: 14), studentsCard]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 10, child: leftColumn),
                const SizedBox(width: 14),
                Expanded(flex: 16, child: studentsCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(title, style: context.styleKick)),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}

class _MapelRow extends StatelessWidget {
  const _MapelRow({required this.name, required this.email, required this.onRemove});

  final String name;
  final String email;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: context.styleBold),
                Text(email, style: context.styleAdminCaption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CustomButton(
            label: 'Lepas',
            variant: ButtonVariant.outline,
            compact: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _StudentsCard extends ConsumerWidget {
  const _StudentsCard({required this.code, required this.total});

  final String code;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(classStudentsProvider(code));
    final selected = ref.watch(selectedStudentsProvider);
    final selection = ref.read(selectedStudentsProvider.notifier);
    final page = paginate(students, ref.watch(paginationPageProvider), AdminPageSize.students);
    final pageIds = [for (final s in page.items) s.id];
    final allChecked = pageIds.isNotEmpty && pageIds.every(selected.contains);

    return CustomCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Siswa ($total)',
            action: CustomButton(
              label: 'Pindahkan terpilih (${selected.length})',
              compact: true,
              onPressed: selected.isEmpty
                  ? null
                  : () => startMoveStudents(context, selected.toList()),
            ),
          ),
          const SizedBox(height: 8),
          const AdminToolbar(search: AdminSearchField(hint: 'Cari siswa')),
          if (students.isEmpty)
            EmptyState(total > 0 ? 'Siswa tidak ditemukan.' : 'Kelas ini belum memiliki siswa.')
          else ...[
            AdminDataTable(
              columns: [
                AdminColumn(
                  '',
                  width: 40,
                  header: AdminCheckbox(
                    value: allChecked,
                    label: 'Pilih semua di halaman ini',
                    onChanged: (v) => selection.setAll(pageIds, v),
                  ),
                ),
                const AdminColumn('Nama', flex: 3),
                const AdminColumn('Akun orang tua', flex: 4),
                const AdminColumn('', width: 110),
              ],
              rows: [
                for (final s in page.items)
                  [
                    AdminCheckbox(
                      value: selected.contains(s.id),
                      label: 'Pilih ${s.name}',
                      onChanged: (v) => selection.toggle(s.id, v),
                    ),
                    Text(s.name, style: context.styleBold),
                    Text(s.email, style: context.styleAdminCaption),
                    CustomButton(
                      label: 'Pindahkan',
                      variant: ButtonVariant.outline,
                      compact: true,
                      onPressed: () => startMoveStudents(context, [s.id]),
                    ),
                  ],
              ],
              minFlexWidth: 360,
            ),
            PaginationBar(page: page.page, totalPages: page.totalPages, total: page.total),
          ],
        ],
      ),
    );
  }
}
