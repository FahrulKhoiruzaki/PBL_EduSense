import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/web_auth/screens/web_shell.dart';
import 'widgets/app_overlays.dart';

void main() {
  runApp(const ProviderScope(child: WebsiteApp()));
}

class WebsiteApp extends StatelessWidget {
  const WebsiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDN 02 Pakunden Kota Blitar',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const WebShell(),
    );
  }
}
