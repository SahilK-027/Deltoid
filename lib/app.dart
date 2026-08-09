import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'core/widgets/scroll.dart';
import 'features/shell/app_shell.dart';
import 'features/today/today_providers.dart';

class DeltoidApp extends ConsumerWidget {
  const DeltoidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follow the OS until the stored preference resolves. The launch window is
    // night-qualified, so this is the one default that matches what the system
    // just drew — assuming dark flipped a light-mode phone to dark and back
    // again in the two frames before the preference landed.
    final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;

    return MaterialApp(
      title: 'Deltoid',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      // Damped scrolling everywhere, and no overscroll glow — see
      // [AppScrollBehavior].
      scrollBehavior: const AppScrollBehavior(),
      // Crossed, not cut. This was `noAnimation` on the argument that lerping
      // every colour in the tree is a grey wash through the midpoint of two
      // palettes — true at Material's default 200ms linear, and the reason the
      // switch is now driven at this app's own micro duration on
      // `easeOutCubic`: fast enough that the midpoint is never a state you can
      // read, slow enough that the screen does not appear to be replaced.
      themeAnimationStyle: AnimationStyle(
        duration: Motion.fast,
        curve: Motion.curve,
      ),
      home: const _Boot(),
    );
  }
}

/// Blocks first paint until the schema exists, the starting catalog is seeded
/// and Today has its data, so no screen ever renders a half-initialised
/// database — and the first screen the user sees is already filled in rather
/// than assembling itself in front of them.
class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The status and navigation bars draw over the app, so their *icons* have
    // to be told which way round the app is.
    //
    // This was set on `appBarTheme.systemOverlayStyle`, which only applies
    // where there is an `AppBar` — and there is not one anywhere in this app,
    // because every screen wears a `HeaderBand` of its own. So the icons kept
    // whatever the launch window left behind, which is white: correct on dark
    // and invisible on light, where the whole bottom strip read as a black
    // band under a white screen.
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: _iconsFor(context),
      statusBarBrightness: Theme.of(context).brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: _iconsFor(context),
      systemNavigationBarDividerColor: Colors.transparent,
    );

    final init = ref.watch(appInitProvider);
    // Waiting on Today here rather than inside the shell keeps the tab bar from
    // sliding in over an empty page. It is one local query behind the seeder,
    // so this costs a frame or two, not a visible wait.
    final today = ref.watch(todayProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: init.when(
        data: (_) =>
            today.hasValue ? const _Ready(child: AppShell()) : const _Holding(),
        loading: () => const _Holding(),
        error: (e, st) => _Ready(
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xxxl),
                child: Text(
                  'Could not open the database.\n\n$e',
                  textAlign: TextAlign.center,
                  style: context.t.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bar icons are the opposite of what they sit on.
  static Brightness _iconsFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
}

/// What Flutter paints while the system splash is still up: nothing but the
/// background colour.
///
/// This used to draw the mark again, which is what made the splash look like it
/// fired twice — the OS drew it, dropped it when the engine attached, and this
/// redrew it a beat later at a different size. The mark now belongs to the
/// launch window alone; MainActivity holds that window until [_Ready] says boot
/// is done, so these frames are never seen.
class _Holding extends StatelessWidget {
  const _Holding();

  @override
  Widget build(BuildContext context) => const Scaffold();
}

const _bootChannel = MethodChannel('com.deltoid.deltoid/boot');

/// Wraps the first real screen and, once it has actually been laid out, tells
/// the launch window to lift.
///
/// The signal goes after a frame rather than during build: releasing the splash
/// the moment the state flips would uncover a screen that has not painted yet,
/// trading a double mark for a blank one. Sent once per process, and sent on
/// the error path too — an app that cannot open its database still has to be
/// able to say so.
class _Ready extends StatefulWidget {
  const _Ready({required this.child});

  final Widget child;

  @override
  State<_Ready> createState() => _ReadyState();
}

class _ReadyState extends State<_Ready> {
  static bool _sent = false;

  @override
  void initState() {
    super.initState();
    if (_sent || kIsWeb || !Platform.isAndroid) return;
    _sent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A missing handler means the activity is gone or this is a test
      // harness; there is no splash left to lift either way.
      _bootChannel.invokeMethod<void>('bootComplete').catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
