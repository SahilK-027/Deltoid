import 'package:deltoid/data/db/converters.dart';
import 'package:deltoid/data/db/renumber.dart';
import 'package:flutter_test/flutter_test.dart';

/// DEBT § 1: two rules that were stated in a doc comment and checked nowhere.
///
/// Both are small, and that is the point — a rule small enough to be obvious is
/// a rule nobody writes a test for, and `nextPosition` is called by every append
/// path in the app while `fromSql` runs on the way *out* of the database, where
/// a throw does not fail a row but fails the whole read.
void main() {
  group('nextPosition', () {
    test('is one past the highest, not the number of rows', () {
      // The distinction the whole reorder path rests on: deletes are tombstones
      // and nothing renumbers behind them, so after a removal the count and the
      // next free position are different numbers.
      expect(nextPosition([0, 1, 2]), 3);
      expect(nextPosition([0, 2, 5]), 6);
      expect(nextPosition([7]), 8);
    });

    test('is never negative, whatever it is handed', () {
      // The claim the comment makes. An empty scope is a parent whose rows have
      // all been deleted, and a negative index is refused by the schema — so
      // without the floor this is the append that cannot be written.
      expect(nextPosition(const []), 0);
      expect(nextPosition([-3, -1]), 0);
      expect(nextPosition([-1]), 0);
    });

    test('does not care what order it is given', () {
      expect(nextPosition([5, 0, 3]), nextPosition([0, 3, 5]));
    });
  });

  group('StringListConverter never throws', () {
    const converter = StringListConverter();

    test('a list round-trips exactly', () {
      const links = ['https://a.example/v', 'https://b.example/w'];
      expect(converter.fromSql(converter.toSql(links)), links);
    });

    test('an empty column is an empty list rather than a parse', () {
      expect(converter.fromSql(''), isEmpty);
      expect(converter.toSql(const []), '[]');
    });

    test('a value that is not JSON reads as no links', () {
      // A hand-edited backup, or a column written by anything but this app.
      // One malformed `form_video_urls` used to take the catalog, the exercise
      // screen and the log down with it, because a converter that throws fails
      // the whole result set rather than the row.
      expect(converter.fromSql('not json at all'), isEmpty);
      expect(converter.fromSql('{'), isEmpty);
      expect(converter.fromSql('["unterminated'), isEmpty);
    });

    test('JSON that is not a list reads as no links', () {
      expect(converter.fromSql('{"a": 1}'), isEmpty);
      expect(converter.fromSql('42'), isEmpty);
      expect(converter.fromSql('"a string"'), isEmpty);
      expect(converter.fromSql('null'), isEmpty);
    });

    test('non-string entries are read as text rather than refused', () {
      // Partial data beats no data: the readable links survive.
      expect(converter.fromSql('["https://a.example/v", 7, null]'),
          ['https://a.example/v', '7', 'null']);
    });
  });
}
