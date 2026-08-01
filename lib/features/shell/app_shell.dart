import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/plate_icon.dart';
import '../history/history_screen.dart';
import '../regime/regime_screen.dart';
import '../settings/settings_screen.dart';
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
    RegimeScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The page fades and rises a few pixels on each switch. Not a slide: the
      // tabs are peers, and a horizontal transition would imply an order they
      // don't have — and the log screen owns the horizontal axis.
      body: TweenAnimationBuilder<double>(
        key: ValueKey(_index),
        tween: Tween(begin: 0, end: 1),
        duration: Motion.base,
        curve: Motion.curve,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child:
              Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
        ),
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: _NavBar(index: _index, onSelect: _select),
    );
  }
}

// `Today` was already lying: the screen backfills a session logged on Tuesday
// and resumes one left open yesterday, so a tab named after a day shows other
// days. The page keeps the date as its own title (§9) — only the label moved.
//
// Settings takes the slot Progress left behind, and not for symmetry:
// bodyweight logging lives in there and is not a setting. It is data entered
// weekly that feeds every pull-up and dip score in the app, and it had never
// once been logged through the UI while it sat two taps deep behind a cog.
//
// Workouts wears a drawn stack of plates rather than Material's dumbbell.
// Material ships exactly one piece of gym equipment, and it is the icon every
// training app on the phone already has; plates are what this app is actually
// about, and the taper reads as load at 24dp where a figure or a barbell does
// not.
const _destinations = [
  (icon: null, active: null, label: 'Workouts'),
  (
    icon: Icons.dashboard_outlined,
    active: Icons.dashboard_rounded,
    label: 'Regime'
  ),
  (icon: Icons.history_rounded, active: Icons.history_rounded, label: 'History'),
  (
    icon: Icons.settings_outlined,
    active: Icons.settings_rounded,
    label: 'Settings'
  ),
];

/// The app's own bar rather than Material's.
///
/// `NavigationBar` insists on its own indicator geometry, height and label
/// behaviour. This is the same thing in 60 lines, and it states the live tab
/// the way the rest of the app states emphasis: **brightness and weight, no
/// pill and no hue.** A coloured indicator here would be the only chrome in the
/// app wearing a colour, which is exactly the look we left behind.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: _destinations[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  /// A null glyph pair means the destination draws its own icon — today that is
  /// Workouts and its plates.
  final ({IconData? icon, IconData? active, String label}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = selected ? c.textPrimary : c.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.04 : 1,
            duration: Motion.base,
            curve: Motion.spring,
            child: destination.icon == null
                ? PlateIcon(size: 27, color: tint, filled: selected)
                : Icon(
                    selected ? destination.active : destination.icon,
                    size: 24,
                    color: tint,
                  ),
          ),
          const SizedBox(height: Space.xs),
          AnimatedDefaultTextStyle(
            duration: Motion.base,
            style: context.t.labelSmall!.copyWith(
              color: tint,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(destination.label),
          ),
        ],
      ),
    );
  }
}
