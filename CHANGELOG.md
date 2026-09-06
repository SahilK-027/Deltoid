# Changelog

What changed in each release, in terms of what the app does rather than what
the code does. The format follows [Keep a Changelog](https://keepachangelog.com),
and versions follow [semantic versioning](https://semver.org): a minor release
changes what the app decides or adds something to it, a patch release only
fixes what it already did.

Every release is an Android APK installed by hand. The build number is Android's
`versionCode` and always increases, because a build whose code has not moved
will not install over the one already on the phone.

## 1.4.0 — 2026-09-06

### Added

- **Vibration, the session notification and keeping the screen on are now
  choices.** All three used to happen whether you wanted them or not. The buzz
  at the end of a rest is its own switch rather than half of the tone's — the
  tone is what carries over a gym, and the buzz is what a phone lying face down
  on a bench still reports.
- Turning the session notification off stops the ongoing line entirely, because
  Android will not run the background service behind it without one. The
  end-of-rest alert is a scheduled alarm rather than part of that service, so it
  still arrives; what is lost is the clock counting down while the screen is
  off. The row says so.

### Changed

- **Settings is rebuilt.** It was six sections and thirteen rows, several of
  them explaining themselves in a column too narrow to finish a sentence. Rows
  now state their answer — `Rest time & alert`, `Weight units · Kilograms` —
  and the explanation lives in the sheet the row opens, where it has the width
  to be a whole sentence. Account and backup are one section, rest and units
  another.
- **Signing out is one row that opens both ways out**, each with room to say
  what it does. Side by side they read as the same action twice: both titles
  began "Sign out", and the difference between them was whether years of
  training stayed on the phone.
- **About names the version.** It read a paragraph set smaller than everything
  around it, with no version anywhere — which is the one thing an About section
  exists to answer.
- A set logged on a pair of dumbbells reads `20 kg each × 10`. `×` used to mean
  both "a pair" and "for this many reps", and printed both at once as
  `20 kg × 2 × 10`. Worse, the compressed form on an exercise's own history
  never carried the pair, so the same set looked like half the load on one
  screen and twice it on another.

### Fixed

- **Every rest helper was being cut mid-sentence.** A stepper's ± controls and
  its readout take the width the description was sharing, so "The default for an
  exercise that has not been given…" is all that ever fit. The sentence now runs
  the full width beneath the row, here and in a regime's deload settings.
- The bodyweight chart keeps the range you picked. Choosing 1M and coming back
  to the screen later drew 3M again.
- The automatic backup row says whether it has ever run, rather than only
  describing when it would.

## 1.3.1 — 2026-09-06

### Fixed

- **The end-of-rest alert has a sound again, on every release build.** The tone
  the system plays when a rest ends is an Android resource, and the release
  build's resource shrinker had been deleting it from the APK for want of a
  reference it could see. Every release ever installed has been missing it. The
  tone that plays with the app open is a different file, which is why the alert
  worked in front of you and never from a pocket, and why this looked for so
  long like a problem with alarms.
- **The session notification appears at all.** 1.3.0 gave it a new status bar
  icon, the shrinker removed that too, and a notification whose icon does not
  exist cannot be posted — so the line describing the workout never appeared,
  and the phone reported that the app had never sent a notification.
- The rest clock stays on screen while the keypad is open. It used to be taken
  away the moment you tapped a cell, which is the moment you are most likely to
  be looking at it.
- On a narrow screen the rest bar no longer overflows its row.
- `BW` is drawn in the same size as the weight beside it, so `BW + 10` reads as
  one value rather than a superscript and a number.

### Changed

- The notification for a session in progress reads as a tracker: "Currently
  tracking Push 1", the movement and the set you are on under it, and the rest
  clock in front of that while one is running. It carries the app's own
  charcoal, and how long you have been training sits beside the app's name the
  way it does on any other ongoing notification.

### Added

- The exercise information sheet folds open on what was done in the other
  session, for a movement this session has not trained before. The numbers are
  still not filled in anywhere — a first time here starts blank — but they are
  one tap away instead of gone.

## 1.3.0 — 2026-09-06

### Added

- The notification for a session in progress now says what the workout looks
  like: the movement you are on, the set count beside the app name, and the
  rest clock draining a second at a time under it. It runs as a foreground
  service, which is what lets the bar keep counting once the screen is off.
  Grant the notification permission and reinstall rather than updating in place
  if the line looks stale.

### Fixed

- **The end-of-rest alert now arrives on Android 12 and below.** The exact-alarm
  permission the app was asking for only exists from Android 13, so on older
  phones the system refused every alarm the app scheduled and nothing said so.
- **A session with no history of its own now opens blank.** It used to fill
  itself from the most recent performance of the same movement in any session,
  so a first Leg 2 arrived carrying a first Leg 1's numbers. Sessions keep
  separate progressions, and this was that rule failing at the one moment it
  matters most.
- **A set that is stronger by estimated 1RM now reads as a win** even when it
  traded reps for weight. 72 kg × 12 followed by 100 kg × 8 is progress, and it
  was being marked as a trade-off.
- **The set sheet no longer claims warm-ups are ignored by last-time.** They
  never were: a warm-up is mirrored into next week's rows and carries its own
  reference like any other set. Only the description of it was wrong, and it
  was wrong for long enough to be believed.
- The log no longer scrolls to reveal a set row that is already on screen.
  Tapping a cell moved the page under your thumb even when every set was in
  view.
- The launcher icon's mark no longer runs to the edge of its own tile.

## 1.2.1 — 2026-09-04

### Fixed

- **The status bar's icons follow the app's theme.** In the light theme they
  were white on white, and stayed that way until the app was backgrounded and
  brought forward again.

## 1.2.0 — 2026-09-04

### Added

- **A bar is a property of the day, and of the set you logged.** A movement can
  sit on a different bar in different sessions — off the rack on one day, a
  lighter bar on another — and the plate diagram now follows the day rather
  than one answer held in the catalog. Sets already logged keep the bar they
  were lifted on, so changing a bar today no longer redraws every session in
  your history.

### Fixed

- **A day that runs the same movement twice no longer breaks.** Opening the ⋯
  menu, adding an exercise, and swapping one all failed on such a day, and
  running a lift early and again as a burnout is a supported thing to do.
- The exercise information sheet showed the catalog's bar while the keypad
  below it drew plates for the day's.

## 1.1.0 — 2026-09-04

### Added

- **Rest is configurable.** Each exercise in a session can carry its own rest
  target — a heavy compound wants three minutes and a cable fly wants sixty
  seconds — with a default in Settings behind it. The pause between two
  exercises is its own number, because the walk to the next machine is a
  property of the gym rather than of the lift. The alert tone can be turned off
  without losing the buzz.

### Changed

- **A rest target is a decision, not a measurement.** The app used to infer one
  from however long you happened to take last time, which meant the timer opened
  on a different number most weeks with nothing on screen to explain it. Rests
  are still recorded against every set; they no longer set the target.

### Fixed

- **The end-of-rest alert now fires.** It had never reached a phone whose screen
  was off.

## 1.0.0 — 2026-09-01

First release.

Deltoid is an offline-first training log. Every screen reads from the phone,
nothing waits on a server, and the app works in full with no account.

- **Sessions keep separate progressions.** Push 1 and Push 2 each remember their
  own history for the same movement, so what a session offers you is what that
  session did last time — not what the exercise did most recently somewhere
  else. This is the reason the app exists.
- **Regimes, cycles and deloads.** Any number of sessions in any order; one pass
  through them is a cycle. A scheduled deload lightens weights and cuts sets for
  a cycle, with per-exercise overrides.
- **A log screen built for a gym floor.** One exercise per page, a keypad that
  fills from last time, plate diagrams for what to load on the bar, warm-up and
  drop sets, partial reps, isometric holds timed rather than counted, and a rest
  timer that survives the screen going off.
- **History that stays true to the day.** A logged workout is a snapshot, so
  editing a programme never rewrites a past session. Every day, every movement,
  and every set is browsable, with notes at the session, exercise and set level.
- **Charts and volume.** Estimated 1RM and heaviest weight over time, split by
  the session each set was trained in; weekly hard sets by muscle; a
  year-at-a-time consistency heatmap; bodyweight with a trend.
- **Backup and restore.** One file holding every workout, written automatically
  after each finished session and exportable to Downloads or any app that takes
  a file.
- **Cloud backup, optional.** Sign in with Google and the phone keeps a copy in
  your own account, so a lost phone is not a lost history. Asked once, at first
  launch, with declining given equal standing — and the app behaves exactly as
  it did before sync existed if you never sign in.
- Kilograms or pounds, light or dark, and a font that follows the system size.
