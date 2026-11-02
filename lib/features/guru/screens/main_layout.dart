import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/tab_navigation.dart';
import '../../../core/theme.dart';
import '../../../providers/app_providers.dart';
import 'attendance_screen.dart';
import 'class_screen.dart';
import 'home_screen.dart';

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(activeTabProvider);
    final isWali = ref.watch(isWaliProvider);
    final c = context.colors;

    return NavigatorPopHandler(
      onPopWithResult: (_) => tabNavigatorKeys[index].currentState?.maybePop(),
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            _TabNavigator(navKey: tabNavigatorKeys[0], root: const HomeScreen()),
            _TabNavigator(navKey: tabNavigatorKeys[1], root: const AttendancePickerScreen()),
            _TabNavigator(navKey: tabNavigatorKeys[2], root: const ClassScreen()),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.mi))),
          child: BottomNavigationBar(
            currentIndex: index,
            onTap: (i) => goTab(ref, i, resetStack: i == index),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.radio_button_checked),
                label: isWali ? 'Hadir' : 'Absen',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_outlined),
                activeIcon: Icon(Icons.grid_view),
                label: 'Kelas',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navKey, required this.root});

  final GlobalKey<NavigatorState> navKey;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
    );
  }
}
