import 'package:deltoid/domain/csv_export.dart';
import 'package:deltoid/domain/enums.dart';
import 'package:deltoid/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

CsvSet _set({
  MeasureMode measureMode = MeasureMode.reps,
  int? count = 8,
  int? partialReps,
  double? weightKg = 100,
  String? session = 'Push 1',
  String? setNote,
  int tzOffsetMinutes = 330,
}) =>
    CsvSet(
      dayKey: 20260720,
      // 2026-07-20 01:30 UTC, which is 07:00 in Delhi.
      startedAt: DateTime.utc(2026, 7, 20, 1, 30).millisecondsSinceEpoch,
      tzOffsetMinutes: tzOffsetMinutes,
      endedAt: DateTime.utc(2026, 7, 20, 2, 32).millisecondsSinceEpoch,
      regime: 'PPL',
      session: session,
      isDeload: false,
      exercise: 'Bench press',
      muscle: MuscleGroup.chest,
      equipment: Equipment.barbell,
      loadMode: LoadMode.total,
      measureMode: measureMode,
      exerciseOrder: 1,
      setNumber: 2,
      setType: SetType.working,
      weightKg: weightKg,
      addedWeightKg: null,
      count: count,
      partialReps: partialReps,
      restSeconds: 120,
      setNote: setNote,
      exerciseNote: null,
      sessionNote: null,
    );

Map<String, String> _row(CsvSet set, [WeightUnit unit = WeightUnit.kg]) =>
    Map.fromIterables(csvSetHeader(unit), csvSetCells(set, unit));

void main() {
  test('every set row is as wide as the header', () {
    expect(csvSetCells(_set(), WeightUnit.kg),
        hasLength(csvSetHeader(WeightUnit.kg).length));
    expect(csvBodyweightCells(20260720, 72.4, WeightUnit.kg),
        hasLength(csvBodyweightHeader(WeightUnit.kg).length));
  });

  test('the date is the filed day and the time is the clock where it was logged',
      () {
    final row = _row(_set());
    expect(row['Date'], '2026-07-20');
    expect(row['Time'], '07:00');
    expect(row['Duration (min)'], '62');
  });

  test('a hold puts its seconds in their own column, never in reps', () {
    final row = _row(_set(measureMode: MeasureMode.hold, count: 45, partialReps: 3));
    expect(row['Reps'], '');
    expect(row['Partial reps'], '');
    expect(row['Seconds held'], '45');
  });

  test('partials sit beside reps rather than inside them', () {
    final row = _row(_set(partialReps: 3));
    expect(row['Reps'], '8');
    expect(row['Partial reps'], '3');
    expect(_row(_set(partialReps: 0))['Partial reps'], '');
  });

  test('weights are written in the unit the header names', () {
    expect(_row(_set(weightKg: 22.5))['Weight (kg)'], '22.5');
    expect(_row(_set(weightKg: 100), WeightUnit.lb)['Weight (lb)'], '220.46');
    expect(_row(_set(weightKg: null))['Weight (kg)'], '');
  });

  test('a session outside the programme is named as one', () {
    expect(_row(_set(session: null))['Session'], 'Custom session');
  });

  group('csvLine', () {
    test('quotes commas, quotes and line breaks', () {
      expect(csvLine(['a', 'b,c', 'say "hi"', 'two\nlines']),
          'a,"b,c","say ""hi""","two\nlines"\r\n');
    });

    test('stops a spreadsheet reading a note as a formula', () {
      expect(csvLine(['-5 kg next time', '=1+1', '@x', '+2']),
          "'-5 kg next time,'=1+1,'@x,'+2\r\n");
    });

    test('leaves plain cells alone', () {
      expect(csvLine(['2026-07-20', '22.5', '']), '2026-07-20,22.5,\r\n');
    });
  });
}
