import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/failure.dart';
import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'core/widgets/scroll.dart';
import 'core/widgets/toast.dart';
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
      builder: (context, child) {
        // **The one place text scale is decided.** The type scale runs 11 to
        // 30sp and half this app is a table: the log's set rows, the keypad's
        // keys and every button are fixed heights with text inside them, so at
        // the top of Android's font slider the keypad overflows and the log
        // stops being readable at exactly the moment it is being used.
        //
        // Clamped rather than ignored. Refusing to scale at all is the other
        // way to break this, and the 30% that fits is worth having — it is the
        // difference between a `micro` label at 11 and one at 14.
        final scaler = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        );
      },
      home: const _FailureToasts(child: _Boot()),
    );
  }
}

/// Speaks the app's failures out loud.
///
/// Under `MaterialApp` rather than inside the shell, for two reasons: it needs
/// the `ScaffoldMessenger` that `MaterialApp` builds, and the screen a write
/// fails on is very often the log — which is pushed *over* the shell. A
/// listener down in a tab would be silent for exactly the screen that writes
/// most.
///
/// A toast rather than a dialog: this reports things that have already happened
/// and that the user cannot act on from here, and the one rule a transient
/// message has to obey is not standing in front of the next set (THEME →
/// Toast).
class _FailureToasts extends StatefulWidget {
  const _FailureToasts({required this.child});

  final Widget child;

  @override
  State<_FailureToasts> createState() => _FailureToastsState();
}

class _FailureToastsState extends State<_FailureToasts> {
  StreamSubscription<AppFailure>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = failures.listen((failure) {
      if (!mounted) return;
      // The messenger, not the context, and read at the moment of the failure:
      // whatever route is on top is the one that should carry the message.
      showToastOn(ScaffoldMessenger.of(context), failure.what,
          destructive: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
