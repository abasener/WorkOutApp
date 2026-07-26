import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'lifts/lifts_screen.dart';
import 'metrics/metrics_screen.dart';
import 'quick_log/quick_log_sheet.dart';
import 'settings/settings_screen.dart';

/// Bottom-nav shell: Home / Lifts / (FAB) / Metrics / Settings,
/// per designFiles/00_UX_DESIGN.md navigation structure.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        // Built fresh each rebuild rather than a `const` field — safe under
        // IndexedStack, whose diffing keys off widget type/position, not
        // object identity, so no screen's state is lost by this. Needed so
        // HomeScreen can be told when it's no longer the active tab (see
        // its `active` param) and auto-exit edit mode.
        children: [
          HomeScreen(active: _index == 0),
          const LiftsScreen(),
          const MetricsScreen(),
          const SettingsScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => QuickLogSheet.show(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_outlined, 'Home', 0),
            _navItem(Icons.fitness_center, 'Lifts', 1),
            const SizedBox(width: 40), // space for the FAB notch
            _navItem(Icons.insights_outlined, 'Metrics', 2),
            _navItem(Icons.settings_outlined, 'Settings', 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _index == index;
    final color = selected ? AppColors.accent : AppColors.textSecondary;
    return InkWell(
      onTap: () => setState(() => _index = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppText.smallText.copyWith(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
