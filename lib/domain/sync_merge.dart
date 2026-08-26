/// Who wins a row, and where a loser goes.
///
/// All of [SYNC.md § 8](SYNC.md#8-conflict--two-versions-of-one-row) and
/// [§ 9](SYNC.md#9-collision--two-rows-one-slot), as functions of plain values.
/// `pull.dart` does the input and output — read the scope, ask here, write the
/// answer through `renumber` — which is what makes § 9's twelve rows twelve
/// unit tests rather than twelve integration tests
/// ([SYNC.md § 17](SYNC.md#17-the-architecture)).
///
/// **Every rule here is deterministic and symmetric.** Two devices given the
/// same pair of rows reach the same answer without negotiating, because every
/// decision is a total order over values both of them can see. That is the
/// property convergence rests on, and the reason ties break on `deviceId`
/// rather than on *whichever arrived first*.
library;

import 'enums.dart';
import 'slots.dart';

/// What a row was stamped with by the device that wrote the version in front of
/// you.
///
/// [fingerprint] is the last resort of the order below, and it exists because
/// `deviceId` is not the unique name it reads as: it is minted once into
/// `app_settings`, inside the database file, and a copy of that file opened on
/// another phone writes under the first one's name. Two such installs also walk
/// `nowMs` from one restored floor, so an equal `updatedAt` between them is
/// ordinary rather than a coincidence — and on an exhausted order each device
/// keeps its own version and neither ever learns the other has one.
///
/// It must be **derived from the row and nothing else**, so that both devices
/// compute the same string for the same row without conferring. For two
/// versions of one row that is the row's own values; for two different rows
/// competing over one slot it is the id, which is already unique.
typedef Stamp = ({int updatedAt, String deviceId, String fingerprint});

/// Which version of one row survives.
enum RowVerdict {
  /// The server's row is written over the local one.
  takeRemote,

  /// The local row stands. It is dirty, so the push that follows this pull
  /// sends it and the account converges on it.
  keepLocal,
}

/// Later, with ties broken deterministically.
///
/// A total order on `(updatedAt, deviceId)`. The tie-break is not decoration:
/// [nowMs] has millisecond resolution and two devices saving the same row on
/// the same second is exactly the case sync exists to survive. Without it each
/// device keeps its own version and neither ever learns the other did.
bool _isNewer(Stamp a, Stamp b) {
  if (a.updatedAt != b.updatedAt) return a.updatedAt > b.updatedAt;
  final byDevice = a.deviceId.compareTo(b.deviceId);
  if (byDevice != 0) return byDevice > 0;
  // Same millisecond and the same name on both rows. The order is not out of
  // discriminators yet — the rows themselves differ, or there would be nothing
  // to decide — so it falls to what they differ by. Equal fingerprints mean one
  // row, not two, and `false` is then the right answer in both directions:
  // there is nothing to take.
  return a.fingerprint.compareTo(b.fingerprint) > 0;
}

/// A pulled row, against the local row of the same id.
///
/// **A clean local row always loses.** It is not an edit — it is a copy of what
/// the server already had, because every local write sets `dirty`. So there is
/// nothing to weigh and nothing to lose, and this is the case almost every
/// pulled row is in.
///
/// **A dirty local row is weighed on the phones' own clocks**, and that is the
/// one place this design does what § 8 says it never does. § 8 decides between
/// two versions that both reached the server, on `server_updated_at`; a local
/// row that has never been pushed *has* no server stamp, and the schema does
/// not change to give it one ([§ 4](SYNC.md#4-what-the-server-holds)). So the
/// choice is between two client stamps and no comparison at all, and the
/// alternatives are worse in both directions: taking the remote always would
/// discard an edit made seconds ago on the phone in your hand, and keeping the
/// local always would let a device that has been offline for a month overwrite
/// every newer row on reconnect — which
/// [§ 12](SYNC.md#12-every-edge-case-and-what-it-does) row 10 says must not
/// happen.
///
/// The blast radius is small: it decides only *unpushed local edit against
/// incoming row*, and only until that row is pushed, after which every later
/// conflict is on the server's clock as § 8 requires.
RowVerdict resolveRow({
  required bool localDirty,
  required Stamp local,
  required Stamp remote,
}) {
  if (!localDirty) return RowVerdict.takeRemote;
  return _isNewer(remote, local) ? RowVerdict.takeRemote : RowVerdict.keepLocal;
}

/// Which of two rows claiming one position moves, and where it moves to.
///
/// Four of § 9's indexes are this one rule — sets in an exercise, movements in
/// a workout, exercises in a day, days in a programme — and none of them is an
/// edge case: **appending is the commonest action in the app, and two devices
/// appending to the same parent both compute `max + 1`.**
///
/// **Both live.** The loser is the row created later, which is the greater id:
/// ids are UUID v7 and therefore time-ordered, so both devices sort the pair
/// the same way without asking each other. The mover takes [nextPosition] over
/// the live scope — the same slot a thumb appending right then would have been
/// given.
({String moveId, int toIndex}) resolveSlot({
  required String incomingId,
  required String occupantId,
  required Iterable<int> liveIndexes,
}) {
  assert(incomingId != occupantId, 'a row does not collide with itself');
  return (
    moveId: incomingId.compareTo(occupantId) > 0 ? incomingId : occupantId,
    toIndex: nextPosition(liveIndexes),
  );
}

/// A name a live sibling already answers to, made distinguishable.
///
/// `sessions_name_live` is compared the way a person compares names — trimmed
/// and case-insensitively — so [taken] is the set of live names already folded
/// that way. Suffixed rather than refused, because § 9's rule is that nothing
/// is deleted: two devices that both renamed a day to `Push 1` end up with
/// `Push 1` and `Push 1 (2)`, and the user renames whichever they meant.
///
/// Counts up until the name is free, so a third collision is `(3)` and not a
/// second `(2)` that collides all over again.
String disambiguateName(String name, Set<String> taken) {
  final base = name.trim();
  if (!taken.contains(base.toLowerCase())) return base;
  for (var n = 2;; n++) {
    final candidate = '$base ($n)';
    // The column is capped at 60 characters, and a suffix must not be what
    // pushes a legal name over it — the CHECK would refuse the row and strand
    // it, which is the one outcome a merge may not produce.
    final trimmed = candidate.length <= 60
        ? candidate
        : '${base.substring(0, 60 - ' ($n)'.length)} ($n)';
    if (!taken.contains(trimmed.toLowerCase())) return trimmed;
  }
}

/// Which of two rows that are both open stays open.
///
/// `workouts_single_open` and `cycles_regime_open_live` are the same question
/// asked of two tables, and § 9 gives them the same answer: **the newer stays
/// open, the older is completed — never discarded, because its sets are real
/// work.** `healDuplicateOpenCycles` already writes exactly this for cycles,
/// which is what makes it the answer rather than a new one.
///
/// Ordered on `startedAt` rather than `updatedAt`: which session began later is
/// a fact about the training, and it does not move when a note is edited. The
/// id breaks a tie, as everywhere else.
String staysOpen({
  required ({String id, int startedAt}) a,
  required ({String id, int startedAt}) b,
}) {
  if (a.startedAt != b.startedAt) return a.startedAt > b.startedAt ? a.id : b.id;
  return a.id.compareTo(b.id) > 0 ? a.id : b.id;
}

/// Which regime is the active one, out of every live regime on the phone.
///
/// **The flag is a singleton, so it cannot be merged row by row.** Activating a
/// regime deactivates another, which is two rows moving for one decision;
/// last-write-wins is defined on one row at a time and has nothing to say about
/// that. Resolving it pairwise — each arriving row against whatever happened to
/// be active when it landed — makes the answer depend on the order rows arrive
/// in, and two phones pulling in different orders reached opposite answers.
/// Nothing then corrected them: the losing side's deactivation minted no new
/// version on purpose, so both copies carried one version and two values, and
/// each looked up to date to the other forever. `sync_fuzz_test` seeds 41, 146,
/// 335 and 531, and [Regimes.activatedAt] carries the rest of the story.
///
/// So the answer is computed from all of them at once, and from a column that
/// merges like any other: **the live regime holding the highest
/// `activatedAt`.** A pure function of rows both phones agree on is the same
/// answer on both phones however the rows got there, which is the whole
/// property that was missing.
///
/// **Null is not zero.** A regime nobody has ever activated is not a candidate,
/// so deleting the only one that was ever active leaves *none* active rather
/// than promoting a programme the user never chose — `deleteRegime` picks the
/// successor deliberately, and stamps it. Null in, null out: with no candidate
/// this returns null and every live regime is left inactive, which is the same
/// state a phone is in before the first regime is created.
///
/// `deviceId` then the `id` break a tie, exactly as [Stamp] does everywhere
/// else, so two activations in one millisecond still settle the same way twice.
String? resolveActiveRegime(
  Iterable<({String id, int? activatedAt, String deviceId})> live,
) {
  ({String id, int activatedAt, String deviceId})? best;
  for (final r in live) {
    final at = r.activatedAt;
    if (at == null) continue;
    final candidate = (id: r.id, activatedAt: at, deviceId: r.deviceId);
    if (best == null ||
        _isNewer(
          (
            updatedAt: candidate.activatedAt,
            deviceId: candidate.deviceId,
            fingerprint: candidate.id,
          ),
          (
            updatedAt: best.activatedAt,
            deviceId: best.deviceId,
            fingerprint: best.id,
          ),
        )) {
      best = candidate;
    }
  }
  return best?.id;
}

/// The identity hue a regime takes when the one it arrived wearing is held, or
/// null when the shelf is full.
///
/// Lowest free slot, exactly as `nextIdentitySlot` hands out to a new regime.
///
/// **Null is a real answer, and § 12 row 15 is wrong about it.** That row says a
/// full shelf wraps and two programmes share a colour — which `identityAt`'s
/// modulo was written for and which the schema forbids outright:
/// `identity_index` carries `CHECK (0..${identitySlots - 1})` *and* a unique
/// index over live rows, so **six live regimes is the ceiling**, and five live
/// plus two devices each creating one offline is seven rows for six slots. No
/// re-slotting makes that fit.
///
/// So the applier lands the seventh **tombstoned** and says so: the regime, and
/// every session, workout and set under it, arrive and are kept — § 15 rule 2
/// holds, nothing logged is deleted — and the one thing lost is that the
/// programme is not on the shelf until something frees a slot. Refusing the row
/// outright would orphan its children, which is the same loss with more steps.
int? freeIdentitySlot(Set<int> taken) {
  for (var i = 0; i < identitySlots; i++) {
    if (!taken.contains(i)) return i;
  }
  return null;
}

/// The number a cycle takes when its own is already held in that regime.
///
/// Cycles number from 1 and count up — `planNextCycle` reads the last one — so
/// the next free number is one past the highest, never a hole in the middle. A
/// hole would be read as a cycle that was deleted rather than one that was
/// renumbered, and Today counts up from the last.
int freeCycleIndex(Iterable<int> taken) {
  final next = nextPosition(taken);
  return next < 1 ? 1 : next;
}

/// Which of two bodyweight readings for one day survives.
///
/// The one case in § 9 where the two rows are **genuinely the same
/// measurement**: one person, one morning, one scale. So this is ordinary last
/// write wins and the loser is tombstoned rather than re-slotted — there is no
/// second slot to move it to, and keeping both would mean every
/// bodyweight-scored lift that day read whichever the query returned first.
bool remoteWinsTheDay({required Stamp local, required Stamp remote}) =>
    _isNewer(remote, local);
