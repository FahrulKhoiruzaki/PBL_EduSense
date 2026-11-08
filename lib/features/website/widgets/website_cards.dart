import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/whatsapp_dialog.dart';
import '../../web_auth/data/web_auth_models.dart';
import '../../web_auth/navigation/web_auth_navigation.dart';
import '../data/website_models.dart';
import '../providers/website_providers.dart';
import 'website_common.dart';

void openWhatsApp(BuildContext context, WhatsAppTopic topic) {
  final number = ProviderScope.containerOf(context, listen: false)
      .read(schoolInfoValueProvider)
      .whatsapp;
  showWhatsAppDialog(context, message: topic.message, adminNumber: number);
}

void openParentLogin(BuildContext context) => openWebLogin(context, WebRole.ortu);

void openAdminLogin(BuildContext context) => openWebLogin(context, WebRole.admin);

class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({
    super.key,
    this.label = 'Hubungi Admin via WhatsApp',
    this.topic = WhatsAppTopic.umum,
    this.variant = ButtonVariant.primary,
    this.onDark = false,
  });

  final String label;
  final WhatsAppTopic topic;
  final ButtonVariant variant;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return CustomButton(
      label: label,
      variant: variant,
      onDark: onDark,
      onPressed: () => openWhatsApp(context, topic),
    );
  }
}

class NewsCard extends ConsumerWidget {
  const NewsCard({super.key, required this.berita});

  final Berita berita;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomCard(
      margin: EdgeInsets.zero,
      onTap: () => ref.read(activeNavProvider.notifier).openNews(berita.slug),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImagePlaceholder(height: 150, imageUrl: berita.imageUrl),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagLabel(berita.kategori.label),
              Text(formatDateLong(berita.tanggal), style: context.webCap),
            ],
          ),
          const SizedBox(height: 8),
          Text(berita.judul, style: context.webH3),
          if (berita.ringkasan.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(berita.ringkasan, style: context.webSmallMuted),
          ],
        ],
      ),
    );
  }
}

class ActivityCard extends ConsumerWidget {
  const ActivityCard({super.key, required this.kegiatan});

  final Kegiatan kegiatan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomCard(
      margin: EdgeInsets.zero,
      onTap: () => ref.read(activeNavProvider.notifier).openActivity(kegiatan.slug),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImagePlaceholder(height: 150, imageUrl: kegiatan.imageUrl),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TagLabel(kegiatan.kategori.label),
              Text(formatDateLong(kegiatan.tanggal), style: context.webCap),
            ],
          ),
          const SizedBox(height: 8),
          Text(kegiatan.judul, style: context.webH3),
        ],
      ),
    );
  }
}

class FaqTile extends StatefulWidget {
  const FaqTile({super.key, required this.faq});

  final Faq faq;

  @override
  State<FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<FaqTile> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final answer = widget.faq.jawaban.isEmpty ? kInfoUnavailable : widget.faq.jawaban;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.su,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.mi),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          expandedAlignment: Alignment.centerLeft,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          onExpansionChanged: (v) => setState(() => _open = v),
          trailing: AnimatedRotation(
            turns: _open ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.add, color: c.ink),
          ),
          title: Text(
            widget.faq.pertanyaan,
            style: context.webBody.copyWith(fontWeight: FontWeight.w600),
          ),
          children: [Text(answer, style: context.webMuted)],
        ),
      ),
    );
  }
}

class FaqList extends StatelessWidget {
  const FaqList(this.items, {super.key});

  final List<Faq> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [for (final f in items) FaqTile(key: ValueKey(f.pertanyaan), faq: f)],
    );
  }
}

class PhotoLightbox extends StatefulWidget {
  const PhotoLightbox({super.key, required this.initial, required this.urls});

  final int initial;
  final List<String> urls;

  @override
  State<PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<PhotoLightbox> {
  late int _index = widget.initial;

  @override
  Widget build(BuildContext context) {
    final count = widget.urls.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ImagePlaceholder(height: 260, label: 'Foto ${_index + 1}', imageUrl: widget.urls[_index]),
        const SizedBox(height: 12),
        Row(
          children: [
            CustomButton(
              label: '←',
              variant: ButtonVariant.outline,
              onPressed: count < 2 ? null : () => setState(() => _index = (_index - 1 + count) % count),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomButton(
                label: 'Tutup',
                variant: ButtonVariant.outline,
                expanded: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 8),
            CustomButton(
              label: '→',
              variant: ButtonVariant.outline,
              onPressed: count < 2 ? null : () => setState(() => _index = (_index + 1) % count),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showPhotoLightbox(BuildContext context, List<String> urls, int index) {
  return showDialog<void>(
    context: context,
    barrierColor: scrimColor,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PhotoLightbox(initial: index, urls: urls),
        ),
      ),
    ),
  );
}

Future<void> showFacilityDialog(BuildContext context, Fasilitas fasilitas) {
  return showDialog<void>(
    context: context,
    barrierColor: scrimColor,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fasilitas.nama, style: dialogContext.webH3),
              const SizedBox(height: 12),
              ImagePlaceholder(height: 180, imageUrl: fasilitas.imageUrl),
              const SizedBox(height: 12),
              Text(
                fasilitas.deskripsi.isEmpty ? kInfoUnavailable : fasilitas.deskripsi,
                style: dialogContext.webMuted,
              ),
              const SizedBox(height: 12),
              CustomButton(label: 'Tutup', onPressed: () => Navigator.of(dialogContext).pop()),
            ],
          ),
        ),
      ),
    ),
  );
}
