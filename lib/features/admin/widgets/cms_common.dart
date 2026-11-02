import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_overlays.dart';
import '../../../widgets/custom_card.dart';
import '../../../widgets/status_badge.dart';
import '../actions/guard_admin.dart';
import '../data/cms_models.dart';
import 'admin_dialogs.dart';

class CmsSection extends StatelessWidget {
  const CmsSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(title, style: context.styleH2),
              ?action,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: context.styleSoft),
            ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class CmsEmpty extends StatelessWidget {
  const CmsEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text(text, style: context.styleMuted)),
  );
}

Widget cmsStatusBadge(ContentStatus status) => StatusBadge(label: status.label);

/// Konfirmasi hapus; galat dari server ditampilkan sebagai toast.
Future<void> cmsConfirmDelete(
  BuildContext context, {
  required String title,
  required String description,
  required Future<void> Function() onDelete,
}) {
  return showAdminConfirm(
    adminDialogContext(context),
    title: title,
    description: description,
    confirmLabel: 'Hapus',
    onConfirm: () async {
      final done = await guardAdmin(() async {
        await onDelete();
        return true;
      });
      if (done == true) AppToast.show('Berhasil dihapus.');
    },
  );
}
