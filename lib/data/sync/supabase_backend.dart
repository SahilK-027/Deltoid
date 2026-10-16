import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/table_spec.dart';
import 'sync_auth.dart';
import 'sync_backend.dart';
import 'sync_config.dart';

/// The only two packages in this file, and the only file they are in.
///
/// Everything above this takes [SyncAuth] and, later, the transport interface —
/// so swapping the backend, or testing without one, is a constructor argument
/// rather than an excavation. `features/` never imports either package, which
/// `test/features/no_supabase_in_features_test.dart` holds to.
///
/// No socket is ever opened. Realtime is not initialised and will not be:
/// two phones do not need to see each other's writes within seconds, and a held
/// connection costs a battery budget to serve a case that does not occur
/// ([SYNC.md § 1](SYNC.md#1-what-this-is-and-is-not)).
class SupabaseBackend implements SyncBackend {
  SupabaseBackend._(this.client, this._config);

  /// Starts the client, once per process.
  ///
  /// Returns null when the build carries no configuration — a clone of this
  /// repo, or `flutter test`. That is a working app that cannot sync, not a
  /// broken one.
  static Future<SupabaseBackend?> start(SyncConfig config) async {
    if (!config.isConfigured) return null;
    final supabase = await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      // The session is persisted and refreshed silently, so a signed-in user
      // sees the sign-in screen exactly once and never again unless they sign
      // out or the refresh token is revoked — SYNC.md § 3.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return SupabaseBackend._(supabase.client, config);
  }

  final SupabaseClient client;
  final SyncConfig _config;

  late final SyncAuth auth = _GoogleSupabaseAuth(client, _config);

  /// Upserts on the primary key, which is `id` on all nine tables.
  ///
  /// `user_id` is never in [rows]: the column defaults to `auth.uid()` and RLS
  /// checks it with `with check`, so the one value a client must not be trusted
  /// to assert is one it never sends.
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _guard(() => client.from(table).upsert(rows));
  }

  @override
  Future<List<Map<String, dynamic>>> since(
    String table,
    DateTime? cursor, {
    required int limit,
  }) async {
    final rows = await _guard(() {
      final query = client.from(table).select();
      // `gte`, not `gt` — see [SyncBackend.since].
      final filtered = cursor == null
          ? query
          : query.gte(serverUpdatedAtColumn, cursor.toUtc().toIso8601String());
      return filtered.order(serverUpdatedAtColumn, ascending: true).limit(limit);
    });
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  @override
  Future<int> count(String table) =>
      _guard(() => client.from(table).count(CountOption.exact));

  @override
  Future<DateTime?> latestAt(String table, String column) async {
    final rows = await _guard(
      () => client
          .from(table)
          .select(column)
          .order(column, ascending: false)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    final value = rows.first[column];
    // Every date column here is the phones' epoch-ms integer rather than a
    // timestamptz, and PostgREST may hand a bigint over as either.
    final ms = value is int ? value : int.tryParse('$value');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Everything the network can do, as the two answers sync has for it.
  ///
  /// A `PostgrestException` means the request reached PostgREST and was
  /// refused — a policy, a column that does not exist, a row it will not take —
  /// and retrying changes nothing, so it is worth saying out loud. Its 5xx
  /// codes are the exception: the server was there and unwell, which is the
  /// same shape as no server at all. Everything else — a socket, a DNS failure,
  /// a timeout, an expired token that could not be refreshed — is a phone
  /// without signal, and a phone without signal is not an error
  /// ([SYNC.md § 13](SYNC.md#13-when-it-fails)).
  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      throw SyncTransportFailure(
        'Your account could not be reached. ${e.message}',
        transient: code.startsWith('5') || code.isEmpty,
      );
    } on Object catch (e) {
      throw SyncTransportFailure('$e', transient: true);
    }
  }
}

class _GoogleSupabaseAuth implements SyncAuth {
  _GoogleSupabaseAuth(this._client, this._config);

  final SupabaseClient _client;
  final SyncConfig _config;

  /// Google is initialised once per process, and the nonce it is given is fixed
  /// at that moment.
  ///
  /// `GoogleSignIn.initialize` takes the nonce, not `authenticate`, so a nonce
  /// per sign-in would mean re-initialising the plugin per sign-in — which its
  /// own documentation says not to do. One per process is enough for what the
  /// nonce is for: a token stamped with it cannot be replayed into any other
  /// process, and sign-in happens once in the life of an install.
  Nonce? _nonce;
  Future<void>? _initialising;

  Future<Nonce> _google() async {
    final nonce = _nonce ??= newNonce();
    await (_initialising ??= GoogleSignIn.instance.initialize(
      serverClientId: _config.googleWebClientId,
      nonce: nonce.hashed,
    ));
    return nonce;
  }

  @override
  SyncAccount? get current => _accountOf(_client.auth.currentUser);

  /// Who is signed in, as events rather than errors.
  ///
  /// The client refreshes its token on a timer, and a refresh that cannot reach
  /// the server — a phone in a gym with no signal — is put on this stream as an
  /// error rather than thrown. Nothing about the account has changed: the
  /// session is still on disk and the next refresh with signal succeeds. A
  /// refresh token that has truly been revoked arrives as a `signedOut` event,
  /// not as an error. Passed along, the error reached the zone handler in
  /// `main`, which announced every token refresh in the gym as "That change was
  /// not saved." in red, over a log that had saved everything
  /// ([SYNC.md § 13](SYNC.md#13-when-it-fails): no network shows nothing).
  @override
  Stream<SyncAccount?> get changes => _client.auth.onAuthStateChange
      .map((event) => _accountOf(event.session?.user))
      .handleError((Object _) {});

  SyncAccount? _accountOf(User? user) => user == null ? null : _account(user);

  /// The name comes from Google's claims, which Supabase keeps in the user's
  /// metadata as `full_name` and, on some sign-ins, `name` alone.
  static SyncAccount _account(User user) {
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final name = [meta['full_name'], meta['name']]
        .whereType<String>()
        .map((n) => n.trim())
        .firstWhere((n) => n.isNotEmpty, orElse: () => '');
    return SyncAccount(
      id: user.id,
      email: user.email,
      name: name.isEmpty ? null : name,
      createdAt: DateTime.tryParse(user.createdAt)?.toLocal(),
    );
  }

  @override
  Future<SyncAccount> signInWithGoogle() async {
    final nonce = await _google();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Backing out of the sheet is an answer, not a failure. Everything else
      // is worth a sentence — Google's own messages name client ids and
      // fingerprints, which belong in a log rather than on a screen.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SyncAuthCancelled();
      }
      throw const SyncAuthFailure("Google couldn't sign you in just now.");
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const SyncAuthFailure("Google didn't return a sign-in token.");
    }

    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        // The raw value against the hash Google stamped in. See [Nonce].
        nonce: nonce.raw,
      );
      final user = response.user;
      if (user == null) {
        throw const SyncAuthFailure('That sign-in did not complete.');
      }
      return _account(user);
    } on AuthException {
      throw const SyncAuthFailure(
        "Your account couldn't be reached. Try again when you have signal.",
      );
    }
  }

  @override
  Future<void> signOut() async {
    // Google first, so the next sign-in asks which account rather than
    // silently reusing the one just signed out of.
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Already signed out of Google, or Google is unreachable. Neither
      // changes what has to happen here.
    }
    await _client.auth.signOut();
  }
}
