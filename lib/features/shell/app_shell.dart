import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/plate_icon.dart';
import '../history/history_screen.dart';
import '../regime/regimes_screen.dart';
import '../settings/settings_screen.dart';
import '../today/today_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // Kept alive across tab switches so scroll position and in-progress edits
  // survive navigation.
  final _pages = const [
    TodayScreen(),
    RegimesScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  /// Drives the fade-and-rise. A controller rather than a
  /// `TweenAnimationBuilder` keyed on the index, which is what this was:
  /// changing a key throws away the element subtree under it, and the subtree
  /// under it was the `IndexedStack`. Every tab switch therefore **rebuilt all
  /// four screens from scratch** — the thing `IndexedStack` is there to
  /// prevent — dropping their scroll positions and their providers' warm state,
  /// and doing all of that work on the same frame the nav bar's ripple was
  /// trying to animate. That is why switching tabs hitched and why the ripple
  /// appeared to freeze halfway.
  late final _fade = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _fade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The page fades and rises a few pixels on each switch. Not a slide: the
      // tabs are peers, and a horizontal transition would imply an order they
      // don't have — and the log screen owns the horizontal axis.
      body: AnimatedBuilder(
        animation: _fade,
        // The stack is the `child`: built once, animated over.
        child: IndexedStack(index: _index, children: _pages),
        builder: (context, child) {
          final t = Motion.curve.transform(_fade.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          );
        },
      ),
      bottomNavigationBar: _NavBar(index: _index, onSelect: _select),
    );
  }
}

// `Today` was already lying: the screen backfills a session logged on Tuesday
// and resumes one left open yesterday, so a tab named after a day shows other
// days. The page keeps the date as its own title (THEME → Composing a screen) — only the label moved.
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
    label: 'Regimes'
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
    // `Material`, not a plain `Container`: ink has to have a surface to paint
    // on, and the nearest one was the Scaffold *behind* the bar — so a ripple
    // would have spread under an opaque background and never been seen.
    return Material(
      color: c.surface,
      shape: Border(top: BorderSide(color: c.border)),
      // The ripple is wider than one destination on purpose (see `_NavItem`),
      // so the bar has to clip: unclipped it would wash over the screen above.
      clipBehavior: Clip.hardEdge,
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

    // The one destination control in the app, tapped more than anything else,
    // and until now the only tappable thing with no press state at all: no
    // scale, no dim, no ink. A tab that does not answer the finger makes the
    // whole app feel a frame behind.
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      // The ripple belongs to the *bar*, not to the destination.
      //
      // Bounded to the cell it read as a lit box one fifth of the bar wide with
      // a hard edge — the pill this bar explicitly does not have, arriving by
      // accident. Unbounded, with a radius the width of the screen, it is what
      // it should be: a wash that starts under the tapped icon and carries
      // across the whole bar, thinning out as it goes. It is clipped to the bar
      // by the `Material` above.
      //
      // `containedInkWell: false` also means the splash originates at the
      // destination's centre rather than the exact touch point — symmetric
      // under the icon, which is the look we want anyway.
      containedInkWell: false,
      radius: MediaQuery.sizeOf(context).width * 0.48,
      splashFactory: const _NavSplashFactory(),
      // Read at the centre only. The gradient has thrown most of this away by
      // a third of the way out, so it can be brighter than a flat splash.
      splashColor: c.textPrimary.withValues(alpha: 0.3),
      // The press state is the ripple. A highlight underneath it is a second
      // shape doing the same job, and it is the one that leaves an edge.
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.04 : 1,
            duration: Motion.base,
            curve: Motion.overshoot,
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

/// The bar's ripple: a radial *gradient* wash, not a flat disc.
///
/// `InkRipple` and `InkSparkle` both paint a solid circle of one colour. Grown
/// wide enough to cross the bar — which is the look this bar wants — a solid
/// circle stops being a ripple and becomes the whole bar changing brightness
/// at once. The wash below is opaque at the tapped destination and falls to
/// nothing by the time it reaches the far end, so the bar reads as *responding
/// under the finger* even though the light travels the full width.
class _NavSplashFactory extends InteractiveInkFeatureFactory {
  const _NavSplashFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _NavSplash(
      controller: controller,
      referenceBox: referenceBox,
      color: color,
      radius: radius ?? referenceBox.size.width * 4,
      onRemoved: onRemoved,
    );
  }
}

class _NavSplash extends InteractiveInkFeature {
  _NavSplash({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required this.radius,
    super.onRemoved,
  }) {
    // One clock, and the finger does not drive it.
    //
    // Two clocks meant the fade could only start once the finger came off, so
    // the wash sat at full radius waiting — a visible hitch between the growth
    // and the fade, and a total length that depended on how long the tap was
    // held. Here the growth and the fade are two curves read off the same `t`
    // and they overlap: the wash is already dimming while it is still moving
    // out. Every press plays the identical animation over `_duration`,
    // whether it was a flick or a long hold.
    _anim = AnimationController(duration: _duration, vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener(_onStatus)
      ..forward();

    controller.addInkFeature(this);
  }

  /// Long enough to cross the bar without looking like it is chasing the
  /// finger; the tab switch itself lands well before it finishes.
  static const Duration _duration = Duration(milliseconds: 420);

  /// Full strength by here, then straight into the fade. Fading from the very
  /// first frame would wash out the moment the finger lands, which is the one
  /// moment the bar has to look like it felt the tap.
  static const double _peak = 0.18;

  final double radius;
  late final AnimationController _anim;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) dispose();
  }

  // The press no longer ends the animation — it runs to `_duration` either way.
  @override
  void confirm() {}

  @override
  void cancel() {}

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final double v = _anim.value;
    final double t = Curves.easeOutCubic.transform(v);
    final double r = radius * t;
    if (r <= 0) return;

    final double f = v < _peak
        ? Curves.easeOut.transform(v / _peak)
        : Curves.easeInOut.transform(1.0 - (v - _peak) / (1.0 - _peak));
    final int alpha = (color.a * 255.0 * f).round();
    if (alpha <= 0) return;
    final Color core = color.withAlpha(alpha);
    final Offset center = referenceBox.size.center(Offset.zero);

    // The falloff, not the radius, is what stops this reading as a flash: full
    // strength only at the centre, half of it a third of the way out, gone at
    // the rim.
    //
    // It also has to **flatten as it fades**. The circle never shrinks — `_anim`
    // only ever runs forward — but a steep falloff losing alpha *looks* like it
    // does: the dim outer ring crosses under the eye's floor first, so the
    // visible edge walks back towards the centre while the real one is still
    // moving out. Easing the mid stop out to the rim as `f` falls means the
    // last thing on screen is a flat disc dissolving in place, which is what
    // lifting a finger should look like.
    final double mid = ui.lerpDouble(0.98, 0.35, f)!;
    final double midAlpha = ui.lerpDouble(1.0, 0.45, f)!;
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          core,
          core.withAlpha((alpha * midAlpha).round()),
          core.withAlpha(0),
        ],
        stops: [0.0, mid, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));

    canvas.save();
    canvas.transform(transform.storage);
    canvas.drawCircle(center, r, paint);
    canvas.restore();
  }
}
