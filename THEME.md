# Deltoid — design language

The visual system every screen implements. Written after auditing a
best-in-class training app screen by screen on a real device (1080×2400, density
450, `dp = px / 2.8125`); the numbers below are measured, not invented, then
rounded to this app's scale. Colours are sampled pixels.

This is a **language, not a feature list.** Nothing here says to add a screen, a
chart or a concept Deltoid does not already have. Read
[README.md](README.md) → *Non-goals* before turning any pattern into a feature.

---

## 0. Scope

The reference app is a full commercial product with a team behind it: exercise
video libraries, muscle-map rendering, smart progression, gym equipment
profiles, supersets, programme marketplaces, cloud sync, subscriptions. **We are
not rebuilding any of that.** Deltoid is one person's training log and stays
one person's training log — four tabs, offline, no accounts.

What we take is the *language*: the greys, the type scale, the component
vocabulary, the way a row is built, the way a sheet asks a question. What we
build with it is our own app, at our own scope.

So, concretely:

| Deltoid has | Gets the language for |
| --- | --- |
| Today | Header band, hero card, primary button, section headers |
| Log (`PageView`, one exercise per page) | §6 — set rows, index chips, keypad, plate view, swipe delete |
| History + workout detail | §8 — date groups, identity tiles, expandable exercise rows |
| Progress (one exercise, one chart) | §5 charts — dashed gridlines, right-hand Y, range pill |
| Regime (sessions, catalog, deload) | §7 — day tabs, count-as-heading, targets card, target sheet |
| Settings, bodyweight, backup | §5 list cards, toggles, sheets |

**Not building, at any point, because we have no such concept:** exercise videos
or photos (a monogram tile stands in), muscle maps, smart/auto progression,
supersets, equipment profiles, programme sharing or import, levels, steps,
nutrition, accounts. Where a pattern in this document depends on one of those,
the pattern is recorded for its *shape* only — see §7's targets card, which we
render once instead of once per planned week.

If applying something here would require a new feature, the answer is no: check
the README's **Non-goals**, then style what we already have.

---

## 1. The six rules

Everything below follows from these. When a decision isn't covered, decide by
these.

1. **Chrome is monochrome. Colour is data.** Buttons, chips, nav, headers,
   selection states — white, black and grey. Hue is reserved for things that
   *mean* something: a chart series, a PR badge, an RIR rating, a deload, a
   destructive action. A blue button and a blue chart line in one screen make
   the button look like data and the data look tappable.
2. **Depth is surface colour, not decoration.** Two greys and a hairline. No
   card borders, no drop shadows, no gradients, no glows.
3. **One primary action per screen, and it is white.** Everything else is a grey
   pill or an underlined text link.
4. **Zero states print dashes, not zeros.** `—— kg`, `-- sets`. A real 0 is a
   measurement; a dash is "nothing here yet". Never fabricate a number.
5. **Every value has a unit, and the unit is smaller than the value.** `87` in
   the value size, `kg` one step down in grey.
6. **Say it once.** A fact appears in exactly one place on a screen. This is the
   rule this app breaks most often and the one that costs it the most: Today
   drew the cycle as labelled bars in the hero *and* as a list underneath *and*
   as a fraction in a section header — three renderings of one number, which is
   what pushed the consistency grid off the bottom of the screen.

   When the same fact appears twice, one of the two is **deleted** — not shrunk,
   not moved somewhere quieter:

   - The screen's subject is named once. A card inside a screen called Today
     does not also say "today". A row inside a section called Consistency does
     not repeat "consistency".
   - A number gets one representation. A bar *or* a count, not both. Where a
     graphic and a figure say the same thing, the graphic stays only if it says
     it faster.
   - A control states its own action once. A row that opens an editor does not
     need a chevron *and* an "Edit" label *and* a tap hint.
   - Repetition *down* a list is not duplication: six rows each showing their
     own set count is a column. Repetition *across levels* is — a total in the
     header and the same total again in the last row.

   The reason is not tidiness. What survives has to be readable at a glance,
   mid-set, with a bar in your hands. Every duplicated element is one more thing
   to read before the screen answers the question it was opened for.

---

## 2. Colour

Sampled from the reference build. Pure neutrals — no blue tint in the greys, which
is the single biggest thing that separates "designed" from "themed".

### Dark (primary)

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#131313` | Page background |
| `surface` | `#1F1F1F` | Cards, app bar, nav bar, sheets, header bands |
| `surfaceHigh` | `#2B2B2B` | Chips, secondary buttons, circular icon buttons, input fills |
| `surfaceHighest` | `#3A3A3A` | Focused input fill, pressed chip, keypad utility keys |
| `surfaceSunken` | `#0E0E0E` | Keypad bed, wells under a scrolling list |
| `border` | `#2E2E2E` | Inset dividers inside a card; outlined empty-state boxes. **Not** card outlines |
| `textPrimary` | `#FFFFFF` | Titles, values, active labels |
| `textSecondary` | `#9A9A9A` | Subtitles, captions, units, inactive nav |
| `textTertiary` | `#6E6E6E` | Chevrons, disabled, placeholder |
| `accent` | `#FFFFFF` | Primary action fill, selected chip fill, active tab underline |
| `onAccent` | `#121212` | Label on `accent` |

### Data / semantic — the only hues

| Token | Hex | Use |
| --- | --- | --- |
| `data` | `#5EC8D8` | Default chart series, sparklines |
| `positive` | `#5DBA87` | Success, completed, "you beat last time" |
| `deload` | `#FFD15E` | Deload identity, caution |
| `negative` | `#F83446` | Destructive fill, delete swipe panel |
| `info` | `#2F7BFF` | Second series, heatmap ramp, identity tiles |
| `series[]` | `#5EC8D8 · #2F7BFF · #FFD15E · #5DBA87 · #B98CFF` | Categorical, in order |

**RIR / effort scale** (a diverging ramp, used only on effort ratings):
`0–1 #F83446` · `2–3 #FFAA33` · `4–5 #5DBA87` · `6+ #2F7BFF` · unknown `#3A3A3A`.

### Light

Mirror by inverting the neutral ramp, not by tinting:
`bg #F4F4F4` · `surface #FFFFFF` · `surfaceHigh #EDEDED` · `surfaceHighest #E0E0E0`
· `border #E4E4E4` · text `#111111 / #5F5F5F / #8C8C8C` · `accent #111111`
(black buttons, white labels). Data colours darken:
`data #0E8FA6` · `positive #12855F` · `deload #B07206` · `negative #C33A2E` ·
`info #2563EB`.

---

## 3. Type

One family, five roles. Measured cap heights converted to sp and rounded.
**Minimum 11sp. Maximum 28sp.** Nothing on any screen is bigger than a page
title or smaller than a nav label.

| Role | Size / line | Weight | Case | Colour | Used for |
| --- | --- | --- | --- | --- | --- |
| `pageTitle` | 27 / 32 | 800 | **UPPERCASE**, tracking −0.5 | primary | The one title in a header band: `TODAY`, `HISTORY` |
| `pageEyebrow` | 13 / 16 | 600 | UPPERCASE, tracking +1.2 | secondary | Date line above a page title |
| `section` | 20 / 26 | 700 | Sentence | primary | Section headings on the page background |
| `title` | 16 / 22 | 600 | Sentence | primary | Card titles, list-row titles, exercise names |
| `body` | 14 / 20 | 400 | Sentence | secondary | Subtitles, descriptions, captions |
| `value` | 22 / 26 | 700 | — tabular | primary | The number a card is about |
| `valueSm` | 16 / 20 | 600 | — tabular | primary | Set-row fields, inline stats |
| `label` | 13 / 16 | 500 | Sentence | secondary | Table headers, chip labels, axis labels |
| `micro` | 11 / 14 | 600 | Sentence | secondary | Nav labels, units, badge text |

Rules:

- **Tabular figures on every number that can change.** Weights, reps, timers,
  dates, counts.
- Units are `body` beside a `value`, never the same size.
- Uppercase appears in exactly two places: the page title and the page eyebrow.
  Uppercase micro-labels scattered over a page (`LAST SESSION`, `THIS CYCLE`)
  are what makes a screen look like a template — use `section` instead.
- Titles never wrap past 2 lines; ellipsize.

---

## 4. Space, radius, motion

**Spacing** — 4pt scale: `2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40`.
Page gutter **16**. Card padding **16** (dense rows 12). Gap between a section
header and its content **12**. Gap between sections **28**. Row height 56–72
depending on whether it has a subtitle.

**Radius** — cards **20**, buttons and fields **14**, chips and pills **999**,
identity tiles **30% of tile size**, heat cells **4**.

**Elevation** — none. Ever. Surface colour only.

**Motion** — 140ms micro (press), 220ms standard (state, layout), 340ms
transitions. Easing `easeOutCubic`; `easeOutQuint` for anything travelling a
distance. Press feedback is a scale to 0.97 plus a dim to 0.86 — never an ink
ripple, which on charcoal is either invisible or a grey smear.

---

## 5. Components

### Buttons

| Kind | Spec |
| --- | --- |
| **Primary** | Full-width, height 54, radius 14, `accent` fill, `onAccent` label at `title` weight 600. One per screen. Pinned to the bottom when it ends a flow ("Complete Workout"). |
| **Secondary** | Same metrics, `surfaceHigh` fill, primary label, no border. |
| **Destructive** | `negative` fill, white label. Only inside a confirmation, never on a page. |
| **Text link** | Label in `title` size, **underlined**, primary colour — not accent-coloured. This is the "See all / Collapse / See 215 more" affordance. |
| **Circular icon** | 40dp `surfaceHigh` circle, white glyph at 18. Used for add / close / refresh. |
| **Compact pill** | Height 36, radius 999, `surfaceHigh`, `label` text. "Edit", "Change". |

Disabled = `surfaceHigh` fill with `textTertiary` label. Never a faded accent.

### Chips (filter / action)

Height 44, radius 999, icon 16 + gap 8 + `label`.
Unselected `surfaceHigh` + primary text. **Selected `accent` fill + `onAccent`
text.** A trailing caret ⌄ means it opens a picker; a chip with no caret is a
toggle. Rows of chips scroll horizontally and bleed off the right edge — the
clipped chip is the scroll affordance.

### Cards

`surface` fill, radius 20, **no border, no shadow**, padding 16. A card is a
grouping device, not a frame: a page of 6 cards has no hierarchy. Prefer one
card holding rows over 6 cards holding one row each.

### List card + rows

The workhorse. One `surface` card; rows inside it; **inset hairline dividers**
that start at the text, not at the card edge; last row has none.

```
[ icon 24 ]  Title                      [ trailing ]
   ↑ 16      Subtitle (body, optional)      ↑ chevron / switch / value
```

Row 56 tall (72 with a subtitle). Leading icon is a **bare white glyph** — a
coloured rounded-square tile is reserved for an *identity* (a programme, a
saved workout), never for decoration. Trailing chevron `textTertiary` at 18.

### Section header

`section` type on the page background — no card, no uppercase. Optional trailing
**underlined text link**, vertically centred with the title. 12 below it.

### Toggles, radios, checkboxes

- **Switch** — on: `accent` track, `#121212` knob. Off: `surfaceHighest` track,
  `textSecondary` knob. No accent hue.
- **Radio** — selected: filled white disc with a dark dot. Unselected: 2px
  `textTertiary` ring.
- **Checkbox** — 26 square, radius 6. Checked: white fill, dark tick.
  Unchecked: 2px `textSecondary` outline, transparent.

### Sheets (the default for any choice)

`surface`, top radius 24, drag handle 36×4 `#4A4A4A`. Header row: **✕ on the
left, bold `title` centred**, full-width hairline under it. Then rows.

Every sheet is titled *and* subtitled. Two sheets that both list session names
are indistinguishable without one line saying which question is being asked.

A picker sheet lists options as `title` + `body` description + trailing radio.

### Dialogs (confirmations)

Bottom-anchored card, not a centred alert. `surface`, radius 24, padding 20.

```
Title (section, bold)                    ✕
Body — what actually happens, in one sentence. (body)

[      Destructive / primary button      ]   ← full width
              Go Back                        ← plain centred text button
```

Never two equal-weight text buttons in a row. The safe option is the quiet one,
the dangerous one is the loud one, and the copy says what happens rather than
"are you sure".

### Empty states

Outlined box: 1px `border`, radius 16, padding 20, muted glyph left, `body` text
explaining what will appear here and what to do. Dashed border when the box is a
drop target. Full-page empty states get the icon centred above `section` title +
`body` message + one primary button.

### Stat tile (2-up grid)

`surface` card: `title` (ellipsized to 1 line) → `body` window caption
("Last 7 workouts") → sparkline → hairline → `value` + unit + chevron.
Zero state keeps the whole layout and prints `——` where the value goes: the grid
stays a grid.

### Charts

- Dashed horizontal gridlines only, `border`; **no vertical gridlines, no chart
  border**.
- Y labels on the **right**, `label` size, `textSecondary`. X labels below the
  baseline.
- Series: `data` line 2px with open circle markers (fill `bg`, stroke series
  colour). Sparklines drop the axes entirely.
- Above the plot: two stats as `label` + `value` + unit, then the date range in
  `body`.
- Below the plot: range selector as a segmented pill — `surfaceHigh` track,
  **white pill** behind the active range, `label` text. A separate small
  `surfaceHigh` pill with a caret for granularity.
- Legend: chips inside a `surface` card, marker + label; disabled series dim to
  `textSecondary`.

### Badges

- **PR / record** — icon + value inline in `label` size, in `positive`.
- **RIR** — a filled circle from the RIR ramp, 26dp, overlapping the
  bottom-right corner of the field it belongs to.
- **Status pill** — radius 999, tint at 14% alpha of the semantic colour,
  text in that colour at `micro`.

### Bottom navigation

`surface` bar, 1px top hairline, height 62 + safe area. Selected: white icon +
white `micro` label at weight 700. Unselected: `textSecondary` both. **No pill,
no indicator, no accent hue** — weight and brightness carry the state.

---

## 6. The logging screen

Deltoid's log is a `PageView`, one exercise per page (README rule — nothing
inside it may use a horizontal gesture). The language for what's *on* the page:

**Top bar** — hamburger, elapsed clock in `value` tabular, rest timer icon +
countdown, then a thin progress track.

**Exercise rail** — 60×84 thumbnails, radius 12, with a 3px underline beneath:
white for the current exercise, `surfaceHighest` for the rest. A finished
exercise gets a white circular tick badge on its thumbnail corner.

**Header** — exercise name in `section` (max 2 lines), `Set 2 of 4` in `body`
under it, and a load summary pill on the right.

**Action chips** — the horizontally scrolling chip row described above.

**Set table** — a header row of `label` columns (`Set · Last time · kg · Reps ·
✓`), then one row per set:

| Element | Spec |
| --- | --- |
| Index chip | 40dp `surfaceHigh` circle, `valueSm`. **Warm-up shows `W`, drop set shows `D`** — a letter, not a colour, and warm-ups are excluded from the "Set n of m" count. |
| Prefill | `body` in `textSecondary`, or `No target` when there is none. Deltoid's session-scoped prefill line goes here, including its "From Push 2 · 12 Jul" attribution. |
| Value field | `surfaceHigh` fill, radius 12, height 48, centred `valueSm`. Focused: transparent fill + 2px white outline. |
| Done | Checkbox as specced. |
| Completed row | Values and index dim to `textSecondary`; the checkbox goes solid white. The row is *not* struck through or recoloured. |
| Delete | Swipe left reveals a full-height `negative` panel flush to the screen edge with a white glyph. No trailing delete button in the row. |
| Add set | A circular `surfaceHigh` + button in the index column, below the last row. |
| Drop set | Renders as sub-rows nested under its parent `D` row, each with its own fields and its own `+` in the index column. |

**Finish** — when every set is ticked, a white primary button appears pinned at
the bottom. It does not exist before that.

**Numeric keypad** — `surfaceSunken` bed. Digits are bare white `24sp` glyphs
with no key background; utility keys (`RIR`, keyboard, ±, backspace) are
`surfaceHigh` rounded rects; the confirm/advance key is white with a dark glyph.
Above the digits sits the effort strip (the RIR circles) and, for a barbell
lift, the **plate view**: a small bar diagram with coloured plate slabs, a
legend of `count × plate`, and one plain sentence —
`10 kg on both sides + 20 kg bar weight = 40 kg`.

---

## 7. Making things (regimes, sessions, exercises)

The reference app runs creation as a multi-screen wizard: illustrated intro, a
progress bar, one question per screen. **Deltoid does not do that.** This is a
personal tool for one person who already knows their split; an onboarding funnel
in front of "add a session" is ceremony, and every screen of it is a screen to
maintain. Creation here stays what it is today — a sheet, or one screen.

What is worth taking from it, and where it goes:

**Choice cards** — for the two or three genuinely branching decisions we have
("start from a template or from scratch"). `surface` fill, radius 16, 1px
`border`, padding 16: icon left (28, white), title in `title`, one line of
`body` saying what it means, radio right. **Selected state is a 2px white
border, not a fill change** — the card stays readable and the set stays
scannable. Stacked in a sheet, not spread over screens.

**Disabled primary** — a creation sheet's confirm button is `surfaceHigh` with a
`textTertiary` label until the form is valid. Never a faded accent, and never an
enabled button that shows an error when tapped.

**Naming** — a single text field in a sheet, `surfaceSunken` fill, focused with
a 2px white outline, with the confirm button directly under it. No screen push
for one string.

### The programme editor

The closest thing to our Regime screen, and the pattern is worth taking whole:

- **App bar** — back, programme name as `title`, a sliders glyph on the right for
  programme-level settings.
- **Day tabs** — one scrollable tab per training day (`Workout A`, `Workout B`…),
  white 3px underline under the active one, `title` labels, grey when inactive.
  This is our sessions-in-a-regime, and it beats a vertical list: the day is a
  context you switch, not an item you scroll past.
- **Action chip row** under the tabs — `Rename`, `Re-order`, and a picker chip
  with a caret. Chips, not an overflow menu: these are the three things you
  actually do to a training day.
- **Count as heading** — the exercise section is headed `7 Exercises`, not
  "Exercises". The number is the useful part. Trailing underlined link
  `Add exercises`.
- **Exercise block** — thumbnail, name in `title`, muscle chips underneath, `⋮`
  overflow on the right; below it, the targets. Blocks are separated by
  full-width hairlines, not by cards.
- **Targets** — they render one card per planned week, scrolling horizontally,
  each listing set rows as `index chip · 8–10 reps · RIR badge`.

**We do not do the week cards.** Deltoid has no periodised plan and no smart
progression: a slot has target sets and a rep range, and what actually happens
is decided at the bar by session-scoped prefill. So the block carries **one**
targets card — `4 × 8–10`, editable — and the horizontal axis stays free. The
set-row shape inside it (index chip, range, optional badge) is the same.

This is confirmed by their own build-from-scratch path: with progression off,
the horizontally scrolling week cards collapse to exactly one card
(`7 Cycles` → `1 Standard Set`). The multi-card layout is a consequence of
periodisation, not of good design — so a single card is not us cutting a corner,
it is the same design with our data in it.

**Target editor** — a sheet, not a screen. Header `✕ · exercise name + scope
subtitle`, then a small table with `label` column headers
(`Set · Reps min · Reps max · RIR`), one row per set: index chip, two
`surfaceHigh` fields whose placeholder is the literal word `Optional`, trailing
badge. A circular `+` below the last row adds a set. Under the table, toggle
rows (title + one line of `body` + switch). Bottom: white **Save**, with a plain
centred text button beneath it for the rarely-used extras.

**Day tabs end with an `Add Day +` tab** — creating the next training day is the
last tab rather than a floating button. A day with no exercises is a rest day
and says so in an empty-state box; adding an exercise converts it.

**Identity: colour + glyph.** A programme picks one of ~7 colours and one glyph;
that pair then marks it everywhere — the card tile, history rows, the day tabs.
Cheap to build, and it is most of why their history list scans so well. Worth
adopting for our regimes: `Regime.colorIndex` + `Regime.glyph`, chosen in the
create sheet, rendered through `IconTile`.

**Two-button footers** — when a screen genuinely ends in two actions, stack
them: secondary (`surfaceHigh`) above, primary (white) below, both full width.
Never side by side.

Rules for any creation surface:

- One question per sheet. If a second question is genuinely required, it is a
  second sheet, not a wizard step with a progress bar.
- No illustrated intro screens, no progress bars, no "we will build you a plan"
  framing. The user is the planner.
- The sheet says what it will make, in its subtitle, before it asks anything.

---

## 8. History and detail screens

**History list** — no cards. Date group header in `section` on the page
background, then entries: identity tile (colour-coded rounded square) + session
name in `title` + programme name in `body` + a one-line ellipsized exercise list
+ a row of muscle chips that clips at the right edge + chevron.

**Workout detail** — full-bleed rows, edge-to-edge dividers, one row per
exercise: thumbnail, name in `title`, summary lines in `body`, PR badges inline,
caret. Expanding reveals set rows: index chip + `60 kg × 8` in `valueSm`, inset
dividers.

**Exercise detail** — tab bar with a white underline for the active tab, then
the chart block from §5, then month-grouped list cards of past performances
(`value` + date in `body` + chevron).

---

## 9. Where we deviate

The goal is a peer, not a clone. Same level of craft, our own product. These are
deliberate departures — keep them when implementing.

| They do | We do | Why |
| --- | --- | --- |
| Wizard for creation | Sheets (§7) | One user, who already knows their split |
| 5 tabs + a centre FAB that repeats what the tabs do | 4 tabs, no FAB | The action lives on Today, where the decision is |
| Empty charts render full axes and gridlines over blank space | No data → no axes; a short empty card that says what will appear here | A gridded void reads as a broken chart, not an empty one |
| Dashboard fills with `-- sets` cards for metrics never used | Dashes inside a card that has a reason to exist; whole sections hide until they have data | Rule 4 is about honesty, not about padding a page |
| 2-up stat tiles ellipsize to `45° Cable Rear…` | Two lines before ellipsis in grid tiles | A truncated exercise name is not an identifier |
| Muscle chips hard-clip mid-word at the screen edge | Fade the overflow edge | Clipping looks like a layout bug; a fade looks like a scroll |
| Warm-up-only exercise reads `Set 0 of 0` | `Warm-up only`, and the count appears when a working set does | A zero pair is a bug face |
| No deload concept | Deload is `deload` amber everywhere it touches — cycle, heatmap, resume card, history row | It is the one thing our cycle model has that theirs doesn't; it must be legible at a glance |
| Prefill is "previous", per exercise | Prefill is session-scoped and says so out loud when it borrows: `From Push 2 · 12 Jul` | The entire reason this app exists (README) |
| Programme identity is a colour + glyph you must pick during creation | Same mark, but auto-assigned on create and changeable later | Identity is worth having; a mandatory question about it is not |
| Rep targets hidden two taps deep behind a card, placeholder `Optional` | Same sheet, but the card shows the target inline (`4 × 8–10`) so it is readable without opening | The target is the point of the slot |

---

## 10. Mapping to this codebase

| Where | Change |
| --- | --- |
| `lib/core/theme/tokens.dart` | Replace the blue-tinted greys with the neutral ramp; `accent` becomes white/black; add `info`; drop the shadow token and `Shadows` helpers. |
| `lib/core/theme/theme.dart` | Rebuild the type scale to §3; `FilledButton` white; remove `dialogTheme` centring in favour of the bottom-anchored confirm; switch/checkbox/radio themes per §5. |
| `lib/core/widgets/primitives.dart` | `AppCard` loses its border and shadow; `SectionHeader` action becomes an underlined link; add `ListCard` + `AppRow`, `SegmentedPill`, `FilterChip`, `ConfirmSheet`; `Pill` stays for status only. |
| `lib/features/shell/app_shell.dart` | Drop the accent pill behind the active tab; white/grey weight shift instead. |
| Today | Header band, monochrome hero, white Start button, dashes in the consistency line when there is no honest rate. |
| Log | Set-row spec in §6 — `W`/`D` index letters, swipe-to-delete, focused-field outline, pinned finish button. |
| History | Rebuild per §7 — this screen is the furthest from the language today. |
| Progress | Chart spec in §5 — right-hand Y labels, dashed gridlines, segmented range pill. |

Order of work: tokens → theme → primitives → shell → one screen at a time,
`flutter analyze && flutter test` after each.
