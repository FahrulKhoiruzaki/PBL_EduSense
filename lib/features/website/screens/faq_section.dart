import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/async_body.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class FaqSection extends ConsumerWidget {
  const FaqSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(faqCategoryProvider);
    final items = ref.watch(filteredFaqProvider);

    return WebPage(
      title: 'FAQ',
      children: [
        WebSearchField(provider: faqSearchQueryProvider, hint: 'Cari pertanyaan'),
        WebChipBar<FaqKategori?>(
          options: [
            (null, 'Semua'),
            for (final k in FaqKategori.values) (k, k.label),
          ],
          selected: category,
          onSelected: (v) => ref.read(faqCategoryProvider.notifier).set(v),
        ),
        AsyncBody<List<Faq>>(
          value: ref.watch(faqProvider),
          onRetry: () => ref.invalidate(faqProvider),
          builder: (all) => items.isEmpty
              ? WebEmpty(all.isEmpty ? 'Belum ada pertanyaan.' : 'Pertanyaan tidak ditemukan.')
              : FaqList(items),
        ),
        const SizedBox(height: 24),
        CustomCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Belum menemukan jawaban?',
                style: context.webBody.copyWith(fontWeight: FontWeight.w700),
              ),
              const ButtonRow(top: 12, children: [WhatsAppButton()]),
            ],
          ),
        ),
      ],
    );
  }
}
