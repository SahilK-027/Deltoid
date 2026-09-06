# Copy audit

Every user-facing string in `lib/` measured against
[CLAUDE.md rule 11](CLAUDE.md#the-rules-most-easily-broken) and
[THEME § 4 "The words"](THEME.md#the-words).

**Status.** Sections 1 to 4 have been applied — every string in them now reads
as the "Pick" or "Suggested" column, and the tests that asserted the old
wording were updated with them. One row of section 3 is deliberately left: the
`Deltoid_Backup` folder name, which cannot be renamed without stranding the
files already in the old one. Section 5 is outstanding: the commit and
release-note conventions. The tables in the applied sections are kept as the
record of what changed.

The app's copy is, on the whole, deliberate and better than most. It is
sentence-cased throughout, it states consequences rather than asking "are you
sure", and its empty states explain. What follows is the residue — the places
where the voice slips into casual register, where a sentence stops half-built,
where the same idea is spelled two different ways in two screens, or where an
implementation word has leaked onto the screen.

Findings are graded:

| Grade | Meaning                                                                             |
| ----- | ----------------------------------------------------------------------------------- |
| **1** | Reads as unprofessional to any user. Fix first                                       |
| **2** | Grammatically incomplete, ambiguous, or asks the reader to solve a riddle            |
| **3** | Correct but inconsistent with the same idea stated elsewhere in the app              |

---

## 1. Grade 1 — the register slips · **applied**

| Location | Current | Problem | Suggested |
| -------- | ------- | ------- | --------- |
| [welcome_screen.dart:206](lib/features/welcome/welcome_screen.dart:206) | `Your training sidekick, right in the pocket!` | The first line of the app, and the worst line in it. "Sidekick" is mascot voice; "right in the pocket" is missing its possessive and is not idiomatic either way; the exclamation mark appears nowhere else in the product. A launch screen states what the app is, calmly. | `Your training log, on the phone you already carry.` |
| [supabase_backend.dart:115](lib/data/sync/supabase_backend.dart:115) | `The server refused that: ${e.message}` | "That" has no antecedent by the time the toast is read, and a raw Postgrest message is appended to a colon in a sentence a user is meant to act on. | `Your account could not be reached. ${e.message}` — or drop the raw message and keep the actionable half. |
| [hold_pad.dart:192](lib/features/log/widgets/hold_pad.dart:192) | `Nothing to beat yet` | Gym-bro register in a field that elsewhere says "First time here, with nothing to suggest from". | `No previous hold to compare against` |
| [workouts_screen.dart:1127](lib/features/workouts/workouts_screen.dart:1127) | `Carry on with it` | The stale-session variant of `Resume session`. Two labels for one button, and the casual one is the variant. The button does the same thing in both states. | `Resume session` in both branches. |
| [history_screen.dart:484](lib/features/history/history_screen.dart:484) | `That is everything` | End-of-list marker written as a shrug. | `End of history` |
| [regimes_screen.dart:126](lib/features/regime/regimes_screen.dart:126) | `Nothing else yet. A second split can be built without losing the one you are mid-cycle on.` | "Mid-cycle on" is a dangling preposition on a hyphenated adverb; the sentence is doing two jobs. | `No other regimes yet. You can build a second one without disturbing the cycle you are training.` |
| [adoption_sheet.dart:83](lib/features/account/adoption_sheet.dart:83) | `Merging keeps everything and tidies nothing: days both sides recorded appear twice, and exercises you made yourself can end up listed twice.` | The epigram before the colon is clever rather than clear, and "twice … twice" repeats. This sentence governs an irreversible data decision. | `Merging keeps every record from both sides without removing duplicates. A day recorded on both will appear twice, as will any exercise you created on both.` |
| [progress_sheet.dart:87](lib/core/widgets/progress_sheet.dart:87) | `Packing ${detail} into one file` | "Packing" is warehouse vocabulary for what is elsewhere called an export. | `Writing ${detail} to the backup file` |
| [progress_sheet.dart:90](lib/core/widgets/progress_sheet.dart:90) | `Clearing this device` | Reads as a factory reset during a restore. | `Clearing existing data on this device` |

---

## 2. Grade 2 — half a sentence, or a riddle · **applied**

| Location | Current | Problem | Suggested |
| -------- | ------- | ------- | --------- |
| [log_screen.dart:1154](lib/features/log/log_screen.dart:1154) | `Time?` / `Reps?` | A bare interrogative noun as the keypad's advance label. It is not a sentence, not a fragment that could start one, and not an instruction. | `Enter time` / `Enter reps` |
| [session_summary_screen.dart:177](lib/features/log/session_summary_screen.dart:177) | `How did it go?` | Conversational prompt where every other field label is a noun phrase (`Session note`, `Note for today`). | `Add a session note` |
| [keypad.dart:149](lib/features/log/widgets/keypad.dart:149) | `Last: ${hint}` | Label-colon-value shorthand. Every other reference to the same fact in the app is written out ("Last time", "Last logged", "Last done in …"). | `Last time ${hint}` |
| [regime_screen.dart:146](lib/features/regime/regime_screen.dart:146) | `Add day  +` | A label carrying a glyph as text, with two spaces holding it off. The `+` is either an icon or it is not in the string. | `Add day`, with the affordance drawn rather than typed. |
| [exercise_screen.dart:297](lib/features/regime/exercise_screen.dart:297) | `Tap to name it` | Gesture instruction standing in for a field label, and "it" has no antecedent in the row. | `Not named yet` as the value, with the row's chevron carrying the affordance. |
| [workouts_screen.dart:1067](lib/features/workouts/workouts_screen.dart:1067) | `Left open` | Status badge for a stale session. Reads as a description of a door. The condition is that the session was started on an earlier day. | `Unfinished` |
| [exercise_sheets.dart:271](lib/features/log/widgets/exercise_sheets.dart:271) | `Un-skip` | Coined verb with a hyphen, opposite a well-formed `Mark as skipped`. | `Clear the skip` |
| [regime_screen.dart:375](lib/features/regime/regime_screen.dart:375), [:487](lib/features/regime/regime_screen.dart:487), [:602](lib/features/regime/regime_screen.dart:602), [log_screen.dart:1570](lib/features/log/log_screen.dart:1570), [exercise_sheets.dart:298](lib/features/log/widgets/exercise_sheets.dart:298), [regime_settings.dart:95](lib/features/regime/regime_settings.dart:95) | `Re-order`, `Re-order exercises`, `Re-order days` | "Re-order" hyphenated means to order a second time. The intended word is `Reorder`. Six occurrences, all of them the same mistake. | `Reorder`, `Reorder exercises`, `Reorder days` |
| [regime_screen.dart:401](lib/features/regime/regime_screen.dart:401) | `A rest day, until something is in it. Add an exercise and this becomes a day the cycle expects you to train.` | Opens on a fragment with no subject. | `This day is a rest day until it holds an exercise. Add one and the cycle will expect you to train it.` |
| [volume_history_screen.dart:45](lib/features/workouts/volume_history_screen.dart:45) | `Tick some sets and the weeks land here, one bar each.` | "Land here" is casual and "one bar each" is an appositive with no verb. | `Complete some sets and each week appears here as a bar.` |
| [bodyweight_screen.dart:604](lib/features/settings/bodyweight_screen.dart:604) | `One ${by.noun} with a weigh-in in it. A second one gives it a shape.` | Two fragments, three pronouns, and "in it … it" in one breath. | `Only one ${by.noun} has a weigh-in. A second one is needed before a trend can be drawn.` |
| [history_screen.dart:667](lib/features/history/history_screen.dart:667) | `Nothing in your exercises is called that.` | "In your exercises" is not a place, and "called that" points at a search box the message does not name. | `No exercise matches that search.` |
| [regime_setup.dart:195](lib/features/regime/regime_setup.dart:195) | `Nothing to pick until a regime is deleted` | Sheet subtitle in the full state. The notice below it already states the rule properly; this is the same fact said badly. | `No template can be created while the regime limit is reached` |
| [regimes_screen.dart:326](lib/features/regime/regimes_screen.dart:326) | `Its days and slots go with it` | "Slots" is the schema's word for what the user calls exercises. The confirmation two screens on gets this right (`Its days and exercise slots go with it.`), and neither says "exercises". | `Its days and the exercises in them are deleted too` |
| [settings_screen.dart:523](lib/features/settings/settings_screen.dart:523) | `The account keeps its copy.` | The most consequential row in Settings explains itself in five words with an ambiguous "its". | `Your training stays in your Google account and is removed from this phone.` |
| [pull.dart:181](lib/data/sync/pull.dart:181) | `Some rows from your account did not fit together on this phone. Your training is all here — something in it may look doubled until the next sync.` | "Rows" is a database word; "look doubled" is not a description a user can act on; the em dash bolts two facts together, which THEME § 4 forbids in the app. | `Part of the data from your account could not be reconciled on this phone. Nothing has been lost. Some entries may appear twice until the next sync.` |
| [pull.dart:243](lib/data/sync/pull.dart:243) | `One ${_label(spec.name)} row from your account could not be saved on this phone.` | Same leaked "row". | `One ${_label(spec.name)} entry from your account could not be saved on this phone.` |
| [backup_service.dart:726](lib/data/backup/backup_service.dart:726) | `This backup is incomplete. It says it holds $declared $label and only $landed arrived, so nothing has been restored.` | "It says it holds" personifies the file, and "arrived" is the wrong verb for a local read. | `This backup is incomplete: it records $declared $label but contains only $landed. Nothing has been restored.` |
| [backup_service.dart:831](lib/data/backup/backup_service.dart:831) | `Your history was restored, but part of it did not fit together the way it should. It is worth a look before you train on it.` | "Did not fit together the way it should" describes nothing checkable, and "worth a look" is advice without an object. | `Your history was restored, but some records are inconsistent. Review your recent sessions before training.` |
| [database.dart:201](lib/data/db/database.dart:201) | `The clock this phone stamps your training with could not be saved.` | Stranded preposition on a nine-word subject. The user cannot act on it and cannot parse it. | `The time zone used to date your training could not be saved.` |
| [watch.dart:68](lib/data/db/watch.dart:68) | `Some of this could not be loaded.` | "This" is whatever screen happens to be showing. | `Part of this screen could not be loaded.` |
| [downloads.dart:41](lib/data/backup/downloads.dart:41) | `This build cannot write to Downloads. Use Share instead.` | "This build" is a developer's word for the thing the user is holding. | `Saving to Downloads is not available on this device. Use Share instead.` |
| [sign_in_flow.dart:51](lib/features/account/sign_in_flow.dart:51) | `This build cannot sign in.` | Same leak, and it states a limitation without saying what still works. | `This version of Deltoid cannot sign in. Everything you log stays on this phone.` |
| [sign_in_flow.dart:104](lib/features/account/sign_in_flow.dart:104) | `Getting your training` | Progress title in the bare participial style. Every other progress phase is a full clause. | `Restoring your training` |
| [trend_chart.dart:808](lib/core/widgets/trend_chart.dart:808) | `Pinch to zoom, drag to pan` | Comma splice of two imperatives. | `Pinch to zoom and drag to pan.` |
| [workouts_screen.dart:1121](lib/features/workouts/workouts_screen.dart:1121) | `Finishing it advances $foreignRegime, not $activeRegimeName` | Correct, but the reader has to infer that "advances" means "counts towards the cycle of". | `Finishing it counts towards $foreignRegime, not towards $activeRegimeName.` |
| [log_screen.dart:757](lib/features/log/log_screen.dart:757) | `Session still running. Resume it from Today.` | "Today" is the label of a tab called **Workouts** ([app_shell.dart:102](lib/features/shell/app_shell.dart:102)). The toast names a screen that does not exist under that name. | `Session still running. Resume it from Workouts.` |

---

## 3. Grade 3 — the same idea, spelled two ways · **applied**

| Idea | Spellings in the app | Pick |
| ---- | -------------------- | ---- |
| An unplanned session | `Ad-hoc session` ([history_screen.dart:551](lib/features/history/history_screen.dart:551), [workout_detail_screen.dart:61](lib/features/history/workout_detail_screen.dart:61), [:180](lib/features/history/workout_detail_screen.dart:180), [:279](lib/features/history/workout_detail_screen.dart:279), [session_summary_screen.dart:113](lib/features/log/session_summary_screen.dart:113)) and `Ad-hoc` ([training_repository.dart:1632](lib/data/repositories/training_repository.dart:1632), [:1976](lib/data/repositories/training_repository.dart:1976), [:2193](lib/data/repositories/training_repository.dart:2193)) | Attributive *ad hoc* takes no hyphen. One string, `Unplanned session`, formatted in `lib/domain/` per [RULES § 4](RULES.md#4-code) — it is currently written in the repository layer, which is where a screen's words should never live. |
| The fallback name of an unplanned session | `Ad-hoc session` on five screens, but `Today` in the reorder sheet's subtitle ([log_screen.dart:1571](lib/features/log/log_screen.dart:1571)) and `Ad-hoc` in the repository | One fallback string, used everywhere. |
| Estimated one-rep max | `Est. 1RM` ([exercise_trend.dart:39](lib/features/history/exercise_trend.dart:39)), `est. 1RM` ([:70](lib/features/history/exercise_trend.dart:70)), `Best est. 1RM` ([:79](lib/features/history/exercise_trend.dart:79)), `estimated 1RM` ([exercise_screen.dart:405](lib/features/regime/exercise_screen.dart:405)), `e1RM` ([exercise_sheets.dart:344](lib/features/log/widgets/exercise_sheets.dart:344)) | `Est. 1RM` in a label, `estimated 1RM` in a sentence. `e1RM` is the code's name for it and belongs in Dart, not on a sheet. |
| Bodyweight-plus loading | `Bodyweight +` ([exercise_catalog_screen.dart:230](lib/features/regime/exercise_catalog_screen.dart:230)), `BW + …` ([set_format.dart:34](lib/domain/set_format.dart:34), [:57](lib/domain/set_format.dart:57)), `BW+ lifts` ([bodyweight_screen.dart:182](lib/features/settings/bodyweight_screen.dart:182), [settings_screen.dart:394](lib/features/settings/settings_screen.dart:394)) | `BW +` is defensible in a set row where space is the constraint. `BW+ lifts` in prose is not — write `bodyweight-plus lifts`. |
| The rest alert | Notification title `Rest done` ([workout_notifications.dart:304](lib/core/workout_notifications.dart:304), [:350](lib/core/workout_notifications.dart:350)), in-app `Rest done` ([rest_timer.dart:72](lib/features/log/widgets/rest_timer.dart:72)), channel name `Rest finished` ([:316](lib/core/workout_notifications.dart:316)) | The channel name is what appears in Android's own settings, so the two are read side by side. Use `Rest finished` for both. |
| Towards / toward | `towards` ([workouts_screen.dart:257](lib/features/workouts/workouts_screen.dart:257)), `toward` ([exercise_sheets.dart:344](lib/features/log/widgets/exercise_sheets.dart:344), [enums.dart:168](lib/domain/enums.dart:168)) | `towards`, matching the app's Commonwealth spelling elsewhere. |
| Logging a weight | Sheet action `Log a weight` ([bodyweight_screen.dart:170](lib/features/settings/bodyweight_screen.dart:170)), button `Log bodyweight` ([:187](lib/features/settings/bodyweight_screen.dart:187), [:844](lib/features/settings/bodyweight_screen.dart:844)) | `Log bodyweight` throughout. |
| Ellipsis on a busy state | `Starting…` ([progress_sheet.dart:81](lib/core/widgets/progress_sheet.dart:81)) against `Signing in` ([welcome_screen.dart:224](lib/features/welcome/welcome_screen.dart:224)), `Exporting` ([settings_screen.dart:204](lib/features/settings/settings_screen.dart:204)), `Restoring` ([:351](lib/features/settings/settings_screen.dart:351)), `Holding` ([hold_pad.dart:192](lib/features/log/widgets/hold_pad.dart:192)) | No ellipsis. A spinner already says the thing is running. |
| The Downloads folder | `Deltoid_Backup` ([downloads.dart:7](lib/data/backup/downloads.dart:7)) | Surfaced to the user in `Into $downloadsFolder, where a file manager can …` ([settings_screen.dart:185](lib/features/settings/settings_screen.dart:185)). An underscored identifier read as a sentence. **Left as it is**: `Deltoid Backups` would be the right name, but renaming it strands every backup already written to the old folder, and the app has no way to move them. Worth doing only alongside a migration that does. |

---

## 4. Placeholder text · **applied**

Hint text is not exempt: it is read more often than most labels, because it is
what an empty field shows. These are written as diary entries.

| Location | Current |
| -------- | ------- |
| [workout_detail_screen.dart:254](lib/features/history/workout_detail_screen.dart:254), [session_summary_screen.dart:256](lib/features/log/session_summary_screen.dart:256) | `Slept badly, everything felt heavy` |
| [session_summary_screen.dart:495](lib/features/log/session_summary_screen.dart:495) | `Slept badly, everything felt heavy, the rack was busy…` |
| [workout_detail_screen.dart:488](lib/features/history/workout_detail_screen.dart:488), [session_summary_screen.dart:592](lib/features/log/session_summary_screen.dart:592), [exercise_sheets.dart:226](lib/features/log/widgets/exercise_sheets.dart:226) | `Shoulder felt off, bench was the wide one` |
| [exercise_sheets.dart:435](lib/features/log/widgets/exercise_sheets.dart:435), [:442](lib/features/log/widgets/exercise_sheets.dart:442) | `Felt heavy, elbow tucked, …` |
| [workout_detail_screen.dart:122](lib/features/history/workout_detail_screen.dart:122), [:200](lib/features/history/workout_detail_screen.dart:200) | `How it felt, what got in the way` |
| [exercise_screen.dart:266](lib/features/regime/exercise_screen.dart:266) | `Third set from the pins, no belt` |
| [exercise_screen.dart:421](lib/features/regime/exercise_screen.dart:421) | `Elbows tucked, pause on the chest` |

An exemplar is a legitimate pattern for a free-text field, and these do teach
what the field is for. Three problems were fixed:

1. **Two of them trail into `…`** while the others do not, so the same field
   type is punctuated two ways.
2. **`Felt heavy, elbow tucked, …`** ends on a comma and an ellipsis, which is
   a list that has given up rather than an example.
3. **Six distinct exemplars for four fields that all take the same kind of
   note.** A placeholder is not the place to be inventive; one per field
   *kind* — a session note and an exercise note — is enough.

There are four kinds of note in the app — a session note, an exercise note for
one logged day, an exercise note attached to a programme day, and a permanent
cue — and each now has exactly one exemplar. `Shoulder felt off, bench was the
wide one` also went: "bench was the wide one" is a note to oneself rather than
an example of one.

Note that `Third set from the pins, no belt` and `Elbows tucked, pause on the
chest` sit close to rule 9's line: they are technique cues specific to one
lifter's programme, offered as the app's own examples. They are generic enough
to pass, but they are the shape of thing rule 9 exists to keep out of
`seed_data.dart`, and a placeholder is no different from seed data in that
respect.

---

## 5. Beyond the UI: commits and release notes · outstanding

Rule 11 covers these too, and they need more work than the app does.

**Subjects are declarative aphorisms rather than imperative clauses.** The
convention everywhere else — and the one Conventional Commits assumes — is a
subject that completes "if applied, this commit will …":

| Current | The form the rule asks for |
| ------- | -------------------------- |
| `fix(prefill): a first time in a session is a first time` | `fix(prefill): treat a session's first set as a first time` |
| `fix(progress): a set a quarter stronger is not a trade-off` | `fix(progress): stop scoring a 25% heavier set as a trade-off` |
| `fix(log): a warm-up is not ignored by last-time, whatever the sheet said` | `fix(log): include warm-up sets in the last-time reference` |
| `fix(bars): the status bar's icons are the app's answer, not the launch window's` | `fix(bars): take status-bar icon brightness from the app theme` |
| `docs(claude): the repository went private, and the rule it justified did not` | `docs(claude): keep the no-personal-data rule after going private` |

Each current subject states a *conclusion* the reader can only verify by
opening the diff. The replacement states the *change*, which is the subject
line's job; the conclusion is what the body is for, and these commits have
bodies that say it well.

Two further points:

- **The gitmoji prefixes** (`🔖 ✨ 💄 📝 🐛 🔧`) duplicate the Conventional
  Commits type that follows them, and `💄 fix(log):` and `📝 fix(log):` show
  the two disagreeing. Either the emoji or the type carries the category, not
  both.
- **There are no release notes.** `chore(release): 1.3.0+5` is a version bump
  with no record of what changed for the user. Five releases have shipped
  without one. A `CHANGELOG.md`, written in the user's terms rather than the
  diff's, is the missing artefact rule 11 assumes exists.

---

## 6. What is already right

Recorded so that a later pass does not "fix" it:

- Every destructive confirmation names what happens instead of asking "are you
  sure" — `Its days and exercise slots go with it`, `Any set you did not tick
  is discarded`, `Removes it from history and the heatmap`.
- Empty states explain the mechanism rather than restating the emptiness:
  `Once a session is finished, every movement in it gets its own history here.`
- The unit-switch and load-mode confirmations name both ends of the change, as
  THEME requires.
- Notices state the rule and not its cause: `You can keep up to $identitySlots
  regimes at a time. Delete one to create another.`
- Sentence case is universal, and there is no title case anywhere in `lib/`.
