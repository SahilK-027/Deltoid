# Deltoid — known weaknesses

What is wrong with this codebase, why it is wrong, and how to tell when it has
been fixed. **Not status** — status is [TODO.md](TODO.md) and nowhere else.
This is the list of things that are *true right now* and would be found by
someone reviewing the app critically, written down so they can be argued with
rather than rediscovered.

Each entry says what to change and how to know it worked. An entry leaves this
file when the check it names passes, not when it feels handled.

## One entry left, and it cannot be closed at a keyboard

**Nothing in [SYNC.md](SYNC.md) should be written until this file is empty.**
Everything that could be closed by writing code has been. What is left is § 6:
a third of the app has never been used in a gym, and sync is the point after
which deleting a feature stops being free — there will be rows of it on a server
and a migration to write. Everything that should be deleted should be deleted
first.

---

## 6. A third of the app has never been used in a gym

From TODO.md, and repeated here because it is the biggest *product* risk and the
easiest to leave sitting: **twelve** features are built, analyzer-clean and
tested but have never been driven on real hardware in a real session. Among them
the hold pad, the rest tone, the haptics, the wakelock, audio ducking, the
ongoing-session notification and the scheduled rest alarm.

Tests do not tell you the hold pad is awkward with chalk on your hands, that the
rest tone is inaudible over gym music, or that the notification's countdown is
wrong on a locked screen. For an app whose primary screen is operated one-handed,
standing at a bar, mid-set, this is the difference between working and shipped.

**What to do.** One month of actual training with a notebook. Every friction
gets written down; at the end, delete rather than fix wherever possible — the
scope rules are the app's best feature and this is the data that feeds them.

**Done when**: the "Not yet driven on the device" section of TODO.md is empty,
by use or by deletion.

---

## What closed, and what checks it now

Kept as a record rather than as work. Each line is a weakness this file used to
describe and the mechanism that replaced it — because an entry deleted with no
check behind it is an entry that comes back.

| Was | Now checked by |
| --- | --- |
| **§1** Invariants lived in prose; a comment cannot fail a build | The register in [RULES § 7](RULES.md#7-working-on-it), and every row below it. `nextPosition` and the JSON converter — the two rules small enough that nobody had tested them — are in `test/data/db_helpers_test.dart` |
| **§2** No gate: a broken test could be pushed | `hooks/pre-push`, plus four lints including `unawaited_futures` |
| **§3** Drift's row mapping on queries that grow with the log | Converted, each behind a field-by-field parity test against the drift query it replaced — `test/data/query_conversion_test.dart`. The queries that stayed say why their row count does not grow, and the paged ones assert their bound |
| **§4** `volumeHistoryProvider` re-queried forever after one visit | `test/features/volume_provider_lifetime_test.dart` |
| **§5** Painters clamping to bounds they computed | RULES § Interface, enforced over `lib/` by `test/core/clamp_bounds_test.dart` |
| **§7** Comments stating facts about other code go stale silently | Folded into the RULES register: a fact about other code becomes an assert, a test, or a reference — never a copy |
| **§8** Comments granting themselves exceptions to THEME | The exceptions are in THEME; `test/core/documented_exceptions_test.dart` fails a comment that claims one without naming the section |
| **§9** No light-theme test; chart transitions unverified | `test/core/light_theme_test.dart` measures both ramps pair by pair, and `test/features/chart_transition_test.dart` holds the zoom to not resizing on any frame |

The two audits that produced much of this — [INVARIANTS.md](INVARIANTS.md) and
[INTERPRETATION.md](INTERPRETATION.md) — are back to their prompts, ready to run
again once sync exists.
