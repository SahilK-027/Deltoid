import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v7: time-ordered, generated offline, safe to use as a primary key that
/// syncs to Postgres without coordination.
String newId() => _uuid.v7();

/// The highest stamp this process has handed out. See [nowMs].
int _lastStamp = 0;

/// Now, in UTC milliseconds, and **never earlier than the last one**.
///
/// This is the number last-write-wins compares, so a clock that moves backwards
/// does not merely mislabel a row — it makes the row lose to the version it was
/// written to replace, and keep losing until real time catches up. Android moves
/// this clock without asking: a network time correction after a flat battery, a
/// manual change, a timezone database update mid-session.
///
/// Clamping to the last value issued is the local half of the answer. Two rows
/// written inside the same clamped millisecond are then separated by
/// `deviceId`, exactly as [currentDeviceId] describes. The other half —
/// agreeing on time with a *different* device — is a server's job.
///
/// **The clamp survives a restart**, and it has to: a mark held only in memory
/// protects one run of the app, and the failure it exists for is precisely the
/// one that spans a launch. A phone comes off a flat battery with its clock at
/// the build date, the app opens, a session is logged, and the network corrects
/// the clock an hour later. Every row from that session carries a stamp from
/// the past, loses to the version it replaced on the next merge, and keeps
/// losing — `resolveRow` never revisits a verdict. `AppDatabase` seeds this
/// from `app_settings` at open and writes it back; see [seedStampFloor].
int nowMs() {
  final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
  return _lastStamp = wall > _lastStamp ? wall : _lastStamp + 1;
}

/// The highest stamp handed out so far, for whoever is writing it down.
int get stampMark => _lastStamp;

/// Raises the clamp to a mark read back from `app_settings`.
///
/// Called by [AppDatabase]'s `beforeOpen`, before any write can run. Raises
/// only: a wall clock honestly ahead of the stored mark is the normal case and
/// needs nothing, and a mark restored from an older export must not drag a
/// healthy clock backwards.
void seedStampFloor(int stamp) {
  if (stamp > _lastStamp) _lastStamp = stamp;
}

/// `app_settings` key holding the highest stamp this install may have used.
const lastStampKey = 'last_stamp';

/// How far past the clock the mark is written at open.
///
/// The mark cannot be rewritten on every stamp: `nowMs` is called from inside
/// every write, so a write of its own from there lands in whatever transaction
/// the caller opened — and under `testWidgets`, in whatever fake-async zone the
/// test is pumping. Escaping either is worse than the problem.
///
/// So it is written twice, at the two moments that are neither: once at open,
/// far enough ahead to cover an ordinary session, and once at close, at the
/// mark actually reached. A kill in between loses nothing as long as the
/// session was shorter than this — and if it was longer, the stamps at risk are
/// only the ones past the lease.
///
/// **`max(wall + lease, stored)`, never `stored + lease`.** The second
/// compounds: a phone relaunched twenty times in a minute would walk the mark
/// twenty leases into the future and every row it stamped would beat every row
/// from every other device, permanently. The first is bounded by the clock.
const stampLeaseMs = 5 * 60 * 1000;

/// Which install wrote a row.
///
/// Last-write-wins compares `updatedAt`, and two devices can stamp the same
/// millisecond — [nowMs] has exactly the resolution needed for that to happen
/// on a shared save. The device id is what breaks the tie deterministically,
/// so both sides pick the same winner instead of each keeping its own.
///
/// Resolved once per open, from `app_settings`, before any write can run. It
/// is the empty string only in the window before a database has been opened,
/// which no repository call can be inside.
String _deviceId = '';

String get currentDeviceId => _deviceId;

/// Set by [AppDatabase]'s `beforeOpen`. Not for callers.
void setCurrentDeviceId(String id) => _deviceId = id;

/// `app_settings` key holding this install's device id.
const deviceIdKey = 'device_id';

/// Resets the monotonic clock. Tests only — a fresh in-memory database in the
/// same process would otherwise inherit the stamps of the one before it, and
/// now the listener of the one before it too.
void resetStampsForTesting() => _lastStamp = 0;

/// Local calendar day as `yyyyMMdd`. Used for heatmap grouping and bodyweight
/// entries, where "which day was it for me" matters more than the exact instant.
int dayKeyOf(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

/// Minutes east of UTC that [date] carries — its zone at *its own* instant, not
/// the phone's zone now.
///
/// The counterpart to [dayKeyOf]: written beside it on every workout so the
/// database can check that the day key and the timestamp name the same day. See
/// `Workouts.tzOffsetMinutes`.
int tzOffsetOf(DateTime date) => date.timeZoneOffset.inMinutes;

DateTime dateFromDayKey(int key) =>
    DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

/// The calendar date [days] before [date], at local midnight.
///
/// **Named, not subtracted.** `date.subtract(Duration(days: n))` is `n * 86400`
/// seconds of absolute time, and a day that contains a clock change is 23 or 25
/// hours long — so the result lands on 23:00 or 01:00 of a neighbouring day
/// rather than on midnight. Dart normalises an out-of-range day component, so
/// `DateTime(2026, 3, -4)` is 24 February and this needs no month arithmetic of
/// its own.
///
/// [days] may be negative, which walks forward.
DateTime daysBefore(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day - days);

/// Whole calendar days from [from] to [to], counting dates rather than hours.
///
/// UTC on both sides, which is the pattern the two heatmaps already use
/// (`heatmap.dart:89-99`, `year_heatmap.dart:55-67`). Only y/m/d is read off
/// each side, so the zone never escapes the expression — and taking the
/// difference of two *local* midnights instead would truncate 13 d 23 h to 13
/// across a spring-forward, which is how "yesterday" reads as "today" twice a
/// year.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// [daysBetween] for two `yyyyMMdd` keys.
///
/// A `dayKey` is not a day count — `toKey - fromKey` is 76 across a month end
/// and 8 870 across a New Year — so a span between keys has to go through the
/// calendar, never through subtraction.
int daysBetweenKeys(int fromKey, int toKey) =>
    daysBetween(dateFromDayKey(fromKey), dateFromDayKey(toKey));
