import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_auth.dart';
import 'sync_config.dart';

/// The only two packages in this file, and the only file they are in.
///
/// Everything above this takes [SyncAuth] and, later, the transport interface —
/// so swapping the backend, or testing without one, is a constructor argument
/// rather than an excavation. `features/` never imports either package, which
/// `test/features/no_supabase_in_features_test.dart` holds to.
///
/// **No socket is ever opened.** Realtime is not initialised and never will be:
/// two phones do not need to see each other's writes within seconds, and a held
/// connection costs a battery budget to serve a case that does not occur
/// ([SYNC.md § 1](SYNC.md#1-what-this-is-and-is-not)).
class SupabaseBackend {
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

  @override
  Stream<SyncAccount?> get changes => _client.auth.onAuthStateChange.map(
    (event) => _accountOf(event.session?.user),
  );

  SyncAccount? _accountOf(User? user) =>
      user == null ? null : SyncAccount(id: user.id, email: user.email);

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
      return SyncAccount(id: user.id, email: user.email);
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
