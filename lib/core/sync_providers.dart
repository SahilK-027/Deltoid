import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/seed/seeder.dart';
import '../data/sync/adoption.dart';
import '../data/sync/connectivity.dart';
import '../data/sync/supabase_backend.dart';
import '../data/sync/sync_auth.dart';
import '../data/sync/sync_config.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_state.dart';
import 'providers.dart';

/// Which answer the welcome screen was given, or null if it has not been asked.
///
/// One question, asked once ([THEME.md](THEME.md) → the welcome screen), so
/// this is the whole of its memory. It is not a record of whether sync is *on*
/// — signing out later leaves this answered, and rightly: the question has been
/// put and does not come back.
const welcomeKey = 'welcome';

enum WelcomeAnswer {
  /// Signed in on the welcome screen.
  account,

  /// `Use without an account`. A real answer, final and repairable from
  /// Settings — [SYNC.md § 3](SYNC.md#3-identity).
  local,
}

/// Whether the welcome screen has been answered, watched so answering it
/// swaps the screen underneath.
final welcomeAnsweredProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.appSettings)..where((t) => t.key.equals(welcomeKey));
  return query.watch().map((rows) => rows.isNotEmpty);
});

/// The same question asked once, off a stream, for the code paths that run
/// before any widget exists.
Future<bool> welcomeAnswered(AppDatabase db) async {
  final row = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(welcomeKey)))
      .getSingleOrNull();
  return row != null;
}

/// Records the answer, and seeds the catalog if it is still empty.
///
/// **Order is the point.** The catalog is written *before* the flag, so the
/// moment [welcomeAnsweredProvider] flips there is already a catalog to train
/// from — the shell renders over a database that is finished rather than one
/// that is filling in behind it. Killed in between, the flag is absent and the
/// screen simply asks again, which is the harmless half of the failure.
///
/// **[seed] is false on the one path that has already dealt with the catalog.**
/// Signing in runs [AdoptionService.adopt] first, and an account that holds a
/// catalog hands over the user's own — with their notes and their edits on it —
/// rather than being given a second one under different ids. Seeding anyway
/// would leave roughly 120 exercises twice over, "Bench Press" under two ids,
/// and a history split across both, which breaks the one thing this app exists
/// for ([SYNC.md § 10](SYNC.md#10-adoption)).
Future<void> answerWelcome(
  AppDatabase db,
  WelcomeAnswer answer, {
  bool seed = true,
}) async {
  if (seed) await ensureStarterCatalog(db);
  await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: welcomeKey, value: answer.name),
      );
}

/// Whether this build was given an account to reach at all.
///
/// Read this rather than `syncBackendProvider` when the question is what to
/// *draw*. The backend is a `FutureProvider` and is null while it starts, so a
/// control hidden on that would flicker into existence on every launch of a
/// configured build; this answers the same question from a compile-time
/// constant and never changes.
///
/// **A build that cannot sign in must not offer to.** An unconfigured build
/// has no account feature, and a control that produces only an error message
/// is claiming one it does not have.
final syncConfiguredProvider = Provider<bool>(
  (ref) => SyncConfig.fromEnvironment.isConfigured,
);

/// The client, started once per process, or null when this build carries no
/// configuration.
///
/// Null is an ordinary state, not a failure: `flutter test` runs in it, and so
/// does a clone of this repo. Everything downstream reads null as *this app
/// cannot reach an account*, and every screen still works — no read waits on a
/// server ([SYNC.md § 15](SYNC.md#15-what-sync-may-never-do) rule 1).
final syncBackendProvider = FutureProvider<SupabaseBackend?>(
  (ref) => SupabaseBackend.start(SyncConfig.fromEnvironment),
);

/// The three shapes at sign-in. Null when this build carries no configuration,
/// which is a build that cannot reach an account and so has nothing to adopt.
final adoptionProvider = Provider<AdoptionService?>((ref) {
  final backend = ref.watch(syncBackendProvider).valueOrNull;
  if (backend == null) return null;
  return AdoptionService(ref.watch(databaseProvider), backend);
});

/// Sign in, sign out, who is signed in. Null when there is no backend.
final syncAuthProvider = Provider<SyncAuth?>(
  (ref) => ref.watch(syncBackendProvider).valueOrNull?.auth,
);

/// The account signed in right now.
///
/// Seeded with what the client already knows, so a signed-in launch does not
/// spend a frame looking signed out before the first event arrives — a session
/// is restored from disk, not fetched.
final accountProvider = StreamProvider<SyncAccount?>((ref) {
  final auth = ref.watch(syncAuthProvider);
  if (auth == null) return Stream.value(null);
  return auth.changes.startWith(auth.current);
});

/// The engine, started once and running for the life of the process.
///
/// Null when this build carries no configuration, which is a working app that
/// cannot sync rather than a broken one — `flutter test` runs in exactly that
/// state and so does a clone of this repo.
///
/// Nothing watches this for a value. It is kept alive by [SyncScope] at the
/// root, and everything a screen wants to know about sync comes off
/// [syncStateProvider], which reads the database rather than the engine
/// ([SYNC.md § 17](SYNC.md#17-the-architecture) — the state is read, not
/// remembered).
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final backend = ref.watch(syncBackendProvider).valueOrNull;
  if (backend == null) return null;

  final engine = SyncEngine(db: ref.watch(databaseProvider), backend: backend);
  engine.start(
    // Distinct, so a token refresh — which emits an account every hour — is not
    // a sign-in and does not trigger a drain of its own.
    signedIn: backend.auth.changes
        .map((account) => account != null)
        .startWith(backend.auth.current != null)
        .distinct(),
    networkRegained: networkRegained(),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// What the welcome screen was answered with, or null if it has not been.
///
/// Read rather than watched: the answer is written once and the screens that
/// care are built after it. What it is *for* is the difference between a phone
/// that chose to stay local and one that is signed out because a token could
/// not be refreshed — the first is working as asked and the second is
/// [SYNC.md § 13](SYNC.md#13-when-it-fails) row 2, where Settings asks for a
/// sign-in and the app keeps working.
final welcomeAnswerProvider = FutureProvider<WelcomeAnswer?>((ref) async {
  final db = ref.watch(databaseProvider);
  final row = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(welcomeKey)))
      .getSingleOrNull();
  return WelcomeAnswer.values
      .where((answer) => answer.name == row?.value)
      .firstOrNull;
});

/// Why the last drain did not land, or null when it did.
///
/// Off the engine rather than the database, because it is the one thing about
/// sync that is *not* on disk: nothing about a row says whether the last
/// attempt to send it hit a basement or a refusal
/// ([SYNC.md § 13](SYNC.md#13-when-it-fails)).
final syncTroubleProvider = StreamProvider<SyncTrouble?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return Stream.value(null);
  // Seeded with what the engine already knows: a failure that happened before
  // this screen was opened is exactly the one worth explaining.
  return engine.troubles.startWith(engine.trouble);
});

/// Local, Synced or Pending, off the database.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final account = ref.watch(accountProvider).valueOrNull;
  return watchSyncState(
    ref.watch(databaseProvider),
    signedIn: account != null,
  );
});

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
