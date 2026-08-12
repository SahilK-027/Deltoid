import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v7: time-ordered, generated offline, safe to use as a primary key that
/// syncs to Postgres without coordination.
String newId() => _uuid.v7();

int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

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

/// Local calendar day as `yyyyMMdd`. Used for heatmap grouping and bodyweight
/// entries, where "which day was it for me" matters more than the exact instant.
int dayKeyOf(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

DateTime dateFromDayKey(int key) =>
    DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);
