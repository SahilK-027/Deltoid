# Deltoid — read this first

**Read [README.md](README.md) before changing anything.** It carries the domain
model, the invariants, the environment quirks, and the traps already hit.

Two more, each with one job:

- **[THEME.md](THEME.md)** — the design language. Colours, the nine type roles,
  and the component vocabulary every screen composes from. Read it before
  touching anything visual, and don't invent a card, row, button or sheet that
  isn't in it. §0 fences the scope: we share a language with a much larger app,
  not its feature set.
- **[TODO.md](TODO.md)** — what is built, what isn't, and the order of the work
  in flight. Status lives there, never in the README.

The short version, so you don't break it before you get there:

1. **Prefill is scoped to the session, not the exercise.** Push 1 and Push 2
   keep separate progressions for the same movement. This is the entire reason
   the app exists. Do not "simplify" `resolvePrefill`.
2. **`WorkoutExercise` / `SetLog` are snapshots of the template, not pointers.**
   Editing a programme must never rewrite past logs.
3. **No programme is hardcoded.** `seed/` ships an exercise catalog and
   *optional* templates. Never seed a regime, and never put personal numbers,
   cues or video links in `seed_data.dart` — those are the user's, added
   through the UI.
4. **The log screen is a `PageView`** — one exercise per page. The set row is
   the single exception: swiping one left uncovers its delete. Nothing else
   inside the log may claim a horizontal gesture.
5. **History paging is keyset, not offset** (`HistoryCursor` on
   `startedAt` + id). Finishing a session while the list is open must not shift
   the page boundary.
6. **Never watch a constant query.** `customSelect('SELECT 1', readsFrom: …)`
   fires once and then goes silent forever, with no error. Use
   `db.watchQuery(...)` from `lib/data/db/watch.dart`.
7. **Pure logic lives in `lib/domain/`** and is tested without a database.
   Extend those tests when changing behaviour.
8. Regenerate drift code after any edit to `lib/data/db/tables.dart`:
   `dart run build_runner build`.
9. **Never copy the project to keep an old version around.** No `old-*/`
   folders, no `*.bak` files, no second checkout, no `git worktree` for
   "reference". Git already holds every previous state, and a copy is 100 MB of
   build output that goes stale the moment it is made, gets edited by mistake,
   and shows up in searches as a second answer to every question. To read the
   old version of a file, read it out of history:

   ```
   git show <commit>:lib/features/today/today_screen.dart
   git log --oneline -- <path>          # find the commit
   git diff <commit> -- <path>          # what changed since
   ```

   One of these was found at 99 MB, parked nine commits back, holding a test
   file two revisions out of date.

Before saying anything is done: `flutter analyze && flutter test`.

This is a personal tool for one person. Check the README's **Non-goals** before
adding a feature — the answer is usually no.
