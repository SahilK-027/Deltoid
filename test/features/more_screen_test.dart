import 'package:deltoid/features/account/backup_mark.dart';
import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/domain/rest.dart';
import 'package:deltoid/domain/units.dart';
import 'package:deltoid/features/more/more_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltoid/domain/session_prefs.dart';
import 'package:deltoid/core/sync_providers.dart';
import 'package:deltoid/data/sync/sync_auth.dart';

/// More, pumped against a real database. The bodyweight log it used to hold
/// is tested with the Weigh-ins screen, in `weigh_ins_screen_test.dart`.
///
/// Harness rules are `regime_screen_test.dart`'s: never `pumpAndSettle` (a
/// watched query that has not answered yet renders a spinner, which never
/// settles), and the container outlives the tree so drift's stream-closing
/// timer lands outside the harness's pending-timer check.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// What the database says the unit is, which is the only thing a confirmed
  /// switch is allowed to have changed.
  Future<WeightUnit> savedUnit() async {
    final rows = await (db.select(db.appSettings)
      ..where((t) => t.key.equals(unitsKey))).get();
    return WeightUnitX.parse(rows.isEmpty ? null : rows.first.value);
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: screen,
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Scrolls until [text] is built, however far down the page it sits.
  ///
  /// A fixed drag is wrong twice over: the page is short enough that one drag
  /// can overshoot a row entirely, and a test that opens the same row twice
  /// would drag a second time from wherever the first left it.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
    }
  }

  /// Opens one of the Training card's rows — which is also what a person does,
  /// rest and the unit being a row each rather than a card each.
  Future<void> openRow(WidgetTester tester, String title) async {
    await scrollTo(tester, title);
    // Built is not the same as on screen: a `ListView` builds past the fold,
    // and a tap on a row below it lands on nothing.
    await tester.ensureVisible(find.text(title));
    await tester.pump();
    await tester.tap(find.text(title));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> openRestSheet(WidgetTester tester) =>
      openRow(tester, 'Rest time & alert');

  Future<void> openUnitSheet(WidgetTester tester) =>
      openRow(tester, 'Weight units');

  group('More', () {
    testWidgets('carries no bodyweight, logged or not', (tester) async {
      // The Bodyweight section moved to Home, as the Weigh-ins habit tile and
      // the screen behind it. Its figure and its link go with it.
      await TrainingRepository(db).logBodyweight(DateTime.now(), 76.5);
      await pump(tester, const MoreScreen());

      expect(tester.takeException(), isNull);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('76.5 kg'), findsNothing);
      expect(find.text('Not logged'), findsNothing);
      expect(find.text('History'), findsNothing);
    });

    testWidgets('the masthead carries the backup button the other tabs do', (
      tester,
    ) async {
      await pump(tester, const MoreScreen());
      // In the tree on every build. It draws nothing until an account is
      // signed in, which is `backup_mark_test`'s to show.
      expect(find.byType(BackupMark), findsOneWidget);
    });

    testWidgets('the file backup is named as a file on the phone', (
      tester,
    ) async {
      await pump(tester, const MoreScreen());
      await scrollTo(tester, 'Backup file on this phone');
      expect(find.text('Backup file on this phone'), findsOneWidget);
      expect(find.text('Automatic backup'), findsNothing);
      expect(
        find.text(
          'Not written yet. A file is written after each finished session.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('every section renders, top to bottom', (tester) async {
      await pump(tester, const MoreScreen());

      expect(tester.takeException(), isNull);
      // Bodyweight moved to the Weigh-ins screen behind its habit tile on
      // Home, so More opens on the account (RULES § 6).
      expect(find.text('Bodyweight'), findsNothing);
      expect(find.text('Account & backup'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Restore from a file'), findsOneWidget);

      // One way out, and the sheet asks which file.
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Backup file'), findsOneWidget);
      expect(find.text('Spreadsheet'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // A `ListView` builds what is on screen, so the tail of the page has to
      // be scrolled to before it exists at all.
      //
      // Rest and the unit are rows stating their answer, not sections
      // spelling out every option on the page.
      await scrollTo(tester, 'Rest time & alert');
      expect(find.text('Training'), findsOneWidget);
      expect(find.text('Rest time & alert'), findsOneWidget);
      expect(find.text('Weight units'), findsOneWidget);
      expect(find.text('Kilograms'), findsOneWidget);

      await scrollTo(tester, 'About app');
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('About app'), findsOneWidget);
      expect(find.text('Deltoid'), findsOneWidget);
    });

    testWidgets('rest ships at two minutes, and the steps are quarter-minutes',
        (tester) async {
      await pump(tester, const MoreScreen());
      await openRestSheet(tester);

      // Both numbers, before anything has been stored: the shipped default.
      expect(find.text('2:00'), findsNWidgets(2));

      // The + belonging to `Between sets` — the first stepper in the sheet.
      final plus = find.descendant(
        of: find.ancestor(
          of: find.text('Between sets'),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(Icons.add_rounded),
      );
      await tester.tap(plus.first);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('2:15'), findsOneWidget);
      final rows = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(restDefaultKey)))
          .get();
      expect(rows.single.value, '135');
    });

    testWidgets('the tone can be turned off; the buzz is not part of it',
        (tester) async {
      await pump(tester, const MoreScreen());
      await openRestSheet(tester);

      expect(
        find.text('Plays a tone when the rest reaches zero.'),
        findsOneWidget,
      );

      // The switch belonging to `Alert sound`, not "whatever switch is last".
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Alert sound'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ).first,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final rows = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(restSoundKey)))
          .get();
      expect(rows.single.value, 'off');
      final prefs = container.read(restPrefsProvider).valueOrNull;
      expect(
        prefs?.sound,
        isFalse,
        reason: 'the log screen reads this at the moment a rest ends',
      );
      // And the switch is about the tone alone: the two durations are
      // untouched, and the between-exercises one still reads through the
      // provider that is its only reader.
      expect(prefs?.defaultSeconds, 120);
      expect(prefs?.betweenExercises, 120);

      await setRestBetweenExercisesSeconds(db, 210);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final moved = container.read(restPrefsProvider).valueOrNull;
      expect(moved?.betweenExercises, 210);
      expect(moved?.defaultSeconds, 120);
    });

    testWidgets('the three session switches store what they are set to', (
      tester,
    ) async {
      await pump(tester, const MoreScreen());

      // Shipped defaults: on, with nothing written to say so.
      expect(
        container.read(sessionPrefsProvider).valueOrNull?.notification,
        isTrue,
      );

      await openRow(tester, 'Session notification');
      // The row is a switch, not a chevron — `openRow` taps the title, which
      // does nothing. Tap the switch itself.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Session notification'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ).first,
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final rows = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(sessionNotificationKey)))
          .get();
      expect(rows.single.value, 'off');
      expect(
        container.read(sessionPrefsProvider).valueOrNull?.notification,
        isFalse,
        reason: 'the log screen reads this before starting the service',
      );
      // And it is its own switch: the screen is still held awake.
      expect(
        container.read(sessionPrefsProvider).valueOrNull?.keepScreenOn,
        isTrue,
      );
    });

    testWidgets('vibration is its own switch, not half of the tone', (
      tester,
    ) async {
      await pump(tester, const MoreScreen());
      await openRestSheet(tester);

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Vibration'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        ).first,
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final prefs = container.read(restPrefsProvider).valueOrNull;
      expect(prefs?.vibrate, isFalse);
      // The tone is untouched — the two are read separately at the moment a
      // rest ends, and turning one off must not silence the other.
      expect(prefs?.sound, isTrue);
    });

    testWidgets('the unit asks before it restates every number in the app', (
      tester,
    ) async {
      await pump(tester, const MoreScreen());
      await openUnitSheet(tester);

      await tester.tap(find.text('Pounds'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('Show weights in pounds?'), findsOneWidget);

      await tester.tap(find.text('Go back').last);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // A radio is one tap, and this one is on the way past to a backup.
      expect(await savedUnit(), WeightUnit.kg);

      await openUnitSheet(tester);
      await tester.tap(find.text('Pounds'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.tap(find.text('Switch to pounds').last);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(await savedUnit(), WeightUnit.lb);
    });
  });

  group('the profile header', () {
    /// More with [account] signed in, on a container of its own: the shared
    /// one has no auth, which is the signed-out build every other test uses.
    Future<void> pumpSignedIn(WidgetTester tester, SyncAccount account) async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncAuthProvider.overrideWithValue(_FakeAuth(account)),
        ],
      );
      await pump(tester, const MoreScreen());
    }

    testWidgets('is absent without an account', (tester) async {
      await pump(tester, const MoreScreen());
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Backed up since'), findsNothing);
      expect(find.text('Account'), findsNothing);
      // The masthead is unchanged either way.
      expect(find.text('ON THIS DEVICE'), findsOneWidget);
    });

    testWidgets('names the account and the day it was created', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        SyncAccount(
          id: 'u1',
          email: 'ada@example.com',
          name: 'Ada Lovelace',
          createdAt: DateTime(2025, 5, 31),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('AL'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Backed up since 31 May 2025'), findsOneWidget);
      expect(find.text('ON THIS DEVICE'), findsOneWidget);
      // The row names the thing, and the address is its detail.
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
    });

    testWidgets('falls back to the email when the sign-in gives no name', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        SyncAccount(
          id: 'u1',
          email: 'lifter@example.com',
          createdAt: DateTime(2025, 5, 31),
        ),
      );
      expect(find.text('L'), findsOneWidget);
      // In the header and under the Account row.
      expect(find.text('lifter@example.com'), findsNWidgets(2));
    });

    testWidgets('the Account row opens the sign-out sheet', (tester) async {
      await pumpSignedIn(
        tester,
        const SyncAccount(id: 'u1', email: 'ada@example.com', name: 'Ada'),
      );
      await tester.tap(find.text('Account'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign out and delete data'), findsOneWidget);
    });
  });

  testWidgets('the About card says what the app is for', (tester) async {
    await pump(tester, const MoreScreen());
    const about =
        'A training tracker that puts you in full control of your programs. '
        'Design your own routines, log every set and rep, and track your '
        'strength over time with clear, organised records.';
    await scrollTo(tester, about);
    expect(find.text(about), findsOneWidget);
  });
}

class _FakeAuth implements SyncAuth {
  _FakeAuth(this._current);

  SyncAccount? _current;

  @override
  SyncAccount? get current => _current;

  @override
  Stream<SyncAccount?> get changes => Stream.value(_current);

  @override
  Future<SyncAccount> signInWithGoogle() async => _current!;

  @override
  Future<void> signOut() async => _current = null;
}
