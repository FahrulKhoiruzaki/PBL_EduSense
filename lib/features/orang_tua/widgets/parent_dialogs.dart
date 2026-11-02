import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_overlays.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/whatsapp_dialog.dart';
import '../../website/providers/website_providers.dart';
import '../providers/parent_providers.dart';

void showParentLogoutConfirm(BuildContext context, {VoidCallback? onLogout}) {
  showConfirmDialog(
    context,
    message: 'Apakah Anda yakin ingin keluar?',
    confirmLabel: 'Keluar',
    onConfirm: () {
      AppToast.show('Anda telah keluar');
      onLogout?.call();
    },
  );
}

void showParentMoreSheet(BuildContext context, {VoidCallback? onLogout}) {
  final container = ProviderScope.containerOf(context, listen: false);

  showAppSheet<void>(
    context,
    builder: (sheetContext) {
      void open(ParentSubPage page) {
        Navigator.of(sheetContext).pop();
        container.read(activeTabProvider.notifier).openSubPage(page);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lainnya', style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: 8),
          RowList(
            children: [
              for (final page in ParentSubPage.values)
                NavRow(title: page.label, onTap: () => open(page)),
            ],
          ),
          const SizedBox(height: 12),
          CustomButton(
            label: 'Keluar',
            variant: ButtonVariant.danger,
            expanded: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              showParentLogoutConfirm(context, onLogout: onLogout);
            },
          ),
        ],
      );
    },
  );
}

Future<void> showParentWhatsAppDialog(
  BuildContext context, {
  required String childName,
  required String className,
}) {
  return showWhatsAppDialog(
    context,
    adminNumber: ProviderScope.containerOf(context, listen: false)
        .read(schoolInfoValueProvider)
        .whatsapp,
    message:
        'Halo Admin SDN 02 Pakunden, data $childName (Kelas $className) di portal tampaknya tidak sesuai. Mohon dicek.',
  );
}
