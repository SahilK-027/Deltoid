/// The words the regime editor prints about the order of a cycle.
///
/// Here rather than beside the widgets that show them, because a string built
/// where it is first needed is copied to the next screen and the copies drift
/// ([RULES.md § 4](RULES.md#4-code)).
library;

/// When a cycle comes round, counted from the open one: `This cycle`,
/// `Next cycle`, `Following cycle`.
///
/// Three names and no fourth. The editor draws at most three cycles, and a
/// rotation of four or more prints `Later cycle` for every member past the
/// third rather than inventing an ordinal nobody says aloud.
String cycleAheadLabel(int ahead) => switch (ahead) {
      0 => 'This cycle',
      1 => 'Next cycle',
      2 => 'Following cycle',
      _ => 'Later cycle',
    };

/// `Leg 1 and Leg 2`, or `Leg 1, Leg 2 and Leg 3`.
String joinDayNames(List<String> names) => switch (names.length) {
      0 => '',
      1 => names.single,
      _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
    };

/// `Leg 1 and Leg 2 alternate in position 3`.
///
/// [position] counts from one, as the list beside it does.
String rotationCaption(List<String> names, int position) =>
    '${joinDayNames(names)} alternate in position $position';

/// The movements of a day on one line: `Back squat · Leg extension`.
///
/// Every name, in order, with no count of the ones that do not fit. The row
/// ellipsizes, and `+2 more` beside an ellipsis reads as two different ways of
/// saying the line was cut.
String exerciseLine(List<String> names) =>
    names.isEmpty ? 'No exercises' : names.join(' · ');

/// `1 day`, `6 days`.
String dayCount(int days) => '$days day${days == 1 ? '' : 's'}';
