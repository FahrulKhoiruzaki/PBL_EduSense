import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/status_badge.dart';
import '../data/admin_models.dart';
import '../providers/admin_providers.dart';

export '../../../widgets/responsive_grid.dart';

extension AdminStyles on BuildContext {
  TextStyle get styleAdminCaption => styleCaption.copyWith(fontSize: 13);
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(title, style: context.styleH1.copyWith(fontSize: 30, height: 36 / 30)),
            ?action,
          ],
        ),
      ),
    );
  }
}

class AdminSearchField extends ConsumerStatefulWidget {
  const AdminSearchField({super.key, required this.hint});

  final String hint;

  @override
  ConsumerState<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends ConsumerState<AdminSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(searchQueryProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchQueryProvider, (_, next) {
      if (next != _controller.text) _controller.text = next;
    });
    return TextField(
      controller: _controller,
      style: context.styleBody,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
      onChanged: (value) {
        ref.read(searchQueryProvider.notifier).set(value);
        ref.read(paginationPageProvider.notifier).set(1);
      },
    );
  }
}

class AdminDropdown<T> extends StatelessWidget {
  const AdminDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.semanticLabel,
  });

  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: DropdownButtonFormField<T>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        style: context.styleBody,
        items: [
          for (final item in items) DropdownMenuItem(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class AdminToolbar extends StatelessWidget {
  const AdminToolbar({super.key, required this.search, this.filters = const []});

  final Widget search;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= 560) {
            return Row(
              children: [
                Expanded(child: search),
                for (final f in filters) ...[
                  const SizedBox(width: 10),
                  SizedBox(width: 170, child: f),
                ],
              ],
            );
          }
          return Column(
            children: [
              search,
              for (final f in filters) ...[const SizedBox(height: 10), f],
            ],
          );
        },
      ),
    );
  }
}

class AdminChipBar<T> extends StatelessWidget {
  const AdminChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (value, label) in options)
            Material(
              color: selected == value ? c.ink : c.mi,
              borderRadius: BorderRadius.circular(99),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onSelected(value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: context.styleBody.copyWith(color: selected == value ? c.su : c.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PaginationBar extends ConsumerWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final int page;
  final int totalPages;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(int target) => ref.read(paginationPageProvider.notifier).set(target);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            CustomButton(
              label: '‹ Sebelumnya',
              variant: ButtonVariant.outline,
              compact: true,
              onPressed: page <= 1 ? null : () => go(page - 1),
            ),
            Text('Halaman $page dari $totalPages · $total data', style: context.styleAdminCaption),
            CustomButton(
              label: 'Berikutnya ›',
              variant: ButtonVariant.outline,
              compact: true,
              onPressed: page >= totalPages ? null : () => go(page + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminColumn {
  const AdminColumn(this.label, {this.flex = 1, this.width, this.header});

  final String label;
  final int flex;
  final double? width;
  final Widget? header;
}

class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minFlexWidth = 480,
  });

  final List<AdminColumn> columns;
  final List<List<Widget>> rows;
  final double minFlexWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fixedWidth = columns.fold<double>(0, (sum, col) => sum + (col.width ?? 0));

    Widget cell(AdminColumn col, Widget child) {
      final padded = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Align(alignment: Alignment.centerLeft, child: child),
      );
      return col.width != null
          ? SizedBox(width: col.width, child: padded)
          : Expanded(flex: col.flex, child: padded);
    }

    Widget buildRow(List<Widget> cells, {required bool header}) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: header ? null : Border(top: BorderSide(color: c.mi)),
        ),
        child: Row(children: [for (var i = 0; i < columns.length; i++) cell(columns[i], cells[i])]),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(box.maxWidth, fixedWidth + minFlexWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                buildRow([
                  for (final col in columns)
                    col.header ?? Text(col.label, style: context.styleKick),
                ], header: true),
                for (final r in rows) buildRow(r, header: false),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AdminCheckbox extends StatelessWidget {
  const AdminCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: c.ink,
          checkColor: c.su,
          side: BorderSide(color: c.si, width: 1.5),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class AccountStatusBadges extends StatelessWidget {
  const AccountStatusBadges(this.account, {super.key});

  final AdminAccount account;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        account.active
            ? const StatusBadge(label: 'Aktif', icon: Icons.check)
            : const StatusBadge(label: 'Nonaktif', icon: Icons.flag, variant: BadgeVariant.perlu),
        if (account.mustChangePassword) const StatusBadge(label: 'Belum ganti password'),
      ],
    );
  }
}

class LogRow extends StatelessWidget {
  const LogRow(this.entry, {super.key});

  final LogAktivitas entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(entry.time), style: context.styleAdminCaption),
                Text(
                  '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}',
                  style: context.styleAdminCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusBadge(label: entry.type.label),
          const SizedBox(width: 12),
          Expanded(child: Text(entry.message, style: context.styleBody)),
        ],
      ),
    );
  }
}

class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap});

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
          style: context.styleAdminCaption.copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
