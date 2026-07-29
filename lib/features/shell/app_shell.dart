import 'package:flutter/material.dart';

import '../history/history_screen.dart';
import '../progress/progress_screen.dart';
import '../regime/regime_screen.dart';
import '../today/today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // Kept alive across tab switches so scroll position and in-progress edits
  // survive navigation.
  final _pages = const [
    TodayScreen(),
    HistoryScreen(),
    ProgressScreen(),
    RegimeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_column_outlined),
            selectedIcon: Icon(Icons.view_column),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Regime',
          ),
        ],
      ),
    );
  }
}
