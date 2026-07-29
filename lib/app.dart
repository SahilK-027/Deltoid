import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/shell/app_shell.dart';

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

/// Blocks first paint until the schema exists and the starting programme is
/// seeded, so no screen ever has to render a half-initialised database.
class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(appInitProvider);
    return init.when(
      data: (_) => const AppShell(),
      loading: () => const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
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
