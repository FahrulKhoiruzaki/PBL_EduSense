import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../core/url_opener.dart';
import '../core/whatsapp.dart';
import 'app_overlays.dart';
import 'common_widgets.dart';
import 'custom_button.dart';

Future<void> showWhatsAppDialog(
  BuildContext context, {
  required String message,
  String? adminNumber,
}) async {
  final opener = ProviderScope.containerOf(context, listen: false).read(urlOpenerProvider);
  final proceed = await showDialog<bool>(
    context: context,
    barrierColor: scrimColor,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _WhatsAppBody(message: message, adminNumber: adminNumber),
        ),
      ),
    ),
  );
  if (proceed != true) return;

  var opened = false;
  try {
    opened = await opener(whatsAppUri(number: adminNumber, message: message));
  } on PlatformException {
    opened = false;
  }
  if (!opened) AppToast.show('Tidak dapat membuka WhatsApp. Pastikan aplikasinya terpasang.');
}

class _WhatsAppBody extends StatefulWidget {
  const _WhatsAppBody({required this.message, required this.adminNumber});

  final String message;
  final String? adminNumber;

  @override
  State<_WhatsAppBody> createState() => _WhatsAppBodyState();
}

class _WhatsAppBodyState extends State<_WhatsAppBody> {
  var _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Membuka WhatsApp…', style: context.styleH2),
          const SizedBox(height: 8),
          Text('Mohon tunggu.', style: context.styleCaption.copyWith(fontSize: 13)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lanjutkan ke WhatsApp', style: context.styleH2),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            'Pesan yang akan dikirim:',
            style: context.styleCaption.copyWith(fontSize: 13),
          ),
        ),
        InfoBanner(widget.message, margin: const EdgeInsets.only(top: 6)),
        const SizedBox(height: 8),
        Text(
          'Nomor admin: ${widget.adminNumber ?? 'belum tersedia'}',
          style: context.styleCaption.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: CustomButton(
                label: 'Batal',
                variant: ButtonVariant.outline,
                expanded: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomButton(
                label: 'Lanjutkan',
                expanded: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
