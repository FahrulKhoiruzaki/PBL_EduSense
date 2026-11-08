import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/value_state.dart';
import '../../../widgets/custom_button.dart';
import '../providers/website_providers.dart';

export '../../../widgets/responsive_grid.dart';

const _narrowBreakpoint = 800.0;

bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width <= _narrowBreakpoint;

double fluid(BuildContext context, double min, double vw, double max) =>
    (MediaQuery.sizeOf(context).width * vw / 100).clamp(min, max);

extension WebStyles on BuildContext {
  TextStyle get webBody => styleBody.copyWith(fontSize: 16, height: 24 / 16);
  TextStyle get webMuted => webBody.copyWith(color: colors.sl);
  TextStyle get webCap => styleCaption.copyWith(fontSize: 13, height: 20 / 13);
  TextStyle get webSmallMuted =>
      styleBody.copyWith(fontSize: 14, height: 22 / 14, color: colors.sl);
  TextStyle get webH3 => styleBold.copyWith(fontSize: 18, height: 26 / 18, fontWeight: FontWeight.w600);

  TextStyle _heading(double min, double vw, double max, double height, double spacing) {
    final size = fluid(this, min, vw, max);
    return styleH1.copyWith(fontSize: size, height: height, letterSpacing: size * spacing);
  }

  TextStyle get webH1 => _heading(36, 6, 68, 1.04, -.035);
  TextStyle get webPageTitle => _heading(32, 5, 52, 1.04, -.035);
  TextStyle get webDetailTitle => _heading(30, 4.6, 48, 1.04, -.035);
  TextStyle get webH2 => _heading(26, 3.4, 40, 1.12, -.025);
}

class WebContainer extends StatelessWidget {
  const WebContainer({super.key, required this.child, this.maxWidth = 1120});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child),
      ),
    );
  }
}

class WebSection extends StatelessWidget {
  const WebSection({
    super.key,
    required this.child,
    this.topPadding = true,
    this.bottomPadding = true,
  });

  final Widget child;
  final bool topPadding;
  final bool bottomPadding;

  @override
  Widget build(BuildContext context) {
    final v = isNarrow(context) ? 44.0 : 64.0;
    return Padding(
      padding: EdgeInsets.only(top: topPadding ? v : 0, bottom: bottomPadding ? v : 0),
      child: WebContainer(child: child),
    );
  }
}

class WebPage extends StatelessWidget {
  const WebPage({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return WebSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(title!, style: context.webPageTitle),
            ),
          ...children,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.linkLabel, this.onLink});

  final String title;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 16,
          runSpacing: 16,
          children: [
            Text(title, style: context.webH2),
            if (linkLabel != null)
              CustomButton(
                label: linkLabel!,
                variant: ButtonVariant.outline,
                onPressed: onLink,
              ),
          ],
        ),
      ),
    );
  }
}

const kPhotoUnavailable = 'Foto belum tersedia';
const kInfoUnavailable = 'Informasi belum tersedia.';

class ImagePlaceholder extends StatelessWidget {
  const ImagePlaceholder({
    super.key,
    this.height = 190,
    this.label = kPhotoUnavailable,
    this.imageUrl,
  });

  final double height;
  final String label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.mi, c.si],
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: context.styleCaption.copyWith(fontSize: 12, color: c.sl),
      ),
    );

    final url = imageUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder,
          loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
        ),
      ),
    );
  }
}

class PageText extends ConsumerWidget {
  const PageText(
    this.pageKey, {
    super.key,
    this.style,
    this.fallback,
    this.hideIfMissing = false,
    this.align,
  });

  final String pageKey;
  final TextStyle? style;
  final TextAlign? align;

  /// Teks pengganti bila admin belum mengisi; bila kosong dipakai [kInfoUnavailable].
  final String? fallback;

  /// Untuk teks hiasan (mis. subjudul): tidak menampilkan apa pun bila belum diisi.
  final bool hideIfMissing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(sitePagesProvider);
    final stored = pages.value?[pageKey];
    if (stored != null && stored.trim().isNotEmpty) {
      return Text(stored, style: style ?? context.webMuted, textAlign: align);
    }
    if (pages.isLoading && !pages.hasValue) return const SizedBox.shrink();
    if (hideIfMissing) return const SizedBox.shrink();
    return Text(fallback ?? kInfoUnavailable, style: style ?? context.webMuted, textAlign: align);
  }
}

class TagLabel extends StatelessWidget {
  const TagLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: context.colors.si),
      ),
      child: Text(text, style: context.styleBadge.copyWith(color: context.colors.ink)),
    );
  }
}

class Breadcrumb extends StatelessWidget {
  const Breadcrumb(this.items, {super.key});

  final List<(String label, VoidCallback? onTap)> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Text(' / ', style: context.webCap),
            InkWell(
              onTap: items[i].$2,
              child: Text(items[i].$1, style: context.webCap),
            ),
          ],
        ],
      ),
    );
  }
}

class WebChipBar<T> extends StatelessWidget {
  const WebChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.trailing,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
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
                        style: context.styleBody.copyWith(
                          fontSize: 16,
                          color: selected == value ? c.su : c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

class WebDropdown<T> extends StatelessWidget {
  const WebDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    required this.semanticLabel,
    this.width = 150,
  });

  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;
  final String semanticLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        label: semanticLabel,
        child: DropdownButtonFormField<T>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          style: context.styleBody.copyWith(fontSize: 16),
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(itemLabel(item))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class WebSearchField extends ConsumerStatefulWidget {
  const WebSearchField({super.key, required this.provider, required this.hint});

  final NotifierProvider<ValueState<String>, String> provider;
  final String hint;

  @override
  ConsumerState<WebSearchField> createState() => _WebSearchFieldState();
}

class _WebSearchFieldState extends ConsumerState<WebSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(widget.provider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(widget.provider, (_, next) {
      if (next != _controller.text) _controller.text = next;
    });
    return Semantics(
      label: widget.hint,
      child: TextField(
        controller: _controller,
        style: context.styleBody.copyWith(fontSize: 16),
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (v) => ref.read(widget.provider.notifier).set(v),
      ),
    );
  }
}

class WebEmpty extends StatelessWidget {
  const WebEmpty(this.message, {super.key, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center, style: context.webBody.copyWith(color: context.colors.st)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class DarkPanel extends StatelessWidget {
  const DarkPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrow(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: narrow ? 32 : 48, horizontal: narrow ? 20 : 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment(-0.34, -0.94),
          end: Alignment(0.34, 0.94),
          colors: [AppColors.darkCardStart, AppColors.darkCardEnd],
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.onDarkCard),
        child: child,
      ),
    );
  }
}

class ButtonRow extends StatelessWidget {
  const ButtonRow({super.key, required this.children, this.top = 28});

  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Wrap(spacing: 12, runSpacing: 12, children: children),
    );
  }
}

class LabeledRow extends StatelessWidget {
  const LabeledRow({super.key, required this.label, required this.value, this.labelWidth = 140});

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.mi))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: labelWidth, child: Text(label, style: context.webMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value, style: context.webBody.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
