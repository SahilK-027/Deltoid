/// The transport, as three methods and no package.
///
/// [SYNC.md § 17](SYNC.md#17-the-architecture): everything above this deals in
/// `Map<String, dynamic>`, never in typed rows. That is the same currency the
/// backup codec speaks, and the only one that can carry a column this build has
/// never heard of — which [SYNC.md § 14](SYNC.md#14-two-builds-one-account)
/// requires it to carry rather than choke on.
///
/// **The fake is the point.** An in-memory implementation with its own
/// monotonic clock, able to misbehave deliberately — drop the response after
/// committing the write, hand back a row from a newer build, fail every third
/// call — is what makes [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does)
/// testable at all. No test talks to a real Supabase.
abstract interface class SyncBackend {
  /// Upserts a batch on `id`, in one request.
  ///
  /// Idempotent, so a retry after a half-finished push is safe and needs no
  /// bookkeeping — [SYNC.md § 6](SYNC.md#6-push). [rows] are wire rows: snake
  /// case keys, no `user_id`, no `server_updated_at`.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Every row stamped at or after [cursor], oldest first, at most [limit] of
  /// them. Null pulls the account from its beginning.
  ///
  /// **At or after, not after.** Two rows can share a `server_updated_at`, and
  /// a strict `>` drops whichever one falls on the far side of a page boundary
  /// — silently, once, with no second chance. Re-reading the boundary row costs
  /// an upsert that is idempotent anyway.
  Future<List<Map<String, dynamic>>> since(
    String table,
    DateTime? cursor, {
    required int limit,
  });

  /// How many rows the account holds in [table].
  ///
  /// Exists so [SYNC.md § 10](SYNC.md#10-adoption)'s prompt can say *214
  /// sessions* rather than *some*.
  Future<int> count(String table);
}

/// A request did not go through.
///
/// [transient] is the difference between *no signal* and *the server refused
/// this row*: the first is the ordinary state of a phone in a basement and the
/// user is told nothing about it, and the second is a bug that will repeat on
/// every retry until somebody hears about it
/// ([SYNC.md § 13](SYNC.md#13-when-it-fails)). Both back off; only one is worth
/// a sentence.
class SyncTransportFailure implements Exception {
  const SyncTransportFailure(this.message, {required this.transient});

  final String message;
  final bool transient;

  @override
  String toString() => message;
}
