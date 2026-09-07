import 'dart:convert';

import 'package:drift/drift.dart';

class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter<List<String>, String> {
  const StringListConverter();

  /// Never throws.
  ///
  /// A converter runs on the way *out* of the database, so a value it cannot
  /// read does not fail the row — it fails the read, and takes every other row
  /// in the result set with it. One malformed `form_video_urls` would blank the
  /// catalog, the exercise screen and the log at once, over a list of links.
  ///
  /// Refusing a value that parses to something other than a list is not enough:
  /// the value may not be JSON at all, which is what a hand-edited backup or a
  /// column written by anything but this app looks like. No links is the honest
  /// reading of an unreadable list, and it is recoverable — the field can
  /// simply be filled in again.
  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(fromDb);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList(growable: false);
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
