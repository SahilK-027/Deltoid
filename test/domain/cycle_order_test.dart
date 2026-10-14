import 'package:deltoid/domain/cycle_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a cycle ahead is named for the first three, and Later after', () {
    expect(cycleAheadLabel(0), 'This cycle');
    expect(cycleAheadLabel(1), 'Next cycle');
    expect(cycleAheadLabel(2), 'Following cycle');
    expect(cycleAheadLabel(3), 'Later cycle');
    expect(cycleAheadLabel(7), 'Later cycle');
  });

  test('day names join with commas and a final and', () {
    expect(joinDayNames([]), '');
    expect(joinDayNames(['Leg 1']), 'Leg 1');
    expect(joinDayNames(['Leg 1', 'Leg 2']), 'Leg 1 and Leg 2');
    expect(
      joinDayNames(['Leg 1', 'Leg 2', 'Leg 3']),
      'Leg 1, Leg 2 and Leg 3',
    );
  });

  test('a rotation is captioned with the position it holds', () {
    expect(
      rotationCaption(['Leg 1', 'Leg 2'], 3),
      'Leg 1 and Leg 2 alternate in position 3',
    );
  });

  test('a day lists every movement, and says when it has none', () {
    expect(
      exerciseLine(['Back squat', 'Leg extension', 'Calf raise']),
      'Back squat · Leg extension · Calf raise',
    );
    expect(exerciseLine([]), 'No exercises');
  });

  test('a count of days agrees in number', () {
    expect(dayCount(1), '1 day');
    expect(dayCount(6), '6 days');
  });
}
