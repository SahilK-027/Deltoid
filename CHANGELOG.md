# Changelog

All notable changes to Deltoid are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). A minor release adds behaviour or changes a decision the app makes; a patch release only corrects existing behaviour.

Each entry follows the same template:

- A heading, `## [x.y.z] - YYYY-MM-DD`, then a one-line summary naming the release type.
- Sections in this order, each included only when it has entries: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**, **Internal** (changes with no user-facing effect), and **Upgrade notes** (anything required before or after installing).
- In the user-facing sections, every bullet opens with the area it affects in bold, as `**Area:**`. Supporting detail goes in a nested bullet.
- One line per bullet and per paragraph, with no hard wrapping, so each entry can be pasted into a GitHub release unchanged. `test/tools/changelog_format_test.dart` enforces the template.

Releases are distributed as Android APKs. The build number after the `+` is Android's `versionCode`; it increases with every release so that each build installs over the previous one.

## [1.21.1] - 2026-10-23

Patch release making the habit grids on Home read in the same order as the year map.

### Fixed

- **Home:** The 30-day grids on the Weigh-ins and Workouts tiles now fill down each column and then across, as the year map on the Weigh-ins screen does. The oldest day is still at the top left and today at the bottom right. They previously filled along each row, so the same days appeared in a different order from the year map and recent days could look missing.

## [1.21.0] - 2026-10-23

Minor release adding custom sessions for training outside your programme, and drawing each day in History as a calendar page.

### Added

- **Home:** You can start a custom session, for a day you train outside your programme. `Train another session` opens the session list, and the last row, `Custom session`, opens the log with no exercises in it. Add the exercises as you train them.
  - A custom session belongs to none of your programme's days, so it never changes the numbers a day opens with, never counts as a day done in the cycle, and does not bring the deload any closer.
  - Each exercise in a custom session starts blank. The ⓘ beside it still says where and when you last did it, and shows those sets when tapped.
  - The `Deload session` switch on the row marks it as a light day. It is on to begin with during a deload cycle. A deload custom session is shown in orange and left out of the strength charts, as a deload day of your programme is.
  - `Train another session` now appears for a programme with only one day, and a programme with no days yet offers `Start a custom session`.
- **Home:** `Log a past session` offers a custom session too, for a day you trained without the app. Its deload switch starts on whatever the cycle was on the day you pick.
- **History:** Workout detail for a custom session has `Mark as a deload` in its ⋯ menu, or `Not a deload` once marked, to correct the switch afterwards.

### Changed

- **History:** Each session in the list starts with its date drawn as a calendar page, the weekday on a blue strip, or orange for a deload, over the day of the month. The date no longer repeats in the line under the session's name.
  - A deload shows only its icon beside the name. Tap the icon to see the word `Deload` for two seconds.
  - Rows have more space around and between their lines.
- **History:** Sessions logged without a training day, which were called `Unplanned session`, are now called `Custom session` everywhere they appear.
- **Regimes:** A training day can no longer be named `Custom session`, so it is never mistaken for one in History or in a chart.

## [1.20.1] - 2026-10-20

Patch release keeping a rest running after you leave the log and making a change of chart range a smooth zoom.

### Fixed

- **Log:** A rest keeps running when you go back from the log screen during a session. Returning to the log shows the clock where it was, including any time added or taken off with the plus and minus controls.
  - If Android closes the app or you swipe it away from recent apps, reopening the log picks the rest up from the last completed set. A rest that is still running carries on and sounds its alert when it ends, and one that finished while the app was closed does not sound late.
  - The next set now records the rest that was actually taken, instead of none, after you have left the log mid-rest.
- **Charts:** Changing the range on an exercise or bodyweight chart zooms the chart instead of redrawing it. Each point stays on its date while the scale changes, and the old line fades out as the new one fades in.
  - Points no longer slide across the chart, and lines no longer vanish part way through the change.
  - Dates, values and gridlines move with the zoom and fade across to the new range, so the axis keeps its numbers throughout.
  - A pinch zoom is reset when you choose a new range.

## [1.20.0] - 2026-10-19

Minor release redrawing the Consistency screen as one year at a time, by week and by day.

### Changed

- **Consistency:** The screen behind the Workouts habit tile shows one year at a time instead of a small year map for every year. The year chip under the title opens a list of every year you have trained in, newest first, each with its session count.
  - `Sessions per week` draws a bar for each week of the year, blue for a week you trained and orange for a deload week, under your average sessions a week and the number of weeks you trained.
  - Pressing or dragging across the bars shows the week's dates and sessions above its bar. Press the same week again to hide it.
  - `Training calendar` shows the year as twelve month calendars, each week starting on Monday, with the week you picked on the chart and today outlined.
  - The week in progress is drawn but left out of the average and the weeks trained, so a Monday with nothing logged yet is not counted as a missed week.

## [1.19.2] - 2026-10-18

Patch release joining a chart's line across a gap and keeping the cycle readout to one line.

### Fixed

- **Charts:** Where nothing was logged for a while, a faint dotted line now joins the readings on either side, so a chart reads as one trend rather than as broken pieces. The solid line still stops at the gap, and the dotted stretch shows that nothing was measured there.
  - The bodyweight graph on the Phase card is joined the same way.
  - On a chart averaged by day, gaps of up to six days are drawn as a solid line, since bodyweight is weighed a few times a week. Only a week or more with nothing logged is dotted.
- **Progress:** The cycle readout under Cycle progress stays on one line, such as `Cycle 2 · 25 Sep–3 Oct 2026 · Cut · +4.1%`, rather than wrapping onto a second. It is set in smaller text, with equal space above and below it.

## [1.19.1] - 2026-10-17

Patch release naming deleted programmes on the All time timeline.

### Fixed

- **Progress:** The All time timeline names each deleted programme, such as `Push pull legs (deleted)`, in its legend and in the year's list of regimes. It used to call every one `Deleted programme`, so two deleted programmes in one year looked identical and the legend named the same thing twice.
  - Deleted programmes stay grey, since the six colours belong to the programmes you still have, and the names tell them apart.
  - A long name in the year's list is shortened before `(deleted)` is, so the row always says the programme is gone.

## [1.19.0] - 2026-10-17

Minor release redrawing every chart so that it reads as clearly with twenty years of data as with one week.

### Changed

- **Charts:** Every chart chooses its value axis the same way. The band fits the data with half a step of room on each side, every gridline sits on a round number, and every label states the value of its own gridline.
  - One reading, or a history that never changes, draws three gridlines with the value between them rather than a single line.
  - A reading far outside the rest, such as a mistyped 260 kg among 100 kg sessions, is drawn as a caret at the edge of the chart rather than flattening every other session against the floor.
  - The weekly volume chart prints three or four values on its axis, and its gridlines are drawn over the empty tracks so the values can be read against them.
- **Charts:** Every chart that runs over time takes its date labels from one ladder. The last label is today, labels no longer collide at a larger system font, 3M no longer repeats a month, and long ranges label whole years at even steps, such as `2006 2011 2016 2021 2026`.
  - Bar charts use the same ladder, so the last bar is labelled with today's date rather than the Monday its week began.
  - Five years of volume is drawn as sixty monthly bars rather than six yearly ones.
- **Charts:** A trend line breaks where two or more weeks or months in a row have nothing logged, rather than drawing straight across the gap. A single empty week is crossed, since one week off is part of training.
  - On the cycle chart, the line from one cycle to the next is dashed when another regime was trained in between.
  - The bodyweight graph on the Phase card breaks in the same places.
- **Charts:** A line shows its markers only while there is room between them, and pinching to zoom brings them back.
  - Volume bars have a maximum width, so a single week of training is no longer drawn as one slab across the whole chart.
  - The volume tiles on Progress fold to months at one year, so their bars stay apart.
- **Charts:** Chart cards share one spacing, and every chart has one legend under its plot. A legend never takes more than two rows and names the rest, such as `and 2 more`.
  - Two lines drawn on top of each other are named together once, such as `Push 2 and Push 1`.
  - The chip that chooses a year reads `Year` until a year is chosen. It used to name a year that was not applied.
  - Volume spans read `Last 18 months` or `Last 5 years` once a span passes about a year, rather than counting hundreds of weeks.
  - A selected cycle that is still open stays grey.
- **Progress:** On long cycle charts, deloads are drawn as faint lines rather than turning the chart orange, and a deload's cycle number is orange only where every cycle is numbered.
- **Progress:** The graphs on All time draw only the line, with no gridlines or deload bands.
- **Bodyweight:** The trend on the Weigh-ins screen behaves as an exercise trend does. One weigh-in draws one dot, a range with nothing in it shows an empty chart with no message, and the change carries its unit, such as `−3.2 kg over the range`.
  - The range control sits above the chart, as it does on every other chart, and the chart is the same height as an exercise trend.
- **Bodyweight:** `Log weight` is a round `+` in the Weigh-ins app bar beside the calendar button, matching the `+` on the Home tile. The floating button it replaces covered the current months of the year map.
- **History:** On an exercise trend, `Change` follows the progression of the session trained last and names it when the chart draws more than one session, such as `Change in Push 2`. It used to compare the first session in the range with the last, whichever sessions they were.
  - A gain is green and a drop is in the ordinary text colour rather than red. No change reads `0%`.
  - A change of 100% or more is printed as a whole number, such as `+182%`.
  - A session that equals your best counts as the best in `Sessions since best`.
- **Appearance:** In the light theme, empty cells and tracks are a lighter grey.

### Fixed

- **Progress:** On the cycle chart, a gain past +200% no longer draws the line out of the chart and over the readout, and the graphs on All time stay inside their cards.
- **Charts:** At the largest system font, chart text is no longer cut short. Three-digit set counts and long muscle names fit the weekly volume list, a volume tile prints `sets/wk` in full, and a figure under a chart that does not fit its place is set smaller rather than cut.
  - The cycle readout no longer touches the value under it.
- **Progress:** A count of one reads `1 set` in the weekly volume list, and `1 set a week` in a volume chart's readout for a month or a year. Both used to read `1 sets`.
- **Log:** A session with a single set reads `1 of 1 set` rather than `1 of 1 sets` on the in-progress tile on Home, in the session notification, and in the sheet that offers to finish with sets left. The session summary does the same, such as `Did 1 of 1 working set`.
- **Charts:** The month labels on a year map are never smaller than the app's smallest text and grow with the system font. When all twelve do not fit, every other month is printed.

## [1.18.0] - 2026-10-16

Minor release recording bulk, cut and maintenance phases and showing them on Home and on Cycle progress.

### Added

- **Home:** A Phase card between Habits and Past sessions records whether you are in a bulk, a cut or maintenance. It shows the phase, the day it started and the week it is in, such as `Week 7 of 12`.
  - A bodyweight graph covers the phase and the weeks before it, tinted by the phase each stretch ran in.
  - Three figures sit beneath it: bodyweight, the change since the phase started, and the change each week. A figure the weigh-ins cannot support shows a dash.
  - With no phase set, the card explains what a phase is for and offers `Set a phase`.
- **Phases:** `Change` on the Phase card opens the phase sheet, where you choose the phase, the day it started, and a planned length of 8, 12 or 16 weeks or none.
  - Choosing a different phase starts a new one, and choosing the same phase corrects the current one.
  - `Clear phase` ends the phase yesterday, so Home shows no phase at once. A phase started today is removed instead.
- **Phases:** The Phase card asks what comes next once the planned length has passed, with `12 weeks are up. Start the next phase, or keep this one going.`
- **Phases:** The Phase card also asks when your weigh-ins have run against the phase for about three weeks, such as `Your weight has risen for three weeks during this cut.`
  - Each question offers `Change phase`, which opens the phase sheet, and `Keep going`. When both apply, the card asks once, about the planned length, and `Keep going` answers both.
  - `Keep going` past the planned length makes the phase open-ended. Against the weigh-ins, the question returns only after three more weeks of weigh-ins run against the phase.
  - These questions appear only on the Phase card, never as a notification.
- **Progress:** On the cycle progress chart, each cycle is tinted by the phase most of its sessions ran in: bulk lavender, cut cyan and maintenance grey. A cycle trained with no phase has no tint.
  - Deloads are drawn as before, and a tint never extends beneath a deload band.
  - Under `All`, each block between two deloads takes the phase most of its sessions ran in.
  - Tapping a cycle names its phase in the readout, such as `Cycle 6 · 3 Sep to 9 Sep 2026 · Cut · +6.4%`.
  - The legend adds a swatch for each phase shown on the chart.
  - This applies to the Cycle progress card and to a regime's progress screen.
- **Sync:** Phases are backed up and synced like weigh-ins, and the backup sheet lists unsent phase changes on a line of their own.

### Upgrade notes

- **Schema change.** Adds the `phases` table. The local schema migrates from version 6 to 7 on first launch.
- If you sync to your own server, apply `supabase/migrations/20261016120000_phases.sql` with `supabase db push` before installing this build on a synced phone. Until the server has the new table, sync fails and changes wait on the phone.
- A backup written by this build is refused by earlier builds, which say that it was written by a newer version.

## [1.17.0] - 2026-10-16

Minor release replacing the four tabs with five and giving bodyweight a place on Home.

### Added

- **Navigation:** The bottom bar reads Home, Regimes, Progress, History and More. Home replaces Workouts, Progress is a new tab, and More replaces Settings.
- **Home:** A Habits section under Today's session holds a Weigh-ins tile and a Workouts tile side by side. Each shows the last 30 days as a grid and how many days of this week the habit was kept, such as `2/7 this week`.
  - The + on the Weigh-ins tile opens the weigh-in sheet, or today's weigh-in when one is already logged.
  - The play button on the Workouts tile starts the session that is due, or resumes the one that is open.
  - Tapping the Workouts tile opens Consistency, and tapping the Weigh-ins tile opens Weigh-ins.
- **Home:** A Past sessions card holds `Log a past session`, which opens the same sheet the calendar button in the masthead used to.
- **Bodyweight:** A new Weigh-ins screen shows the bodyweight trend, a year map of the days you weighed in, and a `Log weight` button. It replaces the Bodyweight screen.
  - The calendar button in its app bar opens the day picker with every weighed day ringed. A weighed day opens its weigh-in to correct or delete, and any other day logs one for that day.
- **More:** While you are signed in, More opens with your initials, the name from your Google account, and `Backed up since` with the date the account was created.

### Changed

- **Bodyweight:** Weighing in moves from Settings to the Weigh-ins tile on Home and the Weigh-ins screen behind it.
- **Progress:** Cycle progress and Weekly volume move from Workouts to the Progress tab, unchanged, with the same All time screens behind them.
- **Consistency:** The Consistency card is replaced by the Workouts tile on Home, which opens the same screen. Its year map now shares one design with the Weigh-ins year map.
- **More:** The first row of Account & backup reads `Account` with your email beneath it, and opens the sheet for signing out.
- **More:** The About card describes Deltoid as a training tracker that puts you in full control of your programs.

### Removed

- **Settings:** The Bodyweight section, whose weigh-ins are now reached from Home.
- **Bodyweight:** The list of weigh-ins grouped by month. The calendar on the Weigh-ins screen opens any past weigh-in instead.
- **Home:** The calendar button in the masthead, replaced by the Past sessions card.

## [1.16.1] - 2026-10-14

Patch release keeping the log on the exercise you move and redrawing the reorder handle.

### Changed

- **Reorder:** The handle on each row of a reorder sheet is a grip of six dots. It used to be three bars, the symbol most apps use for a menu.
  - This applies to reordering exercises on the log screen, exercises in a regime day, and the days of a regime.

### Fixed

- **Log:** Dragging the exercise you are logging to another place in the exercise rail keeps it on screen. The log used to stay at the position the exercise left, which then showed a different exercise.
  - Dragging another exercise past the one you are logging also keeps you on your exercise.
  - `Reorder exercises` now goes straight to the exercise you were logging after `Save order`, without scrolling through the pages in between.

## [1.16.0] - 2026-10-14

Minor release letting two training days alternate in one position of the cycle.

### Added

- **Regimes:** Two or more days can alternate in one position of the cycle, and each cycle trains one of them. A regime that trains Leg 1 in one cycle and Leg 2 in the next now finishes each cycle on five days rather than waiting for both.
  - On a regime's Cycle tab, select a day and choose `Alternate with an existing day` or `Add an alternating day`. `Stop alternating` gives each day its own position again.
  - Which day is due follows what you trained. Closing a cycle early leaves the same day due, and training the other day instead counts as that cycle's turn.
  - Each day keeps its own progression and its own history. Pairing two days never shares their numbers.
- **Regimes:** The regime editor opens on a Cycle tab, which shows the order of this cycle and the next and lists the days by position.

### Changed

- **Workouts:** The cycle bar and `Up next` count positions, so a cycle with two alternating days shows five segments rather than six. `Start a session` marks the alternating day that is not due with `Not due this cycle`.
- **Progress:** In a regime with alternating days, a cycle counts the day that was not trained at its last result, so the figure follows your strength rather than whichever day was due. `How is this measured?` explains this.
- **Regimes:** A day with no exercises now says that the cycle still counts it. It used to call the day a rest day, which the cycle never treated it as.

### Fixed

- **Regimes:** With a larger system font, the day tabs fit their strip. They used to be cut off at the bottom.

### Upgrade notes

- If you sync to your own server, apply `supabase/migrations/20261014120000_session_rotation.sql` before installing this build. Without the new column the server refuses the app's backups.

## [1.15.3] - 2026-10-13

Patch release correcting where the log goes after the last set of an exercise is completed out of order.

### Fixed

- **Log:** Completing the last set of an exercise while earlier sets are still open keeps you on that exercise and moves to the first open set. It used to turn to the next exercise and leave the open sets behind.
  - The page turns once every set of the exercise is completed. This holds for the checkbox, the keypad's Next key, and the hold stopwatch.
  - A set completed in the middle of an exercise still moves down to the next open set before going back to one above it.

## [1.15.2] - 2026-10-11

Patch release correcting when the done mark on a bodyweight movement turns green.

### Fixed

- **Log:** The done mark on a bodyweight movement is scored on your logged bodyweight and the share of it the movement moves. It used to assume 100 kg at a full share, so a set that added load for one rep fewer could stay white when it was the better set.
  - For example, BW+10 kg for 9 followed by BW+15 kg for 8 is a 3.5% better estimate at 70 kg and now turns green. At 100 kg the same two sets are 1.9% apart, inside the 2.5% margin, and stay white.
  - Both sets are scored on today's bodyweight, so a change on the scale between two sessions does not turn a set green.

## [1.15.1] - 2026-10-10

Patch release renaming one heading in the backup sheet that read as contradicting the line above it.

### Fixed

- **Sync:** The backup sheet's heading over the newest session on your account reads `Newest session on your account`. It used to read `Last backed up`, directly under a sentence giving the time of the last backup, so a time from today sat over a session from yesterday.

## [1.15.0] - 2026-10-10

Minor release putting the backup button on Settings and giving the account backup and the file backup different names.

### Added

- **Settings:** The cloud button is on Settings, in the same corner as on Workouts, History and Regimes.

### Changed

- **Sync:** The backup sheet's title is the state alone, such as `Backed up`. The time is in the sentence under it, `Last backed up at 14:02.`, and when changes are waiting the sentence says how many and since when.
- **Settings:** `Automatic backup` is now `Backup file on this phone`, and its time reads `Last written`. It was easy to take for the account's backup time, which it never matched.
- **Settings:** The account row shows the account and no longer repeats the backup state. The cloud button beside it says that, and its sheet says how much is waiting.

## [1.14.1] - 2026-10-10

Patch release making the fixed share of bodyweight on a built-in movement look fixed and answer a tap.

### Fixed

- **Exercises:** The `Share of bodyweight` row of a movement that comes with the app is greyed out and reads `Fixed for this movement`. Tapping it opens a sheet with the value and a note saying why it cannot be changed. It used to look editable and do nothing when tapped.

## [1.14.0] - 2026-10-10

Minor release scoring bodyweight movements on the share of the body they move, and showing that load while logging.

### Added

- **Logging:** A bodyweight movement shows the bodyweight it is scored on beside its name, with the load that comes from it, such as `73.2 kg` over `+69.5 kg (95%)`. Tapping it opens a sheet that explains the figure and lets you log your weight without leaving the session.
  - The ring turns yellow when your last weigh-in is more than a week old, or when no weight has been logged.
- **Exercises:** A bodyweight movement has a share of bodyweight. Push-up is 64%, and Pull-up, Chin-up and Dips are 95%. A bodyweight movement you create asks for its own share.

### Changed

- **Progress:** A bodyweight movement is scored on its share of your bodyweight plus any weight you add, where it used to count your whole bodyweight. Estimated 1RM, charts, session volume and cycle progress for Push-up, Pull-up, Chin-up and Dips change to match.
  - Movements you created keep counting your whole bodyweight until you set their share on the exercise's screen.
- **Progress:** With no bodyweight logged, 60 kg is assumed, where a bodyweight movement used to go unscored and a weighted one was scored on its added weight alone. The first weight you log replaces the assumed figure for every past session.

### Upgrade notes

- If you sync to your own server, apply `supabase/migrations/20261010120000_bodyweight_pct.sql` before installing this build. Without the new column the server refuses the app's backups.

## [1.13.0] - 2026-10-10

Minor release letting a set in a past session be corrected.

### Added

- **History:** A set in a past session can be corrected. Tapping the set, marked with a pencil, opens a sheet where its weight, reps, partial reps and set type can be changed, or the set deleted.
  - Charts, weekly volume, cycle progress and the next session's suggested numbers all follow the corrected set.
  - A session that is still being logged is changed on the log screen, as before.

## [1.12.3] - 2026-10-04

Patch release letting a set be logged as full reps when the same set had partial reps last time.

### Fixed

- **Logging:** A set ticked without partial reps shows as a full set, even when the same set had partials last time. It used to keep last week's partial count beside the reps, so `8` read as `8 | 2`.
  - Nothing stored changes: a set ticked without partials was already saved as full reps.
- **Logging:** The `F` / `P` key reads `P` whenever the partial box is open, including when last week's partials opened it. One press of `F` closes the box and clears the partials, and the box stays closed while you fill in the rest of that set.

## [1.12.2] - 2026-09-24

Patch release listing a discarded session once in the backup sheet.

### Fixed

- **Sync:** A session that was started and then discarded no longer appears in the backup sheet as a second copy of the session being logged. Until its removal is backed up, it is counted on one line, `Discarded and deleted sessions`, with sessions deleted from History.

## [1.12.1] - 2026-09-24

Patch release turning the backup button green as soon as the connection returns, and showing the backup sheet's explanation in full.

### Fixed

- **Sync:** The backup button turns green as soon as the phone is back online, rather than staying yellow until the next backup attempt succeeded. That attempt could be half a minute or more away, because the first try right after reconnecting often fails before the network is fully ready. The attempts just after reconnecting now retry every few seconds. The button turns yellow again if they keep failing.

- **Sync:** The sentence at the top of the backup sheet, such as "Everything is saved on this phone. It is backed up to your account when the phone is online again.", is shown in full. It was cut off after the first few words, because it sat in the sheet's one-line subtitle.

## [1.12.0] - 2026-09-24

Minor release making the backup status visible at all times, with a button that shows what is only on this phone.

### Changed

- **Sync:** The cloud button in the header of Workouts, History, Regimes and the log is now always shown while you are signed in, beside the calendar on Workouts. It is green while the phone is online and your training is backed up, and yellow as soon as the phone loses its connection or a backup attempt fails. A yellow button carries the number of sets and entries not yet backed up.
  - Tapping it opens a sheet that confirms everything is saved on this phone, lists what is on this phone only by session, such as `Push 1 · today · 17 sets, in progress`, and names the last session your account holds. While something is waiting offline, it offers to try again now.
  - The button no longer appears only after a failed attempt, which left it hidden whenever the phone had signal.

## [1.11.0] - 2026-09-24

Minor release showing, on every tab and on the log, when training has not yet been backed up.

### Added

- **Sync:** When an attempt to back up fails and changes are still waiting, a cloud mark appears in the header of Workouts, History and Regimes, and beside Finish on the log. It is grey when there is no connection and yellow when the account refused the changes, and it disappears as soon as a backup succeeds. It does not appear while the phone has a connection and a set is simply waiting a few seconds to be sent.
  - Tapping it opens a sheet that confirms everything is saved on this phone, says how many changes are waiting and since when, lists them by kind, such as workouts and sets, and offers to try again now.

## [1.10.3] - 2026-09-24

Patch release removing a false save warning when training offline, and applying a changed rest time to the exercise in progress.

### Fixed

- **Sync:** Training without a signal no longer shows "That change was not saved." Every set was saved; the message came from the account's routine sign-in refresh failing without a network, which was reported as though a change had been lost. No network now shows nothing, and Settings still shows how many changes are waiting to be backed up.
- **Logging:** A rest time changed in an exercise's settings, opened from the log's menu, now applies to that exercise from its next set. It previously took effect only after turning to another exercise and back. The same applies to the default rest changed in Settings. A rest already counting down keeps its length.

## [1.10.2] - 2026-09-14

Patch release restoring the Cycle progress section on a Workouts screen with no regime on it.

### Fixed

- **Workouts:** Cycle progress is drawn in the screen's empty states, alongside Consistency and Weekly volume, rather than being left out until a regime exists. The card already had an empty state of its own — four cycle slots and dashes for the figures — so the section now appears on a fresh install and the first regime fills it instead of building it.

## [1.10.1] - 2026-09-13

Patch release correcting how chart axes are labelled at larger font sizes.

### Fixed

- **Charts:** At the largest font size, a chart's value labels no longer lose their unit. The axis printed `+60` where it meant `+60%`, and `200` where it meant `200 kg`, because the room reserved for a label was measured at the standard font while the label was drawn at the chosen one. Every chart in the app was affected.
- **Cycle progress:** The cycle numbers under the chart are spaced to fit the width and the font in use, rather than to a fixed rule. Twelve cycles are numbered one by one where they fit and every second where they do not, always at an even spacing.
  - The cycle being read is no longer forced onto the axis, which could print it half a step after its neighbour. It is named in full above the chart.

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

[Unreleased]: https://github.com/SahilK-027/Deltoid/compare/v1.21.1...HEAD
[1.21.1]: https://github.com/SahilK-027/Deltoid/compare/v1.21.0...v1.21.1
[1.21.0]: https://github.com/SahilK-027/Deltoid/compare/v1.20.1...v1.21.0
[1.20.1]: https://github.com/SahilK-027/Deltoid/compare/v1.20.0...v1.20.1
[1.20.0]: https://github.com/SahilK-027/Deltoid/compare/v1.19.2...v1.20.0
[1.19.2]: https://github.com/SahilK-027/Deltoid/compare/v1.19.1...v1.19.2
[1.19.1]: https://github.com/SahilK-027/Deltoid/compare/v1.19.0...v1.19.1
[1.19.0]: https://github.com/SahilK-027/Deltoid/compare/v1.18.0...v1.19.0
[1.18.0]: https://github.com/SahilK-027/Deltoid/compare/v1.17.0...v1.18.0
[1.17.0]: https://github.com/SahilK-027/Deltoid/compare/v1.16.1...v1.17.0
[1.16.1]: https://github.com/SahilK-027/Deltoid/compare/v1.16.0...v1.16.1
[1.16.0]: https://github.com/SahilK-027/Deltoid/compare/v1.15.3...v1.16.0
[1.15.3]: https://github.com/SahilK-027/Deltoid/compare/v1.15.2...v1.15.3
[1.15.2]: https://github.com/SahilK-027/Deltoid/compare/v1.15.1...v1.15.2
[1.15.1]: https://github.com/SahilK-027/Deltoid/compare/v1.15.0...v1.15.1
[1.15.0]: https://github.com/SahilK-027/Deltoid/compare/v1.14.1...v1.15.0
[1.14.1]: https://github.com/SahilK-027/Deltoid/compare/v1.14.0...v1.14.1
[1.14.0]: https://github.com/SahilK-027/Deltoid/compare/v1.13.0...v1.14.0
[1.13.0]: https://github.com/SahilK-027/Deltoid/compare/v1.12.3...v1.13.0
[1.12.3]: https://github.com/SahilK-027/Deltoid/compare/v1.12.2...v1.12.3
[1.12.2]: https://github.com/SahilK-027/Deltoid/compare/v1.12.1...v1.12.2
[1.12.1]: https://github.com/SahilK-027/Deltoid/compare/v1.12.0...v1.12.1
[1.12.0]: https://github.com/SahilK-027/Deltoid/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/SahilK-027/Deltoid/compare/v1.10.3...v1.11.0
[1.10.3]: https://github.com/SahilK-027/Deltoid/compare/v1.10.2...v1.10.3
[1.10.2]: https://github.com/SahilK-027/Deltoid/compare/v1.10.1...v1.10.2
[1.10.1]: https://github.com/SahilK-027/Deltoid/compare/v1.10.0...v1.10.1
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
