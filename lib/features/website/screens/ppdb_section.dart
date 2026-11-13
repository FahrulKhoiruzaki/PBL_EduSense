import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/async_body.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_labels.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

const _sectionPages = {
  'Informasi': 'ppdb-informasi',
  'Jadwal': 'ppdb-jadwal',
  'Persyaratan': 'ppdb-persyaratan',
};

class PpdbSection extends ConsumerStatefulWidget {
  const PpdbSection({super.key});

  @override
  ConsumerState<PpdbSection> createState() => _PpdbSectionState();
}

class _PpdbSectionState extends ConsumerState<PpdbSection> {
  final Map<String, GlobalKey> _anchors = {
    for (final s in WebsiteLabels.ppdbSections) s: GlobalKey(debugLabel: 'ppdb-$s'),
  };

  void _scrollTo(String section) {
    final target = _anchors[section]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _pageCard(String section, String title, String pageKey) {
    return Padding(
      key: _anchors[section],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CustomCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.webH3),
            const SizedBox(height: 8),
            PageText(pageKey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return WebPage(
      title: 'Penerimaan Peserta Didik Baru',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              for (final s in WebsiteLabels.ppdbSections) ...[
                Material(
                  color: c.mi,
                  borderRadius: BorderRadius.circular(99),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _scrollTo(s),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(widthFactor: 1, child: Text(s, style: context.webBody)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        _pageCard('Informasi', 'Informasi PPDB', _sectionPages['Informasi']!),
        _pageCard('Jadwal', 'Jadwal', _sectionPages['Jadwal']!),
        _pageCard('Persyaratan', 'Persyaratan', _sectionPages['Persyaratan']!),
        Padding(
          key: _anchors['Alur'],
          padding: const EdgeInsets.only(top: 32, bottom: 16),
          child: Text('Alur Pendaftaran', style: context.webH2),
        ),
        ResponsiveGrid(
          minItemWidth: 170,
          gap: 12,
          children: [
            for (var i = 0; i < WebsiteLabels.ppdbSteps.length; i++)
              CustomCard(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}',
                      style: context.styleH1.copyWith(fontSize: 28, height: 1.2, color: c.si),
                    ),
                    Text(
                      WebsiteLabels.ppdbSteps[i],
                      style: context.webBody.copyWith(fontWeight: FontWeight.w700),
                    ),
                    PageText('ppdb-alur-${i + 1}', style: context.webCap),
                  ],
                ),
              ),
          ],
        ),
        Padding(
          key: _anchors['Dokumen'],
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: CustomCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dokumen', style: context.webH3),
                const SizedBox(height: 8),
                const PageText('ppdb-dokumen'),
              ],
            ),
          ),
        ),
        Padding(
          key: _anchors['FAQ'],
          padding: const EdgeInsets.only(top: 32, bottom: 16),
          child: Text('FAQ PPDB', style: context.webH2),
        ),
        AsyncBody<List<Faq>>(
          value: ref.watch(faqProvider),
          onRetry: () => ref.invalidate(faqProvider),
          builder: (all) {
            final faqs = [
              for (final f in all)
                if (f.kategori == FaqKategori.ppdb) f,
            ];
            return faqs.isEmpty ? const WebEmpty('Belum ada pertanyaan PPDB.') : FaqList(faqs);
          },
        ),
        Padding(
          key: _anchors['Kontak'],
          padding: const EdgeInsets.only(top: 28),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: WhatsAppButton(topic: WhatsAppTopic.ppdb),
          ),
        ),
      ],
    );
  }
}
