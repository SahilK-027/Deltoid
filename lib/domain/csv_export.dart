/// The training log as rows a spreadsheet can open.
///
/// The backup file is this app's own JSON, which is the right shape for
/// putting a phone back exactly as it was and the wrong one for everything
/// else: a spreadsheet cannot open it and no other tracker can import it. This
/// is the other shape — one row per set, the layout every tracker that imports
/// a history already reads — so years of training are never held hostage by
/// the format they were saved in.
///
/// One-way by design. Nothing reads these files back: a CSV has no ids, so a
/// restore from one could only invent a history, which is the thing
/// `backup_service.dart` exists to refuse.
///
/// Pure, so the shape of a row is tested without a database. The reads that
/// fill a [CsvSet] live in `data/backup/csv_export_service.dart`.
library;

import 'enums.dart';
import 'session_name.dart';
import 'units.dart';

/// One completed set, with everything about where it was done flattened onto
/// it.
///
/// Weights are in kilograms, as stored. The unit a file is written in is a
/// property of the file, applied once by [csvSetCells], not of the row.
class CsvSet {
  const CsvSet({
    required this.dayKey,
    required this.startedAt,
    required this.tzOffsetMinutes,
    required this.endedAt,
    required this.regime,
    required this.session,
    required this.isDeload,
    required this.exercise,
    required this.muscle,
    required this.equipment,
    required this.loadMode,
    required this.measureMode,
    required this.exerciseOrder,
    required this.setNumber,
    required this.setType,
    required this.weightKg,
    required this.addedWeightKg,
    required this.count,
    required this.partialReps,
    required this.restSeconds,
    required this.setNote,
    required this.exerciseNote,
    required this.sessionNote,
  });

  /// The local day the session was filed under, `yyyyMMdd`.
  final int dayKey;

  /// Milliseconds since the epoch, and the zone it was logged in. The time a
  /// spreadsheet shows is the time on the phone's clock that day, not the time
  /// in whatever zone the export happens to run in.
  final int startedAt;
  final int tzOffsetMinutes;
  final int? endedAt;

  final String regime;

  /// Null for a session logged outside the programme.
  final String? session;
  final bool isDeload;

  final String exercise;
  final MuscleGroup muscle;
  final Equipment equipment;
  final LoadMode loadMode;
  final MeasureMode measureMode;

  /// 1-based, in the order the exercises were done.
  final int exerciseOrder;

  /// 1-based, within the exercise.
  final int setNumber;
  final SetType setType;
  final double? weightKg;
  final double? addedWeightKg;

  /// Reps, or seconds held — [measureMode] says which, and [csvSetCells] puts
  /// each in its own column so neither is ever summed as the other.
  final int? count;
  final int? partialReps;
  final int? restSeconds;
  final String? setNote;
  final String? exerciseNote;
  final String? sessionNote;
}

/// The heading of the sets file, with the weight columns named in [unit].
List<String> csvSetHeader(WeightUnit unit) => [
      'Date',
      'Time',
      'Duration (min)',
      'Regime',
      'Session',
      'Deload',
      'Exercise',
      'Muscle',
      'Equipment',
      'Load',
      'Exercise order',
      'Set',
      'Set type',
      'Weight (${unit.label})',
      'Added weight (${unit.label})',
      'Reps',
      'Partial reps',
      'Seconds held',
      'Rest (s)',
      'Set note',
      'Exercise note',
      'Session note',
    ];

/// [set] as cells under [csvSetHeader], weights converted to [unit].
List<String> csvSetCells(CsvSet set, WeightUnit unit) {
  final local = DateTime.fromMillisecondsSinceEpoch(
    set.startedAt + set.tzOffsetMinutes * 60000,
    isUtc: true,
  );
  final end = set.endedAt;
  final hold = set.measureMode.isHold;
  return [
    csvDate(set.dayKey),
    '${_two(local.hour)}:${_two(local.minute)}',
    end == null ? '' : '${((end - set.startedAt) / 60000).round()}',
    set.regime,
    set.session ?? customSessionName,
    set.isDeload ? 'Yes' : 'No',
    set.exercise,
    set.muscle.label,
    set.equipment.label,
    csvLoadLabel(set.loadMode),
    '${set.exerciseOrder}',
    '${set.setNumber}',
    set.setType.label,
    csvWeight(set.weightKg, unit),
    csvWeight(set.addedWeightKg, unit),
    hold ? '' : '${set.count ?? ''}',
    hold || (set.partialReps ?? 0) == 0 ? '' : '${set.partialReps}',
    hold ? '${set.count ?? ''}' : '',
    '${set.restSeconds ?? ''}',
    set.setNote ?? '',
    set.exerciseNote ?? '',
    set.sessionNote ?? '',
  ];
}

/// The heading of the bodyweight file.
List<String> csvBodyweightHeader(WeightUnit unit) =>
    ['Date', 'Bodyweight (${unit.label})'];

List<String> csvBodyweightCells(int dayKey, double kg, WeightUnit unit) =>
    [csvDate(dayKey), csvWeight(kg, unit)];

/// `yyyyMMdd` as ISO `yyyy-MM-dd`, which every spreadsheet reads as a date
/// whatever its locale.
String csvDate(int dayKey) =>
    '${dayKey ~/ 10000}-${_two((dayKey ~/ 100) % 100)}-${_two(dayKey % 100)}';

/// What the weight column means for a movement.
String csvLoadLabel(LoadMode mode) => switch (mode) {
      LoadMode.total => 'Total',
      LoadMode.perSide => 'Per side',
      LoadMode.bodyweight => 'Bodyweight',
      LoadMode.bodyweightPlus => 'Bodyweight plus',
    };

/// A stored weight in [unit], to two decimals with trailing zeros dropped.
///
/// Not rounded to the unit's plate increment the way the screens round it. A
/// spreadsheet is where the exact number is wanted, and a kilogram history
/// read in pounds should convert back to the kilograms that were typed.
String csvWeight(double? kg, WeightUnit unit) {
  if (kg == null) return '';
  final v = (unit.fromKg(kg) * 100).round() / 100;
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// One line of RFC 4180 CSV, CRLF-terminated.
///
/// A cell is quoted when it holds a comma, a quote or a line break, and a
/// quote inside it is doubled — notes are free text and carry all three.
///
/// A cell that opens with `=`, `+`, `-` or `@` is prefixed with an apostrophe.
/// A spreadsheet reads such a cell as a formula, so a note reading
/// `-5 kg next time` opens as `#NAME?`, and a name opening with `=` could run
/// as one. No number this file writes is caught by it: none is ever negative.
String csvLine(List<String> cells) {
  final out = StringBuffer();
  for (var i = 0; i < cells.length; i++) {
    if (i > 0) out.write(',');
    var cell = cells[i];
    if (cell.isNotEmpty && '=+-@'.contains(cell[0])) {
      cell = "'$cell";
    }
    if (cell.contains(RegExp('[",\r\n]'))) {
      cell = '"${cell.replaceAll('"', '""')}"';
    }
    out.write(cell);
  }
  out.write('\r\n');
  return out.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');
