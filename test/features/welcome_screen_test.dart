import 'dart:async';

import 'package:deltoid/core/providers.dart';
import 'package:deltoid/core/sync_providers.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/repairs.dart';
import 'package:deltoid/data/sync/sync_auth.dart';
import 'package:deltoid/features/welcome/curl_illustration.dart';
import 'package:deltoid/features/welcome/welcome_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one screen the whole app is gated on, and the change behind it.
///
/// Moving the seed off the launch path is the riskiest edit in this phase: get
/// it wrong and a phone that signs in ends up carrying two catalogs, `Bench
/// Press` twice under different ids, and a history split across both — which
/// breaks the one rule the app exists for, because per-session progression is
/// keyed to an exercise id ([SYNC.md § 10](SYNC.md#10-adoption)).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> catalogSize() async =>
      (await db.select(db.exercises).get()).length;

  /// A few frames, rather than `pumpAndSettle`.
  ///
  /// The screen does settle now that the drawing holds one fixed hue, so this
  /// is no longer forced — it stays because these tests care about the screen
  /// being *reachable* part-way through its 620ms entrance, not about the frame
  /// after it finishes.
  Future<void> beats(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pump(WidgetTester tester, {SyncAuth? auth}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncAuthProvider.overrideWithValue(auth ?? _FakeAuth()),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  group('the seed waits for the answer', () {
    test('a launch before the welcome is answered seeds nothing', () async {
      await repairDatabase(db, seed: await welcomeAnswered(db));
      expect(await catalogSize(), 0,
          reason: 'seeding before the answer is what puts two catalogs on a '
              'phone that then signs in');
    });

    test('and the repairs still run over the empty database', () async {
      // The rest of the list is not conditional. It has to survive a database
      // with no catalog in it, because that is now a state a launch can be in.
      await expectLater(repairDatabase(db, seed: false), completes);
    });

    test('answering seeds before it records the answer', () async {
      await answerWelcome(db, WelcomeAnswer.local);
      expect(await catalogSize(), greaterThan(0));

      final row = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(welcomeKey)))
          .getSingle();
      expect(row.value, 'local');
    });

    test('a second answer does not seed a second catalog', () async {
      await answerWelcome(db, WelcomeAnswer.local);
      final first = await catalogSize();
      await answerWelcome(db, WelcomeAnswer.account);
      expect(await catalogSize(), first,
          reason: 'the seeder declines a table that is not empty, and this is '
              'the guard that keeps that true when the answer changes');
    });

    test('a launch after the answer seeds as it always did', () async {
      await db.into(db.appSettings).insert(
            AppSettingsCompanion.insert(key: welcomeKey, value: 'local'),
          );
      await repairDatabase(db, seed: await welcomeAnswered(db));
      expect(await catalogSize(), greaterThan(0));
    });
  });

  group('the screen', () {
    testWidgets('asks one question, and offers both answers', (tester) async {
      await pump(tester);

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue on this phone'), findsOneWidget);
      // One screen, never two.
      expect(find.byType(PageView), findsNothing);
      // The wordmark, and the one drawing the app has — see THEME →
      // Illustration, which allows exactly one, on this screen.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CurlIllustration), findsOneWidget);
    });

    testWidgets('declining is a real answer and seeds the catalog',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Continue on this phone'));
      await beats(tester);

      expect(await welcomeAnswered(db), isTrue);
      expect(await catalogSize(), greaterThan(0),
          reason: 'the shell renders over a database that is finished, not one '
              'filling in behind it');
    });

    testWidgets('signing in records the answer', (tester) async {
      final auth = _FakeAuth();
      await pump(tester, auth: auth);

      await tester.tap(find.text('Continue with Google'));
      await beats(tester);

      expect(auth.signInCalls, 1);
      expect(await welcomeAnswered(db), isTrue);
      expect(await catalogSize(), greaterThan(0));
    });

    testWidgets('backing out of Google leaves the question standing',
        (tester) async {
      final auth = _FakeAuth(cancel: true);
      await pump(tester, auth: auth);

      await tester.tap(find.text('Continue with Google'));
      await beats(tester);

      expect(await welcomeAnswered(db), isFalse,
          reason: 'closing Google\'s sheet answers Google, not this screen');
      expect(await catalogSize(), 0);
      // And the button is live again rather than stuck saying "Signing in".
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('a sign-in that fails says so and asks again', (tester) async {
      final auth = _FakeAuth(fail: 'No signal.');
      await pump(tester, auth: auth);

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No signal.'), findsOneWidget);
      expect(await welcomeAnswered(db), isFalse);
    });

    testWidgets('one tap opens one sheet', (tester) async {
      final auth = _FakeAuth(hold: true);
      await pump(tester, auth: auth);

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      // The label has changed, so this taps the disabled button underneath it.
      await tester.tap(find.text('Signing in'));
      await tester.pump();

      expect(auth.signInCalls, 1);

      auth.release();
      await beats(tester);
    });
  });
}

class _FakeAuth implements SyncAuth {
  _FakeAuth({this.cancel = false, this.fail, this.hold = false});

  final bool cancel;
  final String? fail;

  /// Holds the sign-in open, so a test can stand in the gap a network makes.
  final bool hold;
  final _held = Completer<void>();

  int signInCalls = 0;
  SyncAccount? _current;

  void release() => _held.complete();

  @override
  SyncAccount? get current => _current;

  @override
  Stream<SyncAccount?> get changes => Stream.value(_current);

  @override
  Future<SyncAccount> signInWithGoogle() async {
    signInCalls++;
    if (hold) await _held.future;
    if (cancel) throw const SyncAuthCancelled();
    if (fail != null) throw SyncAuthFailure(fail!);
    return _current = const SyncAccount(id: 'u1', email: 'lifter@example.com');
  }

  @override
  Future<void> signOut() async => _current = null;
}
