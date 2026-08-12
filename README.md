# Deltoid

Deltoid is a personal, offline-first training log built with Flutter and SQLite.
It runs on Android and keeps everything on the device.

Offline-first is finished and is the architecture, not a stage: every screen
reads local disk and nothing waits on a server. **Online sync across your own
devices is in scope and not yet built** — the schema has carried the columns for
it from the start (`updatedAt`, `deletedAt`, `deviceId`, `dirty`), and the app
makes no network call until it lands.

**No programme is baked in.** A fresh install ships with an exercise catalog and
nothing else. You either build your own split or start from one of the two
templates (PPL 6-day and Upper/Lower) and edit it into shape. A template writes
ordinary sessions and slots, so nothing about it stays special once it has been
applied.

**It is a single-user personal tool rather than a product**, so scope discipline
is a requirement. [RULES.md § Scope](RULES.md#6-scope) lists what stays out.

---

## The docs

There are four documentation files, and each one has a single job. Nothing
belongs in two of them.

| File                     | Holds                                                                                                 |
| ------------------------ | ----------------------------------------------------------------------------------------------------- |
| **README.md** (this)     | What it is, how to set it up, how to run it, what the files are, how it is built                      |
| **[RULES.md](RULES.md)** | Every rule the app is held to — data invariants, migration protocol, code traps, scope                |
| **[THEME.md](THEME.md)** | The app as it stands: every screen, the design language it is drawn in, and the decisions behind both |
| **[TODO.md](TODO.md)**   | One list — what is done, what is left                                                                 |
| [CLAUDE.md](CLAUDE.md)   | Orientation for AI sessions. Points at the four above; holds nothing of its own                       |

---

## Setup

You need the Flutter SDK (Dart `^3.11.5`) and a working Android toolchain.
Point the shell at the Android SDK first:

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH
```

Then fetch the packages and generate the database code:

```bash
flutter pub get
dart run build_runner build
```

`build_runner` writes the drift database code in `lib/data/db/database.g.dart`,
and it has to be run again after **any** edit to `lib/data/db/tables.dart`.

## Running it

Start the app on a connected device or emulator:

```bash
flutter run
```

Check it before calling any change done. Both commands must come back clean:

```bash
flutter analyze && flutter test
```

Build a release APK:

```bash
flutter build apk --release
```

### Filling it with data

`tool/seed_years.dart` writes a backup file holding years of plausible history,
so the app can be tested at a size no fresh install reaches. The history it
generates progresses over time, keeps each session's numbers separate and
includes deload weeks. Restore the file through Settings → Backup.

```bash
dart run tool/seed_years.dart --years 5 --out seed.json
```

### Environment notes (this Mac)

- **Android is the only target that can be built here.** Xcode is not
  installed, only CommandLineTools, so iOS cannot be built or run on this
  machine. Nothing iOS-specific is known to be broken, but nothing has been
  verified either.
- The emulator crashes when it is given a window on macOS 26, so run it
  headless:

  ```bash
  emulator -avd Pixel_3a_API_31_arm64-v8a -no-window -no-snapshot -gpu swiftshader_indirect
  ```

- Take a screenshot with `adb exec-out screencap -p > out.png`.
- Inspect the database on the device with the command below. Quote the whole
  thing, or the shell mangles it:

  ```bash
  adb shell "run-as com.deltoid.deltoid sqlite3 /data/data/com.deltoid.deltoid/app_flutter/deltoid.sqlite 'select count(*) from workouts'"
  ```

- `file_picker` resolves to version 3.0.4, which is missing a namespace and
  breaks the Gradle build. The app uses `file_selector` instead, and it should
  not be swapped back.

---

## How it is built

The app is built with Flutter, Riverpod and drift. Everything lives on local
disk, and there is no network call anywhere in it today. State is a layer of
Riverpod providers over drift streams, so a write in one place re-renders
whatever was watching that table.

That stays true after sync lands: local disk is what the screens read, and a
sync is a background reconciliation of the same tables rather than a thing any
screen waits on. Reads never learn about the network.

There are four layers, and the dependencies point one way only — `features`
depends on `data`, which depends on `domain` — while `core` is available to all
three.

- **`domain/`** holds pure Dart with no Flutter, no database and no I/O. Every
  rule that does arithmetic lives here and is unit-tested without a database:
  prefill and deload, cycle timing, estimated 1RM and effective load, weekly
  volume, consistency, plate maths and unit conversion.
- **`data/`** holds the drift schema, the two repositories over it, the starter
  catalog and the whole-database JSON backup. Repositories return plain records
  and streams, so no widget ever touches a table directly.
- **`features/`** holds one folder per tab, each with its own screens, providers
  and widgets.
- **`core/`** holds the theme tokens, the shared providers, the component
  primitives every screen composes from, and a few cross-cutting pieces such as
  id generation, the end-of-rest alert, the per-second ticker and scroll
  behaviour.

Weights are always stored in kilograms, and the display unit converts them at
the edge. The schema is at version 7 and the upgrade path is real, so read
[RULES.md § Schema and migrations](RULES.md#3-schema-and-migrations) before
touching a column.

### Layout

```
lib/
  main.dart · app.dart          bootstrap, theme mode, the shell

  domain/                       pure Dart, heavily unit-tested
    prefill.dart                  resolvePrefill + applyDeload   ← the core rule
    cycle_engine.dart             CycleStatus, planNextCycle     ← cycles, deload
    metrics.dart                  e1RM, effective load, beatsPrevious, stalls
    muscle_volume.dart            weekly sets folded into six regions
    consistency.dart              sessions-per-week, streaks, honest rates
    session_diff.dart             today's improvisation vs the template
    plates.dart                   what to load on the bar
    units.dart                    kg / lb, rounding, signed deltas
    enums.dart                    LoadMode, MeasureMode, SetType, SkipReason, …

  data/
    db/                         tables.dart (schema), database.dart (migrations),
                                watch.dart (the only safe way to watch a query)
    repositories/               training_repository  logging, cycles, history,
                                                     progress, volume
                                regime_repository    programmes, sessions, catalog
    seed/                       starter exercise catalog + optional templates
    backup/                     whole-DB JSON export / restore, Downloads writer

  core/
    theme/                      tokens.dart, theme.dart — the language in code
    widgets/                    primitives.dart (cards, rows, chips, sheets),
                                trend_chart.dart (the one chart), calendar.dart
                                (the one day picker), reorder_sheet.dart,
                                ticking.dart (every per-second rebuild)
    providers.dart · ids.dart · rest_alert.dart · scroll.dart

  features/
    today/                      Workouts: next session, heatmap, volume bars
    log/                        the logging PageView, keypad, hold pad, summary
    history/                    session feed, per-exercise history, trend chart
    regime/                     regime library, programme editor, exercise catalog
    settings/                   settings, bodyweight log, backup
    shell/                      the four-tab scaffold

test/                           domain · data · features · tool
tool/seed_years.dart            generates years of plausible history
assets/audio/rest_done.mp3      the end-of-rest tone
```

### The four tabs

The app has four tabs: Workouts, Regime, History and Settings.
[THEME.md](THEME.md) describes the system every one of them is drawn with. In
short:

- **Workouts** is the landing screen. It shows how long it has been since you
  trained, the one session to start next, the consistency grid and this week's
  sets per muscle. The code still calls this feature `today`.
- **Regime** holds the regime library and the programme editor, along with the
  exercise catalog and the deload configuration.
- **History** holds the session feed and the per-exercise index. Every row opens
  what was actually logged, and an exercise opens with its trend chart at the
  top.
- **Settings** holds units, theme, the bodyweight log and backup.
