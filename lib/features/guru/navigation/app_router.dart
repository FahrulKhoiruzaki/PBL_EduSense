import 'package:flutter/material.dart';

import '../../../models/app_models.dart';
import '../screens/attendance_screen.dart';
import '../screens/grades_screen.dart';
import '../screens/need_attention_screen.dart';
import '../screens/class_screen.dart';

void pushPage(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

void openTarget(BuildContext context, NavTarget target) {
  pushPage(
    context,
    switch (target.route) {
      AppRoute.attendanceClass => const AttendanceClassScreen(),
      AppRoute.gradeDetail => GradeDetailScreen(gradeId: target.arg!),
      AppRoute.needAttention => NeedAttentionScreen(initialTab: target.arg ?? 0),
      AppRoute.stats => const StatsScreen(),
      AppRoute.grades => const GradesScreen(),
    },
  );
}
