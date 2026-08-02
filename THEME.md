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
   pill or a quiet text link.
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

**Six hues and a red — `orange #FF8B66` · `blue #689FFA` · `yellow #FDD35F` ·
`green #5DBA86` · `lavender #BE8CFF` · `cyan #77D4E3`, plus `red #F83446`.**
Named on `DeltoidColors` and referenced by name. Never write a hex at a call
site: a chart series, a regime's mark and the deload orange have to be the same
tones wherever they appear, not near-misses picked one screen at a time.

**The same six in both themes**, as the reference app does it. An identity mark
is the same mark whichever theme it is drawn in, and a colour that changes with
the phone's setting is one you have to learn twice.

These are the original six, returned to after a full loop, and the loop is the
lesson. They were replaced by a saturated set (`#FF6535`, `#F9AC0E` …) that read
as shouting on the device; then by a set solved for equal contrast on charcoal,
which did make the weights even and turned yellow into `#A0812B` — an ochre. A
number satisfying a constraint is not a yellow. Sampling the reference app's own
charts landed within a few points of this six on every hue.

So: **a hue has to stay the hue.** Evenness is worth solving for only where it
does not cost that. These run 7.0:1 to 13.0:1 on `bg` — a wider spread than the
solved set, and the right trade, because yellow is bright because yellow is
bright.

What previously forced a second, darker set for the light theme was a **white**
glyph on the fill, which these are far too light to carry (1.4:1 on yellow). The
glyph is derived from the fill now, so the fills are free to be light.

The cost, stated plainly: on a white card `yellow` is 1.4:1 and `cyan` 1.7:1. On
the light theme the six are **fills and marks — never text, never a hairline.**
Where a hue must carry text on both themes, use `textPrimary` and let the hue be
the shape behind it.

Red is deliberately not in the six. `negative` and the failure end of the effort
ramp are the one signal that must never be read as information, so it stays out
of the palette everything else draws from — and it is allowed to shout where the
six are not.

**A filled mark's glyph is the fill's own hue, taken down.** Not white, not
black — `#FF8B66` carries `#9E2600`, `#5DBA86` carries `#275C3E`. A tile is one
colour with a shape cut out of it, and a white or black shape makes it two.

`IconTile` solves for it: same hue, same saturation, lightness walked down until
the glyph clears **3.2:1 against its own fill**, which lands every tile at
3.24–3.35:1. A fixed multiplier was tried and ranges 2.9–3.7
depending on where the hue sits — the uneven-set problem again, one level down.
White was the rule before that and measured 1.9:1 on the old yellow.

A palette is therefore only ever a list of fills. Nothing about a glyph is
attached to it, and a hue retuned later cannot break its own mark.

**Identity marks live on the Regimes screen and nowhere else.** The tile on a
Today card or a History row is `heatOn` blue for a session and `deload` orange
for a light week — the regime's own hue was there once, and it made the one
distinction those screens exist to show invisible on the orange regime and
indistinguishable from a mark on every other one. Which programme a workout
belongs to is said in words; whether it was a deload is only ever said by the
tile.

| Token | Hex | Use |
| --- | --- | --- |
| `data` | `cyan #77D4E3` | Default chart series, sparklines |
| `positive` | `green #5DBA86` | Success, completed, "you beat last time" |
| `deload` | `orange #FF8B66` | Deload identity |
| `warning` | `yellow #FDD35F` | Stated limit or consequence (`NoticeBox`) |
| `negative` | `red #F83446` | Destructive fill, delete swipe panel |
| `info` | `blue #689FFA` | Second series, heatmap ramp, session tiles |
| `series[]` | `cyan · blue · yellow · green · lavender` | Categorical, in order |
| `identity[]` | the six, in order | Regime marks, on the Regimes screen only |
| `heatOn` | `blue #689FFA` | A day you trained; the session tile |

**RIR / effort scale** (a diverging ramp, used only on effort ratings):
`0–1 #F83446` · `2–3 orange` · `4–5 green` · `6+ blue` · unknown `#3A3A3A`.

### Light

Mirror by inverting the neutral ramp, not by tinting:
`bg #F4F4F4` · `surface #FFFFFF` · `surfaceHigh #EDEDED` · `surfaceHighest #E0E0E0`
· `border #E4E4E4` · text `#111111 / #5F5F5F / #8C8C8C` · `accent #111111`
(black buttons, white labels). Data colours darken, and **do not take the six
hues**: they are tuned for charcoal, and `#FDD35F` on white is not a colour, it
is a smudge. `data #0E8FA6` · `positive #12855F` · `deload #B07206` ·
`negative #C33A2E` · `info #2563EB`.

---

## 3. Type

One family, five roles. Measured cap heights converted to sp and rounded.
**Minimum 11sp. Maximum 30sp.** Nothing on any screen is bigger than a page
title or smaller than a nav label.

| Role | Size / line | Weight | Case | Colour | Used for |
| --- | --- | --- | --- | --- | --- |
| `pageTitle` | 30 / 36 | 800 | Sentence, tracking −0.5 | primary | The one title in a header band, and it **names the screen**: `History`, `Workouts`, `Settings` |
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

Above a page title, **12 only when something small sits on top of it** — an
eyebrow, or a row of buttons. A title that is itself the first line under the
status bar takes **24**: at 12, thirty points of uppercase start hard against
the notch and the header band reads as part of the system bar rather than as
the top of the page.

**Radius** — cards **20**, buttons and fields **14**, chips and pills **999**,
identity tiles **30% of tile size**, heat cells **4**.

**Elevation** — none. Ever. Surface colour only.

**Motion** — 140ms micro (press), 220ms standard (state, layout), 340ms
transitions. Easing `easeOutCubic`; `easeOutQuint` for anything travelling a
distance.

**Press feedback is a scale to 0.97 plus a dim to 0.86 — except on a row.**
Scale reads on a card, a chip or a button because the whole shape travels. On a
full-width row against an identical row above it, 1% of scale is invisible, and
a list that does not answer the finger makes the whole app feel a frame behind.
So rows and nav destinations get **ink** (`InkRow`), and nothing else does:
`splashFactory` stays `NoSplash` app-wide and the ripple is asked for
explicitly. It is white at 10% rather than Material's `onSurface` at 12%, which
on `#1F1F1F` is the grey smear this rule used to ban outright.

**A ripple is a circle, and it is the only press state.** The nav bar's ink was
briefly a rectangle sized to the whole bar, and it looked like what it was: a
lit box a cell and a half wide with a hard edge, sitting behind the labels —
which is the pill `No pill, no indicator` rules out, arriving by accident. Two
rules came out of it:

- `highlightShape` is **never** `rectangle` on a bare surface. A highlight is a
  filled shape held for as long as the finger is down, and on anything that is
  not already a bounded row it draws an edge nobody asked for.
- **No highlight under a splash.** The ripple is the press state; a highlight
  beneath it is a second shape doing the same job, and it is the one that
  leaves the edge. `highlightColor: transparent` on the nav.

A row is the exception, and only because a row *is* a rectangle: `InkRow` keeps
a faint one because the shape it fills is the shape you pressed.

**The ripple is `InkSparkle`** — the Android 12 one: a soft radial wash bounded
to the thing you pressed, falling off at its edges rather than stopping at
them, and it **plays to completion** after the finger has gone, so changing tab
does not cut the bar's own feedback short. `InkRipple`'s hard circle was honest
and read as a blob under the icon.

**Scrolling is damped, everywhere.** `AppScrollBehavior` puts
`BouncingScrollPhysics` on every list on every platform and drops the
overscroll glow with it. Android's clamping physics stops a list dead at the end
of its content and leaves a stretch indicator to say so; a list that visibly
resists has already said it, and this is an app scrolled one-handed with a bar
in the other.

**Anything with a height animates to it.** A fold that arrives in one frame
reads as the widget being replaced rather than as this one opening — every
expand/collapse is an `AnimatedSize` on `easeOutQuint`, and every chevron that
marks one is an `AnimatedRotation` rather than two glyphs swapped.

**A reload never blanks what is on screen.** `skipLoadingOnReload` on every
paged view: a write anywhere in history invalidates the feed, and the list you
are reading must not vanish for a spinner because you ticked a set two screens
away.

---

## 5. Components

### Buttons

| Kind | Spec |
| --- | --- |
| **Primary** | Full-width, height 54, radius 14, `accent` fill, `onAccent` label at `title` weight 600. One per screen. Pinned to the bottom when it ends a flow ("Complete Workout"). |
| **Secondary** | Same metrics, `surfaceHigh` fill, primary label, no border. |
| **Destructive** | `negative` fill, white label. Only inside a confirmation, never on a page. |
| **Text link** | Label in `title` size, primary colour, **no underline**, followed by an 18dp chevron. This is the "See all / Collapse / See 215 more" affordance. A rule under a word is the one decoration that has to be perfectly consistent to read as anything but a mistake, and it never was — so there are none. |
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
**text link** *or* one small figure (a month's session count), vertically
centred with the title. 12 below it, and **28 between one section and the
next** — `Space.section`, not "about 24".

**Every heading on a page background is `SectionHeader`.** Not a `Row` of
`headlineSmall` that happens to look like one: History's month headings were
hand-rolled for exactly as long as it took their padding to drift off every
other heading in the app. If a heading needs something on its right that is not
a link, it gets a `trailing` slot — it does not get rebuilt.

**A heading is one line. There is no subtitle.** Two of them had one and the
cost was the same both times: `Consistency` and `Regime library` started their
content 20pt lower than the headings above them, so no two sections on a page
began at the same distance from what they head. The sentence goes **inside the
card**, under the thing it describes — the consistency figures now sit beneath
the grid they count, which is also where they are read. A figure that belongs
to the heading itself (a month's, a year's session count) goes in `trailing`,
on the title's line.

**A section's rows sit in a `ListCard`.** The card's edge lands 12 under the
heading; full-bleed rows put the first line of text 28 under it with nothing in
between, so a page mixing the two has sections that visibly start at different
heights — which is what made `Active regime` look wrong next to `Movements`.
Full-bleed rows are for a screen that is *nothing but* rows under date
headings (History §8), never for one section of a page.

### Toggles, radios, checkboxes

- **Switch** — on: `accent` track, `#121212` knob. Off: `surfaceHighest` track,
  `textSecondary` knob. No accent hue.
- **Radio** — selected: filled white disc with a dark dot. Unselected: 2px
  `textTertiary` ring. Built as `AppRadio`, and it is the trailing control of
  an [AppRow] — one choice per row. Reach for it over a [SegmentedPill] when
  the choice needs room to say what it means; the pill is for a control that
  governs the page under it.
- **Checkbox** — 26 square, radius 6. Checked: white fill, dark tick.
  Unchecked: 2px `textSecondary` outline, transparent.

### Sheets (the default for any choice)

`surface`, top radius 24, drag handle 36×4 `#4A4A4A`. Header row: **bold `title`
centred, ✕ on the right** in a 48 tap target, full-width hairline under it.
Then rows.

The ✕ is on the right, not the left, and bigger than a row's glyph: it is the
only control on the sheet that is not one of the choices, and on the left it
read as the first item in the list. It sits on the **title's line**, not
centred in the title-and-subtitle block — it closes the sheet, and a two-line
header dragged it down beside a subtitle it has nothing to do with.

The handle is ours, not the framework's: `showDragHandle: false` on every sheet
that uses `AppSheet`, which draws the bar itself, 8 down from the top. The
title then sits in equal air: 16 above it, 16 below, then the hairline.
Material's handle reserves a 48pt interactive box and left an inch of empty
charcoal over every title.

The subtitle **identifies, or it is not there**. One short `body` line naming
*which* thing is being edited — the date under a session name, the exercise
under `Set 2` — and it never wraps. It is not a place to state scope or explain
the sheet: "This workout only" under a title that is already an exercise name
says nothing the rows underneath don't say better, and it is exactly the
duplication rule 6 exists to stop. A sheet whose title already names the thing
goes without one — and so does a sheet opened from a screen that is *already*
about that thing: the set sheet does not need "Back Squat" under it when the
exercise's name is the biggest text on the page behind it. Two sheets that both list session names are indistinguishable without one
line saying which question is being asked.

Rows in a sheet are **full-bleed `AppRow`s, never a `ListCard`** — a card inside
a sheet is a panel inside a panel, and the sheet's gutter then insets rows that
already carry their own padding. **No rules between them**: a sheet is one short
list with a hairline already under its header, and a line under every row turned
five choices into five boxes. Row padding is the separation. Hairlines stay
where a list is long enough to lose your place in — inside a `ListCard` on a
page, not in a sheet.

A picker sheet lists options as `title` + `body` description + trailing radio.

**Notes are capped.** 500 characters for a session's or an exercise's, 200 for
a set's — a set note is rendered inside a table row and anything longer than a
phrase pushes the table apart. The counter reads `120 / 500` in `label`, and
turns `negative` on the last character.

**Text entry lives in a sheet, not a dialog.** Every note in the app — the
day's, an exercise's on that day, a set's — opens `promptForNote`: sheet header,
one `surfaceSunken` field, one white Save, riding above the keyboard. A centred
alert lands in the middle of the screen while the row that summoned it sits at
the bottom, and it fights the keyboard for the same space. Dialogs are for
*names*: one line, no scrolling, nothing to lose.

### The day picker

A month grid in a **dialog** (`pickDay`), never `showDatePicker`. Material's
dialog is the one surface the language cannot reach: it arrives centred, with
its own type scale, its own ripples, a landscape header and an accent taken from
the `ColorScheme`. Three screens asked "which past day?" and all three answered
it in a different app.

The one picker in the app that is **read before it is tapped**, which is why it
is not a sheet — a sheet puts the month you are reading at the bottom of the
screen, under your thumb.

`‹ March 2026 ›` in `title` across the top, the name itself opening a year grid;
weekday initials in `label` `textTertiary`; 38dp day circles. **Six rows,
always** — a month wants four, five or six depending on where its first day
falls, and sizing to the month made every page turn a resize.

Three states stack on one circle, ranked so none hides another:

- **A ring in the day's own colour for a day you trained** — `heatOn` blue,
  `deload` orange, the same two the heatmap and the history rows use. Without
  it the calendar is the one surface in the app that cannot show you the gap you
  opened it to fill.
- **`accent` fill** for the day currently chosen. A trained day keeps its
  coloured ring around the fill.
- **`textTertiary` ring** for today.

A day outside the range is `textTertiary` and dead — **shown, not removed**, so
the month keeps its shape and the hole says why.

**Picking a day that is already logged asks rather than guesses**: see what is
there, or log another session on it. Guessing "log another" is how a tap meant
to check Tuesday ends with a second Tuesday in history.

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

**There is one chart** — `TrendChart` in `core/widgets/trend_chart.dart` — and
**one range control** above it, `TrendRangeBar`: `1W · 1M · 3M · 1Y` as chips,
then a year picker where `All` used to be. The plot was written a second time
for bodyweight and came back with a different range control (`3m 6m 1y All` in
a segmented pill), no edge suppression and no calendar-aware tick spacing, so it
printed `Dec 19Jul 26` and `330 Jul` on top of themselves. A chart is a
language, not a widget you write per screen.

- **Both axes drop their edge ticks.** A label at `min` or `max` has half a line
  of room and prints over its neighbour.
- **Tick spacing is calendar-shaped**: a week, a fortnight, a month, a quarter,
  a year. Ticks every 97 days label three different months and read as noise.
- Y bounds are the data plus air, snapped to a round step — **never anchored at
  zero**, which draws a year of bodyweight as a flat line an inch off the
  bottom. The air stops at zero when nothing in the series is negative.
- Dashed horizontal gridlines only, `border`; **no vertical gridlines, no chart
  border**.
- Y labels on the **right**, `label` size, `textSecondary`. X labels below the
  baseline.
- Series: `data` line 2px with open circle markers (fill `bg`, stroke series
  colour). Sparklines drop the axes entirely.
- **Markers only while they mark something.** Past ~40 points the circles touch
  and a year of training renders as a thick dotted band with the line lost
  inside it — the shape you came to read, hidden by the points it is made of.
  Drop them and say `Pinch to zoom, drag to pan` instead.
- **Zoom is horizontal only.** Time is the axis with too much in it; scaling
  the value axis as well would make the same progress look like whatever you
  last pinched.
- Above the plot: two stats as `label` + `value` + unit, then the date range in
  `body`.
- Below the plot: range selector as a segmented pill — `surfaceHigh` track,
  **white pill** behind the active range, `label` text. A separate small
  `surfaceHigh` pill with a caret for granularity.
- Legend: chips inside a `surface` card, marker + label; disabled series dim to
  `textSecondary`.

### Mastheads

**A page title names its page, in sentence case.** Both halves of that were
once the other way round and both were wrong:

- **No uppercase.** At 30sp and weight 800 the size and weight already carry
  the emphasis; uppercase only cost every title its word shapes — which is what
  a heading is actually read by — and made long ones ellipsize sooner.
- **The landing screen names itself too.** It used to be titled with the date,
  on the grounds that the nav bar already said "Today". The nav label is 11sp
  at the far end of the screen, so that made the one screen you land on the
  only one whose masthead never says where you are. The date is the eyebrow
  above it, which is the slot it always half-occupied.

**Every destination's masthead is two lines: an eyebrow over the title.** The
eyebrow states what the page holds — the date on Workouts, the span on History,
the inventory on Regimes (`3 regimes · 3 slots free`), where it lives on
Settings. Regimes and Settings were a bare 30sp word on a short band, and next
to the other two tabs they read as screens from a different app. A tab with no
honest eyebrow yet (the count hasn't loaded) takes the wider `24` top gap until
it has one, rather than printing a number nothing measured.

**Only a destination gets a masthead.** `pageTitle` at 30sp belongs to the four
tabs — Workouts, Regime, History, Settings. Everything you *push* wears the app
bar instead: back arrow left, **small centred title** in `title` size, actions
right. A logged day or one exercise in a 30sp masthead reads as somewhere you
navigated *to* rather than into, and there is no way back up the hierarchy from
a screen that looks like the top of one.

Anything the centred title has no room for — a date, a set count, a metric
strip — goes in a `surface` block directly under the bar, sharing its colour so
the two read as one header.

**The band does not scroll**, and it holds *only* the masthead: the screen's
name, its eyebrow, and at most one quiet line about the state of things (on
Workouts, when you last trained). Everything you can act on is a section under
it, with its own heading, on the page background.

A block put inside the band shares the band's surface, so it has no boundary of
its own — Workouts had the session in there and the header ran half the screen
with the first real section beginning somewhere in the middle of it, unmarked.
Pin the band, scroll the content.

**One noun, one screen.** An exercise is looked at, edited and created on the
same page — `ExerciseScreen`. It was three shapes: a read-only slot screen whose
`General` section handed off to an `Edit` sheet, that sheet (dropdowns, text
fields, its own header and its own Save), and the same sheet again for `New
exercise`. Editing a movement looked nothing like looking at one.

The page is **sections, not a form**: `Overrides` — only when you arrived from a
training day, because nowhere else has a day for them to be true in — then
`General`, always. Every field is an ordinary row you tap, opening one question
at a time, which is how every other setting in this app is changed. No dropdown:
a Material menu drops over the page with no room to say what an option *means*,
and `How the weight is entered` is the field that decides how every set ever
logged is read.

An existing row **saves as you go**. A new one holds a draft behind one
`Create exercise` button, because a half-filled movement abandoned by a
back-swipe should not be in the catalog.

**The notice.** A stated limit or consequence: `warningMuted` ground, a hairline
of `warning` at 45%, `warning_amber_rounded` and the title in `warning` yellow,
and the sentence itself in `textPrimary`. `NoticeBox`.

It exists because a limit explained in a grey box, above a stack of greyed-out
cards, is one more greyed-out thing — the whole sheet was off and nothing on it
said which part was the *reason*. Colour is what separates a rule from a casualty
of it.

Yellow, not red: `negative` is for destroying something, and a limit destroys
nothing. It carries its own `warning` token rather than borrowing `deload`'s
amber, so a light week and a refused action can be retuned apart. Never for an
error, never dismissible — a notice states a rule that is currently true.

**The copy states the rule, not its cause.** "You can keep up to 6 regimes at a
time" — not the reason there are six, which is an identity colour per regime and
tells you nothing you can act on. An implementation detail in a warning reads as
an excuse.

### The metric screen

Re-audited on the device against a year of real logs, because our Progress
screen is the one place the language never landed. The shapes below are what
make that app read as one product; none of them costs a feature we don't have.

**One card contract, everywhere.** Title → range subtitle (`Last 7 Workouts`)
→ the visual → headline value with its unit one step down → chevron. A
dashboard tile, an exercise tile and a muscle tile are the *same card* with a
different payload. Ours diverge per screen, which is what makes the app feel
assembled rather than designed.

**A grid of those cards is the picker.** There is no "choose an exercise, then
see a chart" step: every exercise is a card already showing its sparkline and
its latest figure, grouped under plain headings (`Last Week`, `Lifetime`), and
tapping one opens the full chart. The answer is on screen before the question
is asked.

**On a metric screen the number leads and the date is the caption** — `63.7 kg`
in `title`, `Sat, Feb 28` in `body` beneath it. On a *session* screen it is the
other way round, because there the day is the subject. Same row, inverted, and
the inversion is the information.

**The metric is a tab strip, not a setting.** `1-RM · 3-RM · 10-RM · Heaviest
Weight` across the top; switching restates every row and the chart in that
metric. It answers "by which measure" — a better question than "over what
window", which is what a range pill answers, and both are present.

**The tabs pin, the chart scrolls.** The metric strip stays under the title bar
while the plot and the range pill scroll away beneath it, so the thing you
change is always reachable and the thing you read is not permanently occupying
half the screen.

**Lists under a chart group by month**, `section` heading on the page
background, rows in one card beneath — the same grouping History already uses.

### Muscle volume bars

Weekly sets per muscle, and the one chart in this app that is a *list*: one row
per muscle, name on the left, a horizontal bar, the count on the right.

```
Legs     ████████████████████  12 sets
Chest    ██████████             6 sets
Arms     ██████████████         8 sets
```

- Rows are in **`MuscleGroup` order and never re-sorted** — chest, back,
  shoulders, arms, legs, core. A list that reorders itself as you train puts
  chest in a different place every week, so reading it means finding the row
  first; fixed, the position *is* the label and a gap is visible at a glance.
  Sorting by count would make the biggest bar first, which is the one fact the
  bar lengths already tell you.
- The bar is normalised to the **largest muscle that week**, not to a target.
  This app has no volume targets and inventing one would be advice, not a
  measurement (README non-goals).
- Bar: `data`, height 8, radius 4, on a `surfaceHigh` track that shows the full
  width so an empty week is still a row rather than a gap.
- Name in `body`, count in `valueSm` with `sets` in `micro` beside it. A muscle
  trained zero times prints `— sets` and an empty track (rule 4).
- No axis, no gridlines, no legend. A bar list whose longest bar is the maximum
  needs none of them, and they are what turn six rows into a chart nobody reads.

### The hero pager

The first block of the landing screen may hold **more than one card, swiped
horizontally**, with a dot indicator beneath: today's session first, the week's
muscle volume second. It is the one place in the app where a horizontal gesture
carries content rather than navigation, and it exists because Today's first
screenful is the most contested space in the app — two answers that are both
"what should I do", and neither is worth pushing the other below the fold.

Rules: **two pages, at most three.** The first page is always the action —
start, resume, or what is next — because a landing screen that opens on a
statistic makes you swipe to use the app. Dots are `textTertiary`, active
`textPrimary`, 6dp, centred under the card. The pager takes the height of its
tallest page so the dots do not move as you swipe.

This does not license horizontal gestures anywhere else. The log screen owns
its axis (README invariant 4) and nothing inside it may take one.

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

**Exercise rail** — the reference uses 60×84 photo thumbnails with a 3px
underline beneath. This app has no exercise photography and never will (§0), and
a rail of two-letter monograms takes the same room while saying less than the
name does, so ours is **text tabs with the same underline**: white under the
current exercise, `surfaceHighest` under the rest, a tick before a finished one.
Only the exercises you are *not* on carry a `2/4` count — the current one has
`Set n of m` in the header directly beneath.

**Header** — exercise name in `section` (max 2 lines), `Set 2 of 4` in `body`
under it, and a load summary pill on the right.

**Action chips** — the horizontally scrolling chip row described above.

**Set table** — a header row of `label` columns (`Set · Last time · kg · Reps ·
✓`), then one row per set. **On the page, not in a card**: the index column
starts on the page gutter, so it shares a vertical with the exercise name, the
rail above it and everything else on the screen. Load and reps are equal-width
expanding columns.

| Element | Spec |
| --- | --- |
| Index chip | A circle filling the index column, `valueSm`. **Warm-up shows `W`, drop set shows `D`**, and warm-ups are excluded from the "Set n of m" count. A typed set is tinted with it: `data` for a warm-up, `deload` for a drop — a letter *and* a colour. The tint is **blended into `surfaceHigh`, never translucent**: laid over the drop capsule at 18% it picked up the grey behind it and came out a washed olive. The letter alone put the two rows that are not your working sets in the same grey as the rows that are. |
| Prefill | Not a column. Last time's numbers sit **inside** the fields as ghost text — `textTertiary`, and nothing else: no dot, no italic — because you compare against them at the moment you are deciding what to lift, and a separate column costs the width the value needs. Where the ghosts came from is not a caption in the header — that was the info sheet's line printed twice — it is the `Last logged` row behind the exercise's ⓘ, with a `deload`-orange dot on the button whenever they were borrowed from another session. |
| Value field | `surfaceHigh` fill, radius 12, height 48, centred `valueSm`. Focused: transparent fill + 2px white outline. |
| Done | Checkbox as specced. |
| Completed row | Values and index dim to `textSecondary`, the fields drop from `surfaceHigh` to `surface`, and the checkbox goes solid white. Dull, not black: at `surfaceSunken` a logged row read as a hole cut in the table. The row is *not* struck through, washed, or recoloured. |
| Delete | **Swipe the row left** to uncover a `negative` delete button, and tap it. The **whole** row travels — index chip, drop-capsule segment and fields as one piece; sliding the fields out from under a chip that stays put reads as the table coming apart. The button is **carried in by the row**, parked one panel past its right edge and clipped until the swipe brings it in — never a static panel uncovered underneath. It is the checkbox's shape in the checkbox's place: 28dp square, radius 4, 18dp glyph, `negative` fill. The swipe is live from anywhere on the row, the index column included, and it drags back shut the way it opened — the swipe reveals, it never deletes on release, because a set logged an hour ago must not be one flick from gone. A tap anywhere else on the row, or a swipe on another one, closes it. The set sheet behind the index chip keeps its delete too: the chip is the way to a *group's* actions, the swipe is the way to *this row's*. The cost is that the page no longer turns from a drag that starts on the table — taken deliberately, because deleting one leg of a drop set otherwise meant hitting a 5dp dot. |
| Add set | A circular `surfaceHigh` + button in the index column, below the last row. |
| Drop set | The group's rows sit on one `surfaceHighest` capsule filling the index column: the `D` chip at its head, a `textTertiary` dot on each middle leg, and the `+` in the **last leg's cell**, level with the row it continues — never a row of its own, which left a cell-high gap under a dot that marked nothing. Every cell in the column opens that row's sheet; on the `+` it is a long-press. The capsule's caps stop on the **chip's** edge, not the row's — a row is taller than the chip in it, and a cap drawn to the row ends in a shoulder with nothing under it. |

**Finish** — when every set is ticked, a white primary button appears pinned at
the bottom. Before that it is a quiet link in the top bar: finishing
early is legitimate here (a rack gets taken, a session gets cut short) and the
confirmation names what is unfinished, so the action has to exist — it just
should not be the loudest thing on screen while there is still work to do. The
two never show at once.

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

**Fields are declared once, in `inputDecorationTheme`.** Fill, radius, focused
outline, hint colour and insets are the theme's; a call site passes a hint, a
prefix or a suffix and nothing else. Seven fields each carried their own copy of
that block, which is how the exercise search in History ended up with no focused
outline, no hint colour and a different magnifying glass than the identical
field in the catalog. A list filtered by typing uses `SearchField`.

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
  "Exercises". The number is the useful part. Trailing text link
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

**Re-ordering is a drag, everywhere** — `showReorderSheet`. A training day's
exercises, a regime's days and today's log all open the same sheet: numbered
rows, a drag handle on the right, one `Save order` under them.

It was ⌃ / ⌄ buttons per row, on a note saying an immediate vertical drag
competes with the page scroll and loses. That is true of a drag started from
anywhere on the row and false of one started from a **handle** — the handle
owns the gesture, the rest of the row still scrolls, and `ReorderableListView`
brings its own auto-scroll to carry a row past the fold. Two directions is a
fine control for moving something once and a bad one for arranging six things,
which is what you opened the sheet to do.

The order is committed on **Save**, not per move: a re-order is one decision
made out of several movements, and writing each one pushes a stream update into
everything watching underneath.

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
| No deload concept | Deload is `deload` orange everywhere it touches — cycle, heatmap, resume card, history row | It is the one thing our cycle model has that theirs doesn't; it must be legible at a glance |
| Prefill is "previous", per exercise | Prefill is session-scoped and says so out loud when it borrows: an orange dot on the ⓘ, the session and date inside it | The entire reason this app exists (README) |
| Programme identity is a colour + glyph you must pick during creation | Same mark, but auto-assigned on create and changeable later | Identity is worth having; a mandatory question about it is not |
| Rep targets hidden two taps deep behind a card, placeholder `Optional` | Same sheet, but the card shows the target inline (`4 × 8–10`) so it is readable without opening | The target is the point of the slot |
| Theme is three labelled words in a segmented track | Three miniatures of the app — background, `Aa`, chart series, cards — with System split on the diagonal, over a `title` label. Each sits on a `surface` mount with a hairline, taking 2px `accent` when chosen (the choice-card state, §7): a miniature paints its own palette, so the dark tile on a dark page has no edge of its own | A track asks you to remember what "System" did last time; the tile shows it. The one place in the app where a control renders the *other* palette on purpose |
| Every screen's masthead prints the screen's name | Same, landing screen included: `Workouts` in `pageTitle`, the date as its eyebrow, the rest gap as a `body` line beneath | This was briefly the other way round — the date as the title, on the grounds that the nav bar already says the name. It made the one screen you open into the only one whose masthead never says where you are, and the nav label answering for it is 11sp at the far end of the screen |

---

## 10. Mapping to this codebase

| Where | Change |
| --- | --- |
| `lib/core/theme/tokens.dart` | Replace the blue-tinted greys with the neutral ramp; `accent` becomes white/black; add `info`; drop the shadow token and `Shadows` helpers. |
| `lib/core/theme/theme.dart` | Rebuild the type scale to §3; `FilledButton` white; remove `dialogTheme` centring in favour of the bottom-anchored confirm; switch/checkbox/radio themes per §5. |
| `lib/core/widgets/primitives.dart` | `AppCard` loses its border and shadow; `SectionHeader` action becomes a text link; add `ListCard` + `AppRow`, `SegmentedPill`, `FilterChip`, `ConfirmSheet`; `Pill` stays for status only. |
| `lib/features/shell/app_shell.dart` | Drop the accent pill behind the active tab; white/grey weight shift instead. |
| Today | Header band, monochrome hero, white Start button, dashes in the consistency line when there is no honest rate. |
| Log | Set-row spec in §6 — `W`/`D` index letters, swipe-to-delete, focused-field outline, pinned finish button. |
| History | Rebuild per §7 — this screen is the furthest from the language today. |
| Progress | Chart spec in §5 — right-hand Y labels, dashed gridlines, segmented range pill. |

Order of work: tokens → theme → primitives → shell → one screen at a time,
`flutter analyze && flutter test` after each.
