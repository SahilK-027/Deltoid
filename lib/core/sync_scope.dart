import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_providers.dart';

/// Keeps the sync engine alive, and tells it when the app comes forward.
///
/// **The lifecycle hook is new.** There is exactly one
/// `WidgetsBindingObserver` in this app and it belongs to the log screen, which
/// is already carrying the rest alarm; sync mounts its own at the root
/// ([SYNC.md § 18](SYNC.md#18-the-phases), phase 3). At the root because a
/// resume matters most on the screen sync is *not* on: the phone was in a
/// pocket between sets, and the rows owed are the ones logged before it went
/// there.
///
/// Above the boot gate, so the engine exists while the database is still being
/// looked over. It pushes nothing until there is an account, and reading
/// [syncEngineProvider] is what constructs it — nothing else watches it, by
/// design.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncEngineProvider)?.resumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: the backend resolves a beat after launch, and
    // an engine that was null at first build has to be constructed when it
    // stops being one.
    ref.watch(syncEngineProvider);
    return widget.child;
  }
}
