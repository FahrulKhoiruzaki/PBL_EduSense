import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/async_body.dart';
import '../data/website_labels.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/month_calendar.dart';
import '../widgets/website_common.dart';

class AcademicsSection extends ConsumerWidget {
  const AcademicsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebPage(
      title: 'Akademik',
      children: [
        ResponsiveGrid(
          minItemWidth: 240,
          gap: 16,
          children: [
            for (final (title, pageKey) in WebsiteLabels.akademikInfo)
              CustomCard(
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
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 40, bottom: 16),
          child: Text('Kalender Akademik', style: context.webH2),
        ),
        AsyncBody<List<CalendarEvent>>(
          value: ref.watch(calendarProvider),
          onRetry: () => ref.invalidate(calendarProvider),
          builder: (events) => MonthCalendar(events: events),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 40, bottom: 16),
          child: Text('Informasi Kelas', style: context.webH2),
        ),
        AsyncBody<List<ClassLevelInfo>>(
          value: ref.watch(classInfoProvider),
          onRetry: () => ref.invalidate(classInfoProvider),
          builder: (all) => ResponsiveGrid(
            minItemWidth: 280,
            gap: 16,
            equalHeight: false,
            children: [
              for (var k = 1; k <= 6; k++)
                _ClassCard(tingkat: k, items: [for (final i in all) if (i.tingkat == k) i]),
            ],
          ),
        ),
        const SizedBox(height: 40),
        DarkPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informasi untuk Orang Tua',
                style: context.webH2.copyWith(color: AppColors.onDarkCard),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Pantau perkembangan belajar anak melalui Portal Orang Tua. Orang tua hanya dapat melihat data anak sendiri.',
                  style: context.webBody.copyWith(color: AppColors.onDarkCardMuted),
                ),
              ),
              ButtonRow(
                children: [
                  CustomButton(
                    label: 'Login Orang Tua',
                    onDark: true,
                    onPressed: () => openParentLogin(context),
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

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.tingkat, required this.items});

  final int tingkat;
  final List<ClassLevelInfo> items;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kelas $tingkat', style: context.webH3),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(kInfoUnavailable, style: context.webCap)
          else
            for (final kind in ClassInfoKind.values)
              ..._section(context, kind, [for (final i in items) if (i.kind == kind) i]),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, ClassInfoKind kind, List<ClassLevelInfo> list) {
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(kind.label, style: context.webCap.copyWith(fontWeight: FontWeight.w700)),
      ),
      for (final i in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.judul, style: context.webBody.copyWith(fontWeight: FontWeight.w600)),
              if (i.deskripsi.isNotEmpty) Text(i.deskripsi, style: context.webCap),
            ],
          ),
        ),
    ];
  }
}
