import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Who is signed in, if anyone.
///
/// The id is what every server row is keyed to; the email is what Settings
/// shows so the answer to *which account is this?* is on screen rather than
/// remembered.
class SyncAccount {
  const SyncAccount({required this.id, required this.email});

  final String id;
  final String? email;
}

/// Sign in, sign out, who is signed in — and nothing about rows.
///
/// An interface because the implementation is the one part of sync that cannot
/// be tested without a network and a real Google account. Everything above it
/// takes this type, so the welcome screen and Settings are testable against a
/// fake that never opens a socket, and no widget in `features/` ever imports
/// `package:supabase_flutter` ([SYNC.md § 17](SYNC.md#17-the-architecture)).
/// `test/features/no_supabase_in_features_test.dart` holds that.
abstract interface class SyncAuth {
  /// The account signed in right now, or null for `Local`.
  SyncAccount? get current;

  /// Every change to the above, including the silent refresh that keeps a
  /// session alive and the moment it finally fails.
  Stream<SyncAccount?> get changes;

  /// Opens Google's own sheet, and returns when Supabase has a session.
  ///
  /// Throws [SyncAuthCancelled] when the user backs out, which is an ordinary
  /// answer rather than a failure — nothing is reported, nothing is retried.
  Future<SyncAccount> signInWithGoogle();

  Future<void> signOut();
}

/// The user closed the sheet. Not an error, and never surfaced as one.
class SyncAuthCancelled implements Exception {
  const SyncAuthCancelled();
}

/// Sign-in failed for a reason worth telling the user about.
///
/// [message] is written to be read on a screen: no provider names, no error
/// codes, nothing about tokens.
class SyncAuthFailure implements Exception {
  const SyncAuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A nonce pair: what Google is asked to stamp into the token, and what
/// Supabase is asked to check it against.
///
/// The ID token Google returns is a bearer credential — anything holding one
/// can present it as a sign-in. The nonce is what stops a token captured from
/// somewhere else being replayed here: Google embeds the hash we send, Supabase
/// is given the raw value, and a token minted for any other request carries a
/// hash of a nonce nobody here generated.
///
/// Hashed on the way out and raw on the way in, deliberately — that asymmetry
/// is the mechanism, not an inconsistency. Supabase's *skip nonce checks*
/// switch turns all of this off and exists for a platform that cannot supply
/// one; Android can, so it stays on.
typedef Nonce = ({String raw, String hashed});

Nonce newNonce([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final raw = base64UrlEncode(bytes);
  return (raw: raw, hashed: sha256.convert(utf8.encode(raw)).toString());
}
