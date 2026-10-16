import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../../domain/phases.dart';
import '../db/database.dart';
import '../db/watch.dart';

/// Bulk, cut and maintenance: the writes the phase sheet and the Phase card
/// make, and the one read both of them need.
///
/// Every write is to the row it names and to no other. Where a phase ends is
/// derived from the next one's start ([phaseSpans]), so starting a phase never
/// edits the phase before it, and two phones never have to agree on a pair of
/// rows ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)).
class PhaseRepository {
  PhaseRepository(this.db);

  final AppDatabase db;

  /// Every live phase, oldest first.
  ///
  /// Unbounded, and it does not need a bound: one row per declaration, a few
  /// a year.
  Future<List<PhaseEntry>> phases() async {
    final rows = await (db.select(db.phases)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.dayKey)]))
        .get();
    return [for (final row in rows) _entry(row)];
  }

  /// [phases], re-read whenever the table changes.
  Stream<List<PhaseEntry>> watchPhases() =>
      db.watchQuery([db.phases], phases);

  /// Starts a [kind] phase on [from], and returns its id.
  ///
  /// The phase before it is not touched: it now ends the day before [from]
  /// because that is where this one starts. A live phase already starting on
  /// [from] is replaced, which is how a mis-tapped phase is corrected
  /// ([THEME → Phase sheet](THEME.md#phase-sheet)); the look-up and the
  /// write are one transaction so a double tap on Save cannot leave two.
  Future<String> startPhase(
    PhaseKind kind, {
    required DateTime from,
    int? plannedWeeks,
  }) {
    assert(plannedWeeks == null || phasePlannedWeeks.contains(plannedWeeks));
    final key = dayKeyOf(from);
    return db.transaction(() async {
      await (db.update(db.phases)
            ..where((t) => t.dayKey.equals(key) & t.deletedAt.isNull()))
          .write(PhasesCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        deviceId: Value(currentDeviceId),
        dirty: const Value(true),
      ));
      final id = newId();
      await db.into(db.phases).insert(PhasesCompanion.insert(
            id: Value(id),
            kind: kind,
            dayKey: key,
            plannedWeeks: Value(plannedWeeks),
          ));
      return id;
    });
  }

  /// Corrects the start day and planned length of the phase [id].
  ///
  /// The sheet saves this when the phase it opened with is still the one
  /// selected. The kind is not an argument: a different kind is a new phase,
  /// started with [startPhase].
  Future<void> editPhase(
    String id, {
    required DateTime from,
    int? plannedWeeks,
  }) {
    assert(plannedWeeks == null || phasePlannedWeeks.contains(plannedWeeks));
    return _write(
      id,
      PhasesCompanion(
        dayKey: Value(dayKeyOf(from)),
        plannedWeeks: Value(plannedWeeks),
      ),
    );
  }

  /// Ends the phase [id] on [on], leaving no phase after it.
  ///
  /// An end day on the row rather than a row meaning "no phase": the cleared
  /// phase keeps tinting the cycles it covered, and one phone clearing while
  /// another edits stays one row for last-write-wins to decide
  /// ([SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does), row 21).
  Future<void> clearPhase(String id, {required DateTime on}) =>
      _write(id, PhasesCompanion(endDayKey: Value(dayKeyOf(on))));

  /// Answers the planned-length prompt with `Keep going`.
  ///
  /// The phase becomes open-ended, so [plannedLengthPassed] is false from here
  /// on and the question is asked once.
  Future<void> keepGoingPastPlan(String id) =>
      _write(id, const PhasesCompanion(plannedWeeks: Value(null)));

  /// Answers the weigh-in prompt with `Keep going` on [on].
  ///
  /// [weighInsAgainstPhase] reads only the weigh-ins after this day, so the
  /// question returns only once three more weeks have run against the phase.
  Future<void> keepGoingAgainstWeighIns(String id, {required DateTime on}) =>
      _write(id, PhasesCompanion(keptDayKey: Value(dayKeyOf(on))));

  /// One edit to one row, stamped as this device's write.
  Future<void> _write(String id, PhasesCompanion changes) async {
    await (db.update(db.phases)..where((t) => t.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(nowMs()),
        deviceId: Value(currentDeviceId),
        dirty: const Value(true),
      ),
    );
  }

  static PhaseEntry _entry(Phase row) => PhaseEntry(
        id: row.id,
        kind: row.kind,
        startKey: row.dayKey,
        plannedWeeks: row.plannedWeeks,
        endKey: row.endDayKey,
        keptKey: row.keptDayKey,
      );
}
