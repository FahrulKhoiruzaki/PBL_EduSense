import 'package:edu_sense/core/theme.dart';
import 'package:edu_sense/widgets/app_overlays.dart';
import 'package:flutter/material.dart';

Widget harnessApp(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light,
      home: home,
    );
