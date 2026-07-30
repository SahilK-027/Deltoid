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
          today.hasValue ? const AppShell() : const _BootSpinner(),
      loading: () => const _BootSpinner(),
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

class _BootSpinner extends StatelessWidget {
  const _BootSpinner();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
