import 'package:aplikasi_guru/core/theme.dart';
import 'package:aplikasi_guru/widgets/app_overlays.dart';
import 'package:flutter/material.dart';

Widget harnessApp(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light,
      home: home,
    );
