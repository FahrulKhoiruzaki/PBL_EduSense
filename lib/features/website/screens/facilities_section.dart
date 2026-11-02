import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/async_body.dart';
import '../../../widgets/custom_card.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import '../widgets/website_cards.dart';
import '../widgets/website_common.dart';

class FacilitiesSection extends ConsumerWidget {
  const FacilitiesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebPage(
      title: 'Fasilitas',
      children: [
        AsyncBody<List<Fasilitas>>(
          value: ref.watch(facilitiesProvider),
          onRetry: () => ref.invalidate(facilitiesProvider),
          loading: const LoadingList(count: 2, height: 220),
          builder: (items) => items.isEmpty
              ? const WebEmpty('Belum ada data fasilitas.')
              : ResponsiveGrid(
                  minItemWidth: 240,
                  gap: 16,
                  children: [
                    for (final f in items)
                      CustomCard(
                        margin: EdgeInsets.zero,
                        onTap: () => showFacilityDialog(context, f),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ImagePlaceholder(height: 160, imageUrl: f.imageUrl),
                            const SizedBox(height: 12),
                            Text(f.nama, style: context.webH3),
                            if (f.deskripsi.isNotEmpty)
                              Text(
                                f.deskripsi,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.webSmallMuted,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
