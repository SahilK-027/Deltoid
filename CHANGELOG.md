# Changelog

All notable changes to Deltoid are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). A minor release adds behaviour or changes a decision the app makes; a patch release only corrects existing behaviour.

Each entry follows the same template:

- A heading, `## [x.y.z] - YYYY-MM-DD`, then a one-line summary naming the release type.
- Sections in this order, each included only when it has entries: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**, **Internal** (changes with no user-facing effect), and **Upgrade notes** (anything required before or after installing).
- In the user-facing sections, every bullet opens with the area it affects in bold, as `**Area:**`. Supporting detail goes in a nested bullet.
- One line per bullet and per paragraph, with no hard wrapping, so each entry can be pasted into a GitHub release unchanged. `test/tools/changelog_format_test.dart` enforces the template.

Releases are distributed as Android APKs. The build number after the `+` is Android's `versionCode`; it increases with every release so that each build installs over the previous one.

## [Unreleased]

## [1.10.0] - 2026-09-12

Minor release replacing the Last session card on Workouts with how much stronger the active programme has made you, cycle by cycle.

### Added

- **Workouts:** A Cycle progress card, showing the change in strength across the active regime's cycles as one figure, one word for the direction, and a chart with a point per cycle.
  - Every cycle is compared with cycle 1 of that regime, and the comparison never restarts. Switching to another programme pauses a regime; coming back carries on from the next cycle number.
  - A cycle's point is the mean change across the lifts trained in it, where a lift is one exercise in one session — Push 1 bench and Push 2 bench are two lifts, as they are everywhere else in the app.
  - A deload cycle scores nothing and is drawn as an orange band. The cycle being trained is drawn as a hollow dashed point, because it is not finished.
  - Tapping a cycle names it under the figure, with the days it covered and what it scored. The range is Last 12, Last 24 or All; past 24 cycles All draws one point per block, the last cycle before each deload.
  - A regime in its first cycle says so instead of claiming a comparison, and one with nothing logged keeps the card and prints dashes.
- **Regimes:** A screen behind the card listing every lift the latest cycle compared, grouped into stronger, no change and weaker, each row carrying the best set in cycle 1 and the best set now.
  - A panel explaining how the figure is arrived at, folded away until it is opened.
  - In a first cycle the screen lists which lifts are recorded and which are still to train.
- **Regimes:** An All time screen, reached from the Cycle progress heading: a year of training as one cell per week, coloured by the regime trained, orange for a deload week and grey for a week off, with the year chosen by a stepper.
  - The regimes trained in that year are legended separately from the two week states, and the spells behind the strip open to name their dates and cycle numbers.
  - A card per regime with its own chart and figures, the one being trained marked Active.

### Removed

- **Workouts:** The Last session card is gone. The masthead already says when you last trained and History lists the session itself, so the space now answers a question nothing else did.

## [1.9.0] - 2026-09-12

Minor release giving every colour in the app one meaning, and redrawing the plate view on the keypad.

### Changed

- **Colour:** Orange now means a deload and nothing else, and blue means progress and nothing else — a trained day, and every line on every chart.
  - The colours that identify a regime or a muscle region are a new set of six, in the order pink, cyan, yellow, lavender, sand, green. Warm and cool alternate, so two bars side by side never read as one.
  - A rested day in the week strip is grey rather than orange, because a rest day is not a deload.
  - Drop sets and rest-pause sets are lavender. Warm-up sets stay cyan.
- **Exercise history:** Each session on an exercise's chart keeps its own colour, blue for the most recent. Where more than seven sessions fall inside the selected range, the seven most recently trained are drawn and the chart says so, for example "Showing 7 of 9 sessions" — rather than two progressions sharing a colour.
- **Exercise history:** A count of sessions since your best is grey. It was the red the app uses for deleting, which made an ordinary number read as a fault.
- **Keypad:** The plate view is redrawn as the bar, then what goes on one end, then the bar's own weight, each plate carrying a swatch in the colour it physically is. It replaces a sentence that had to be read like a formula between sets.
  - Two plates to a column: a third kind starts a column beside the first rather than pushing the keypad down.
  - A weight the rack cannot make says how much is missing per side, in grey with a warning glyph. It is not an error — no gym has every plate — so it is no longer drawn in red.

### Removed

- **Keypad:** The button that put the keypad away is gone. Back closes the pad, keeping the session open and saving what was typed.

## [1.8.0] - 2026-09-11

Minor release letting the end of a session lower a movement's programmed set count.

### Added

- **Session summary:** When fewer working sets were ticked than the day programmes, the summary offers the lower count to the programme, for example "Did 1 of 3 working sets of Deadlift". Ticking it means the next workout opens on the shape that was trained, without empty working sets added to reach the old count.
  - Left unticked, nothing changes: the next workout adds the missing working sets back, as before.
  - Not offered in a deload week, for a skipped exercise, for an exercise with no working set ticked, or for an exercise the day runs twice.

## [1.7.0] - 2026-09-11

Minor release removing the keypad's last-time button and correcting how an exercise edited mid-session reaches the session in progress.

### Removed

- **Keypad:** The "Last time" button above the digits is gone. The cell being typed into already shows last time's number, and `Next` adopts it when nothing is typed.

### Fixed

- **Log:** Changing an exercise's bar while a session is in progress now updates that session's plate view. It previously kept breaking weights over the bar the session opened with, for example a 20 kg bar after the exercise was changed to the 16 kg women's bar.
  - A training day that names its own bar for the movement keeps it, and finished sessions keep the bar they were logged on.
- **Log:** Changing an exercise's muscle while a session is in progress now counts that session's sets toward the new muscle. Finished sessions keep the muscle they were logged with.
- **Log:** The log redraws as soon as an exercise is edited. A new name, load mode, or measure mode previously appeared only after the next set was written.
- **Exercises:** The confirmation for a muscle change now states that finished sessions keep their muscle. It previously claimed every set would move.

## [1.6.3] - 2026-09-11

Patch release consolidating duplicated UI components and correcting the visual inconsistencies between them.

### Fixed

- **Sheets:** Long pickers now share a single maximum height of 70% of the screen. The chart year picker stopped at 70% and the exercise muscle and equipment pickers at 66%.
- **Charts:** The weekly volume chart's gridlines now use the same dash pattern as the line charts (4 pt drawn, 4 pt gap, previously 3 pt and 3 pt).
- **Charts:** The volume chart no longer truncates value labels when the axis exceeds 100 sets per week. The label gutter is now measured against every printed label rather than the axis maximum alone.
- **Heatmap:** The year heatmap now repaints when the theme changes. A year already on screen could retain the previous theme's colours.
- **Bodyweight:** The empty-state button now uses the standard primary button and its press feedback, replacing a Material ripple.
- **Accessibility:** The add buttons in the set table now carry screen-reader labels: "Add a set", and "Add a leg" on a drop set.

### Internal

- All bottom sheets open through a single `showAppSheet` helper. A test fails on any direct call to `showModalBottomSheet`.
- Introduced `InsetPanel`, `PadKey` and `PadDismissButton`, replacing five hand-built panels and the duplicated keys of the set keypad and hold pad.
- `StepperRow` moved into the shared primitives; redundant `Divider` arguments removed in favour of the theme.
- Chart axis helpers (`axisLabelCount`, `axisDateFormat`, `axisGutter`, `gridlineDash`) and heatmap colours (`heatColourIn`) are shared between charts.
- Added the `Radii.bar`, `Radii.heatCell` and `Sizes.key` tokens and removed the unused filled-button theme.

## [1.6.2] - 2026-09-09

Patch release fixing truncated value-axis labels.

### Fixed

- **Charts:** Value-axis labels in the two hundreds are no longer truncated (for example, `205` rendered as `20`).
  - The label gutter was sized from the axis bounds only. Inter's figures are proportional, so interior labels can be wider than either bound. The gutter is now measured against every tick.

## [1.6.1] - 2026-09-08

Patch release completing the month-transition fix from 1.6.0.

### Changed

- **Calendar:** The incoming month now fades in place instead of sliding in from the edge.

### Fixed

- **Calendar:** The outgoing month no longer remains visible beneath the incoming one during a month change. The 1.6.0 fix used `Threshold(0)`, which has no effect; it now uses `Threshold(1)`.

## [1.6.0] - 2026-09-08

Minor release reworking the day picker used by backfill, weigh-ins and session re-dating.

### Added

- **Calendar:** Swipe horizontally to change month. The arrow controls remain.
- **Calendar:** The selected day is shown beneath the picker title.
- **Calendar:** Every month is laid out as six full rows, with adjacent-month days shown at reduced emphasis.

### Changed

- **Calendar:** The layout now reads top to bottom: title, selected day, month, weekday letters, then dates.
- **Calendar:** The month and year selectors use the standard chip component.
- **Calendar:** Rings on logged days are heavier than those on empty days.
- **Backfill:** A session can be backfilled to any date, including dates before the first logged session.

### Fixed

- **Calendar:** A grey ring no longer flickers on future days when paging to the current month.
- **Calendar:** `September` is no longer truncated on 384 dp-wide screens.
- **Calendar:** Both months were briefly drawn on top of each other during a month change. This fix was incomplete; see 1.6.1.

## [1.5.0] - 2026-09-08

Minor release making every day in the day picker state whether it holds data.

### Changed

- **Calendar:** Every selectable day now carries a ring: in the day's colour when something is logged, grey when nothing is.
- **Calendar:** Today is marked with a dot beneath the date instead of a ring.
- **Calendar:** Tapping a day outside the permitted range shows the reason instead of doing nothing.
- **Calendar:** The month is shown at the top of the card, with the weekday initials and controls at the bottom. Month and year are now separate selectors.

### Fixed

- **Calendar:** The picker no longer overflows at large system font sizes.

## [1.4.1] - 2026-09-08

Patch release fixing the loss of a weigh-in when changing an entry's date.

### Fixed

- **Bodyweight:** Changing the date on the weight sheet no longer deletes the entry it was opened from. Each day is now written independently and is cleared only by deleting it.
- **Bodyweight:** The weigh-in calendar now marks days that already have an entry.

### Upgrade notes

- Weigh-ins lost to this defect cannot be recovered by this build. They were soft-deleted, so a backup taken before the loss still contains them.

## [1.4.0] - 2026-09-06

Minor release rebuilding Settings and making three device behaviours optional.

### Added

- **Settings:** Rest-end vibration can be switched off independently of the rest tone.
- **Settings:** The ongoing session notification can be switched off.
  - Without the notification Android does not run the background service, so the rest bar stops updating while the screen is off. The rest-end alert is a scheduled alarm and still fires.
- **Settings:** Keeping the screen on during a session is now optional.

### Changed

- **Settings:** Reorganised from six sections and thirteen rows into four sections. Rows state their current value, and explanations moved into the sheets they open.
- **Account:** "Sign out" and "Sign out and delete data" are now presented in a single sheet, each with a description of its effect.
- **Settings:** The About section now shows the app version.
- **Log:** Dumbbell sets read `20 kg each × 10` instead of `20 kg × 2 × 10`, and the compact history format now includes the pair.

### Fixed

- **Settings:** Rest helper text is no longer truncated beside stepper controls; it now spans the full width beneath the row.
- **Bodyweight:** The chart now retains the selected range after leaving the screen.
- **Backup:** The automatic backup row states whether a backup has ever run.

### Upgrade notes

- On Android 8 and later, vibration is fixed per notification channel, so the app may list up to four channels in the system notification settings.
- The three new preferences are stored on the device and are not synced.

## [1.3.1] - 2026-09-06

Patch release restoring notifications and the rest-end alert sound in release builds.

### Added

- **Log:** For a movement not yet trained in the current session, the exercise information sheet shows what was done in the other session. Values are still not prefilled.

### Changed

- **Notifications:** The session notification reads "Currently tracking" with the session name, current movement and set, rest countdown and elapsed time, and uses the app's own accent colour.

### Fixed

- **Notifications:** The rest-end alert plays its tone in release builds. The resource shrinker had removed the sound from every release APK.
- **Notifications:** The session notification is posted again. The shrinker had also removed its status-bar icon in 1.3.0.
- **Log:** The rest clock remains visible while the keypad is open.
- **Log:** The rest bar no longer overflows on narrow screens.
- **Log:** `BW` is drawn at the same size as the weight beside it.

## [1.3.0] - 2026-09-06

Minor release adding a live session notification and correcting prefill.

> **Known issue:** the APK attached to this release cannot post notifications, because the resource shrinker removed the notification icon. Install 1.3.1 instead.

### Added

- **Notifications:** The session notification shows the current movement, the set count and a draining rest bar. It runs as a foreground service so the bar keeps updating with the screen off.

### Changed

- **Prefill:** A session with no history of its own now opens blank instead of borrowing the most recent performance from another session. The information sheet still names where the movement was last performed.
- **Log:** A set with a higher estimated 1RM than the previous one is marked as progress even when reps were traded for weight, using a 2.5% margin.

### Fixed

- **Notifications:** The rest-end alert now fires on Android 12 and earlier. `SCHEDULE_EXACT_ALARM` is declared for API 32 and below, and a refused exact alarm falls back to an inexact one.
- **Log:** The set sheet no longer states that warm-ups are ignored by the previous-performance reference.
- **Log:** Focusing a set cell scrolls only when the row is out of view.
- **App:** The launcher icon's mark no longer runs to the edge of its tile.

### Upgrade notes

- Adds a foreground service and two permissions. Install over the existing app so both are registered.

## [1.2.1] - 2026-09-04

Patch release fixing status-bar icon contrast in the light theme.

### Fixed

- **Theme:** Status-bar icons now follow the app theme. In the light theme they were white on white until the app was backgrounded and resumed.

## [1.2.0] - 2026-09-04

Minor release making the bar a property of the training day and of each logged set.

### Added

- **Log:** The exercise menu in a session opens the exercise's settings, with the day's overrides, without leaving the session.

### Changed

- **Log:** The bar is set per training day rather than once in the catalog, and every logged set records the bar it was performed on. Changing a bar no longer alters the plate diagrams of past sessions.

### Fixed

- **Log:** A training day containing the same movement twice no longer breaks the exercise menu, adding an exercise, or swapping one.
- **Log:** The exercise information sheet shows the day's bar, matching the keypad's plate diagram.

### Upgrade notes

- **Schema change.** Adds `bar_kind` to `session_exercises` and `workout_exercises`. The local schema migrates from version 3 to 4 on first launch.
- Apply the server migration (`supabase db push`) before installing on a synced device. Until the server has the new columns, every push fails.

## [1.1.0] - 2026-09-04

Minor release making rest durations configurable.

### Added

- **Rest:** Each exercise in a training day can carry its own rest target.
- **Settings:** Default rest, rest between exercises, and a rest-tone switch.

### Changed

- **Rest:** The rest target is no longer inferred from the previous rest taken. Exercises without their own target open on the default of two minutes.

### Fixed

- **Notifications:** The rest-end alert now fires with the screen off. The alarm is scheduled when the rest starts, not when the app is backgrounded.
- **Notifications:** The lock-screen countdown no longer runs past zero.
- **Notifications:** When the tone cannot play, for example during a call, the alert falls back to the notification.

### Upgrade notes

- The new preferences are stored on the device and are not synced.

## [1.0.0] - 2026-09-01

Initial release of Deltoid, an offline-first training log for Android.

### Added

- **Programmes:** Regimes, sessions and cycles, with scheduled deloads and per-exercise overrides.
- **Prefill:** Progression is scoped to the session, not the exercise, so Push 1 and Push 2 keep separate histories for the same movement.
- **Log:** One exercise per page, with a keypad prefilled from the previous session, plate diagrams, warm-up and drop sets, partial reps, timed isometric holds, and a rest timer that runs with the screen off.
- **History:** Logged workouts are snapshots, so editing a programme never rewrites a past session. Notes at the session, exercise and set level.
- **Charts:** Estimated 1RM and heaviest weight over time by session, weekly hard sets by muscle, a yearly consistency heatmap, and a bodyweight trend.
- **Backup:** Export and restore of a single backup file, written automatically after each finished session.
- **Sync:** Optional cloud backup with Google sign-in. Without an account the app runs entirely on the device.
- **Settings:** Kilograms or pounds, light or dark theme, and support for the system font size.

[Unreleased]: https://github.com/SahilK-027/Deltoid/compare/v1.10.0...HEAD
[1.10.0]: https://github.com/SahilK-027/Deltoid/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/SahilK-027/Deltoid/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/SahilK-027/Deltoid/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/SahilK-027/Deltoid/compare/v1.6.3...v1.7.0
[1.6.3]: https://github.com/SahilK-027/Deltoid/compare/v1.6.2...v1.6.3
[1.6.2]: https://github.com/SahilK-027/Deltoid/compare/v1.6.1...v1.6.2
[1.6.1]: https://github.com/SahilK-027/Deltoid/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/SahilK-027/Deltoid/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/SahilK-027/Deltoid/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/SahilK-027/Deltoid/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/SahilK-027/Deltoid/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/SahilK-027/Deltoid/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/SahilK-027/Deltoid/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/SahilK-027/Deltoid/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SahilK-027/Deltoid/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SahilK-027/Deltoid/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SahilK-027/Deltoid/releases/tag/v1.0.0
