import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v7: time-ordered, generated offline, safe to use as a primary key that
/// syncs to Postgres without coordination.
String newId() => _uuid.v7();

int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// Local calendar day as `yyyyMMdd`. Used for heatmap grouping and bodyweight
/// entries, where "which day was it for me" matters more than the exact instant.
int dayKeyOf(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

DateTime dateFromDayKey(int key) =>
    DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);
