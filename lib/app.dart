import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/shell/app_shell.dart';
import 'features/today/today_providers.dart';

class DeltoidApp extends ConsumerWidget {
  const DeltoidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dark until the stored preference resolves, so first paint never flashes
    // white on a dark-mode phone.
    final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.dark;

    return MaterialApp(
      title: 'Deltoid',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
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
    final init = ref.watch(appInitProvider);
    // Waiting on Today here rather than inside the shell keeps the tab bar from
    // sliding in over an empty page. It is one local query behind the seeder,
    // so this costs a frame or two, not a visible wait.
    final today = ref.watch(todayProvider);

    return init.when(
      data: (_) =>
          today.hasValue ? const AppShell() : const _BootMark(),
      loading: () => const _BootMark(),
      error: (e, st) => Scaffold(
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
    );
  }
}

/// The same mark, at the same size and on the same colour as the launch window
/// the system just drew. Boot is short and bounded by real work, so a spinner
/// only advertised that something was slow; holding the mark makes the handoff
/// from the launch window to Flutter's first frame invisible instead.
class _BootMark extends StatelessWidget {
  const _BootMark();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        // 150dp is what the platform splash draws: 52% of its 288dp canvas,
        // the widest the mark can be and still clear the 192dp circular mask.
        child: Image.asset(
          dark ? 'assets/brand/mark_white.png' : 'assets/brand/mark_ink.png',
          width: 150,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
