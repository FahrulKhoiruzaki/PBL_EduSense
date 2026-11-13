import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class ContactSection extends ConsumerWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final info = ref.watch(schoolInfoValueProvider);

    return WebPage(
      title: 'Kontak & Pengaduan',
      children: [
        ResponsiveGrid(
          minItemWidth: 300,
          gap: 24,
          equalHeight: false,
          children: [
            CustomCard(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (label, value) in [
                    ('Alamat', info.alamat),
                    ('Telepon', info.telepon),
                    ('Email', info.email),
                    ('Media sosial', info.mediaSosial),
                  ])
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.mi)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: context.webCap),
                          Text(value ?? '—', style: context.webBody),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (info.petaUrl != null)
              ImagePlaceholder(height: 260, label: 'Peta', imageUrl: info.petaUrl),
          ],
        ),
        const SizedBox(height: 32),
        DarkPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Butuh bantuan?', style: context.webH2.copyWith(color: AppColors.onDarkCard)),
              const SizedBox(height: 12),
              PageText(
                'kontak-ajakan',
                style: context.webBody.copyWith(color: AppColors.onDarkCardMuted),
                hideIfMissing: true,
              ),
              const ButtonRow(
                children: [
                  WhatsAppButton(onDark: true),
                  WhatsAppButton(
                    label: 'Kirim Pengaduan via WhatsApp',
                    topic: WhatsAppTopic.pengaduan,
                    variant: ButtonVariant.outline,
                    onDark: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
