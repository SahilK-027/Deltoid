# Deltoid

A personal, offline-first training log. Flutter, Riverpod and drift over SQLite,
Android only, one user.

Everything lives on the device and no screen waits on a server — the app makes
no network call at all today. Sync across your own devices is designed and in
scope but not built; the schema has carried its columns from the start
(`updatedAt`, `deletedAt`, `deviceId`, `dirty`).

**No programme is baked in.** A fresh install ships with an exercise catalog and
nothing else. Build a split or start from a template (PPL 6-day, Upper/Lower) and
edit it — a template writes ordinary rows, and nothing about it stays special.

The one idea the app exists for: **progression is scoped to the session, not the
exercise.** Push 1 and Push 2 keep separate histories of the same movement, so
what the fields prefill with is what you did on _this_ day last time.

## Quick start

Needs the Flutter SDK (Dart `^3.11.5`) and an Android toolchain.

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH
flutter pub get
dart run build_runner build
git config core.hooksPath hooks
flutter run
```

`build_runner` generates `lib/data/db/database.g.dart` and must be re-run after
any edit to `lib/data/db/tables.dart`. `core.hooksPath` is once per clone —
`.git/hooks` is not version-controlled — and points git at [`hooks/`](hooks/),
whose `pre-push` runs `flutter analyze && flutter test` and refuses the push if
either fails. `git push --no-verify` is the only way past it.

## Commands

|                                   |                                                          |
| --------------------------------- | -------------------------------------------------------- |
| `flutter run`                     | run on a connected device or emulator                    |
| `flutter analyze && flutter test` | the gate — both must be clean before anything is done    |
| `dart run build_runner build`     | regenerate after a schema change                         |
| `flutter build apk --release`     | release build                                            |
| `flutter test tool/test/`         | tests for the seed generator, which `flutter test` skips |
| `supabase db push`                | apply `supabase/migrations` to the linked project        |
| `supabase test db`                | the RLS suite, against a local stack (needs Docker)      |

## Layout

```
lib/
  main.dart · app.dart      bootstrap, theme mode, the shell

  domain/                   pure Dart — no Flutter, no database, no I/O
    prefill.dart              resolvePrefill + applyDeload    ← the core rule
    cycle_engine.dart         cycle status, deload scheduling
    metrics.dart              e1RM, effective load, beatsPrevious, stalls
    muscle_volume.dart        weekly sets folded into six regions
    volume_history.dart       weeks, spans and rates
    chart_buckets.dart        the fold every chart draws through
    consistency.dart          sessions per week, streaks, honest rates
    session_diff.dart         today's improvisation vs the template
    plates.dart · units.dart · set_format.dart · enums.dart

  data/
    db/                     tables.dart (schema), database.dart,
                            watch.dart (the only safe way to watch a query)
    repositories/           training_repository  logging, cycles, history,
                                                 progress, volume
                            regime_repository    programmes, sessions, catalog
    seed/                   starter catalog + optional templates
    backup/                 whole-database JSON export / restore, Downloads writer

  core/
    theme/                  tokens.dart, theme.dart — the language in code
    widgets/                primitives.dart (cards, rows, chips, sheets),
                            trend_chart.dart (the one chart), calendar.dart
                            (the one day picker), reorder_sheet.dart,
                            ticking.dart (every per-second rebuild)
    providers.dart · ids.dart · rest_alert.dart · failure.dart
    workout_notifications.dart

  features/                 workouts · log · history · regime · settings · shell

test/                       domain · data · features · core
test/integrity/             the oracle and the fuzz harness
tool/seed_years.dart        generates years of plausible history
tool/test/                  its tests, outside test/ so they never run by default
assets/audio/rest_done.mp3  the end-of-rest tone
```

Four layers, dependencies one way only: `features` → `data` → `domain`, with
`core` available to all three. Repositories return plain records and streams, so
no widget touches a table. Weights are always stored in kilograms and converted
at the edge.

Riverpod providers sit over drift streams, so a write re-renders whatever was
watching that table. That stays true after sync: screens read local disk, and a
sync is background reconciliation of the same tables.

The four tabs are **Workouts** (next session, consistency grid, weekly volume),
**Regime** (programmes, editor, exercise catalog), **History** (session feed,
per-exercise history and trend) and **Settings** (units, theme, bodyweight,
backup).

## Testing

732 tests, plus nine pgTAP tests behind `supabase test db`. Beyond the usual
unit and widget tests, `test/integrity/` holds two pieces worth knowing about:

- `test/integrity/invariant_oracle.dart` — sixteen structural rules re-derived in
  SQL, callable after any write, each with a test that has watched it fire.
- `test/integrity/model_fuzz_test.dart` — seeded random operations against the
  real database and a deliberately dumb in-memory model, checking the oracle
  after every one. A failure prints the seed and the shortest sequence that still
  reproduces it.

The committed fuzz run is small enough to live in the suite. Environment
variables turn it into a soak:

```bash
FUZZ_REPORT=1 FUZZ_SEEDS=500 FUZZ_OPS=2000 FUZZ_BACKUP_EVERY=10 flutter test test/integrity/model_fuzz_test.dart
```

`FUZZ_SEEDS` × `FUZZ_OPS` is the size of the run, `FUZZ_REPORT=1` prints how many
operations each seed applied, and `FUZZ_BACKUP_EVERY=N` thins the one operation
whose cost grows with the history behind it — it rewrites every row, and
thinning it is what makes a run of millions of operations finish in an
afternoon. Replay a printed failure exactly:

```bash
FUZZ_SEED=17 FUZZ_SEEDS=1 FUZZ_OPS=4000 flutter test test/integrity/model_fuzz_test.dart
```

To test at a size no fresh install reaches, generate a history and restore it
through Settings → Backup. What it writes progresses over time, keeps each
session's numbers separate and includes deload weeks:

```bash
dart run tool/seed_years.dart --years 5 --out seed.json
```

## Schema changes

`schemaVersion` is **2** and the migration ladder is running. A schema change is
an edit to `tables.dart`, a regenerate, a default in `data/db/table_spec.dart`,
and an idempotent rung in `upgradeSchema` — see
[RULES § 3](RULES.md#3-schema-and-migrations) before touching a column.

A column on a syncable table is also a column on the server, in
`supabase/migrations/`. `test/data/server_schema_test.dart` compares the two and
fails if they drift apart, which is the quietest failure sync has.

## The server

Cloud backup's half that is not Dart lives in `supabase/`:

```
supabase/
  config.toml               the local stack's shape, committed
  migrations/*.sql          nine tables, RLS, indexes, the server clock
  tests/database/*.sql      pgTAP — proves the policies, which nothing else can
```

The RLS policies are the whole of the security ([SYNC § 3](SYNC.md#3-identity)),
so they live in the repo where they have a diff and a review rather than only in
a browser. Running them needs Docker and a local stack. This Mac has 3.8 GiB
given to Docker, which the full stack does not fit in, so start only what the
tests need:

```bash
supabase start -x realtime,storage-api,imgproxy,studio,postgres-meta,mailpit,edge-runtime,logflare,vector,supavisor
```

Then `supabase test db`, and `supabase stop` when finished.

## The docs

Each has one job, and nothing belongs in two of them.

| File                     | Holds                                                                              |
| ------------------------ | ---------------------------------------------------------------------------------- |
| **README.md** (this)     | What it is, how to set it up, how to run it, where things live                     |
| **[RULES.md](RULES.md)** | Every rule the app is held to — data invariants, migrations, code traps, scope     |
| **[THEME.md](THEME.md)** | The app screen by screen, and the design language it is drawn in                   |
| **[SYNC.md](SYNC.md)**   | The sync design: what syncs, how a conflict resolves, what it may never do         |
| **[TODO.md](TODO.md)**   | One list — what is done, what is left. Status lives here and nowhere else          |
| [CLAUDE.md](CLAUDE.md)   | Orientation for AI sessions; points at the five above and holds nothing of its own |

It is a single-user personal tool rather than a product, so scope discipline is a
requirement — [RULES § 6](RULES.md#6-scope) lists what stays out, and the answer
to "should this be added" is usually no.

## Environment notes

- **Android is the only target buildable here.** Only CommandLineTools is
  installed, no Xcode. Nothing iOS-specific is known broken; nothing is verified.
- The emulator crashes with a window on macOS 26, so run it headless:
  `emulator -avd Pixel_3a_API_31_arm64-v8a -no-window -no-snapshot -gpu swiftshader_indirect`
- Screenshot: `adb exec-out screencap -p > out.png`
- Read the on-device database (quote the whole thing or the shell mangles it):
  `adb shell "run-as com.deltoid.deltoid sqlite3 /data/data/com.deltoid.deltoid/app_flutter/deltoid.sqlite 'select count(*) from workouts'"`
- `file_picker` resolves to 3.0.4, which is missing a namespace and breaks the
  Gradle build. The app uses `file_selector`; do not swap it back.
