# Deltoid — the design system

**Single source for anything visual.** Compose screens from the components
below; if what you need is not here, add it here first. A component invented in
a feature folder is a second answer to one question, and the two drift apart
within a week.

No status, no data rules — see [TODO.md](TODO.md) and [RULES.md](RULES.md).

---

## 1. The character

Deltoid is used **mid-set, one-handed, at arm's length, with chalk on your
hands**. Everything below follows from that.

- **Quiet.** Near-black, two greys, white. Nothing glows, pulses or
  congratulates you.
- **Dense, never crowded.** A screen answers its question in one glance;
  everything else is one tap away.
- **Instrument, not dashboard.** Numbers are the interface.
- **Honest.** It shows what it measured, never filling a gap with a plausible
  number, a badge or encouragement.
- **Still.** Motion confirms a change; it never performs.

If a screen would look at home in a fitness app's marketing shots, it is wrong.

---

## 2. The six rules

For any decision not covered below.

1. **Chrome is monochrome; colour is data.** Buttons, chips, nav, headers and
   selection states are white, black and grey. Hue is reserved for things that
   *mean* something — a chart series, a deload, a muscle region, a destructive
   action. A blue button beside a blue chart line makes the button look like
   data and the data look tappable.
2. **Depth is surface colour.** Two greys and a hairline. No card borders,
   shadows, gradients or glows, ever.
3. **One primary action per screen, and it is white.** Everything else is a grey
   pill or a quiet text link.
4. **Zero states print dashes, not zeros.** `—— kg`, `-- sets`. A `0` is a
   measurement; a dash is "nothing here yet". Never fabricate a number.
5. **Every value carries its unit, smaller than the value.** `87` at value size,
   `kg` one step down in grey.
6. **Say it once.** A fact appears in one place on a screen. When it appears
   twice, one is **deleted** — not shrunk, not moved somewhere quieter.
   - The screen's subject is named once. A card inside Workouts does not say
     "today".
   - A number gets one representation: a bar *or* a count. Where a graphic and a
     figure say the same thing, the graphic stays only if it says it faster.
   - A control states its action once — not a chevron *and* an "Edit" label
     *and* a tap hint.
   - Repetition *down* a list is a column, not duplication. Repetition *across
     levels* is — a total in the header and again in the last row.

   Not tidiness: every duplicated element is one more thing to read before the
   screen answers what it was opened for.

---

## 3. Colour

Pure neutrals, no blue tint in the greys. That choice is most of what separates
"designed" from "themed".

### Neutral ramp — dark

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#131313` | Page background |
| `surface` | `#1F1F1F` | Cards, app bar, nav bar, sheets, header bands |
| `surfaceHigh` | `#2B2B2B` | Chips, secondary buttons, circular icon buttons, input fills |
| `surfaceHighest` | `#3A3A3A` | Focused input fill, pressed chip, keypad utility keys, empty bar track |
| `surfaceSunken` | `#0E0E0E` | Keypad bed, wells under a scrolling list |
| `border` | `#2E2E2E` | Inset dividers inside a card, outlined empty-state boxes. **Never** a card outline |
| `textPrimary` | `#FFFFFF` | Titles, values, active labels |
| `textSecondary` | `#9A9A9A` | Subtitles, captions, units, inactive nav |
| `textTertiary` | `#6E6E6E` | Chevrons, disabled, placeholder |
| `accent` | `#FFFFFF` | Primary action fill, selected chip fill, active tab underline |
| `onAccent` | `#121212` | Label on `accent` |

### Neutral ramp — light

Inverts, never tinted. `bg #F4F4F4` · `surface #FFFFFF` · `surfaceHigh #EDEDED`
· `surfaceHighest #E0E0E0` · `border #E4E4E4` · text `#111111 / #5F5F5F /
#8C8C8C` · `accent #111111` with white labels.

### The hues

**Six, plus one red.** `orange #FF8660` · `blue #689FFA` · `yellow #FFD15E` ·
`green #5DBA86` · `lavender #B28DF7` · `cyan #77D4E3`, and `red #F83446`.

Named on `DeltoidColors` and referenced by name. **Never write a hex at a call
site**: a chart series, a regime's mark and the deload orange must be the same
tone everywhere, not near-misses picked one screen at a time.

**A hue has to stay the hue.** These run 7.0:1 to 13.0:1 on `bg` — a wide spread
and the right trade, because yellow is bright. A set solved for equal contrast
turned yellow into an ochre: a number satisfying a constraint rather than a
colour.

**The same six in both themes** — a colour that changes with the phone's setting
is one you learn twice. The cost: on a white card `yellow` measures 1.4:1 and
`cyan` 1.7:1, so in light **the six are fills and marks only — never text, never
a hairline.** Where a hue must carry text in both themes, use `textPrimary` and
let the hue be the shape behind it.

**Red is deliberately outside the six.** `negative` must never read as
information, so it stays out of the palette everything else draws from — and may
shout where the six may not.

### Semantic assignments

| Token | Hue | Means |
| --- | --- | --- |
| `seriesPrimary` | cyan | First chart line, sparklines |
| `positive` | green | Success, completed, beat last time |
| `deload` | orange | A light week, wherever it appears |
| `warning` | yellow | A stated limit or consequence |
| `negative` | red | Destructive fill, delete panel |
| `seriesSecondary` | blue | Second chart line, heat ramp, session marks |
| `series[]` | cyan · blue · yellow · green · lavender | Categorical, in order |
| `identity[]` | the six, in order | One per programme |
| `heatOn` | blue | A day trained |
| `heatEmpty` | `surfaceHighest` | A day not trained, and an untrained muscle |

Two rules stop those colliding:

- **A closed set may be reused only where the two never share a screen.** The
  six serve both programme identity and muscle regions, and no screen shows both.
- **Identity marks appear only where they separate programmes** — the regime
  library. Elsewhere a mark means *what kind of day this was*: `heatOn` for a
  session, `deload` for a light week. That is what a feed of trained days is
  scanned for, and a programme hue in the same slot hides it.

### A filled mark's glyph is its own hue, taken down

Not white, not black. `#FF8660` carries `#9E2600`; `#5DBA86` carries `#275C3E`.
A tile is one colour with a shape cut out of it; a white or black shape makes it
two.

`IconTile.glyphOn`: same hue, same saturation, lightness walked down until the
glyph clears **3.2:1 against its own fill**, landing every tile at 3.24–3.35:1.
A fixed multiplier ranges 2.9–3.7 depending on where the hue sits — the
uneven-set problem one level down.

So a palette is only ever a list of fills. Nothing about a glyph is attached to
it, so a hue retuned later cannot break its own mark, and the fills stay light
enough to serve both themes.

---

## 4. Type

One family, nine roles. **Minimum 11sp, maximum 30sp** — nothing larger than a
page title or smaller than a nav label.

**One exception, a clock.** The hold pad's timer runs at 44sp: the only number
read from the floor with your chin on your hands. The cap stops a *heading*
competing with a page title; a running clock is not a heading, and shrinking it
would obey the rule at the cost of the moment the screen exists for. If a second
thing ever needs this, it becomes a role in the table.

| Role | Size / line | Weight | Case | Colour | Used for |
| --- | --- | --- | --- | --- | --- |
| `pageTitle` | 30 / 36 | 800 | Sentence, tracking −0.5 | primary | The one title in a destination's header band |
| `pageEyebrow` | 13 / 16 | 600 | UPPERCASE, tracking +1.2 | secondary | The line above a page title |
| `section` | 20 / 26 | 700 | Sentence | primary | Section headings on the page background |
| `title` | 16 / 22 | 600 | Sentence | primary | Card titles, row titles, exercise names, pushed-screen app-bar titles |
| `body` | 14 / 20 | 400 | Sentence | secondary | Subtitles, descriptions, captions |
| `value` | 22 / 26 | 700 | — tabular | primary | The number a card is about |
| `valueSm` | 16 / 20 | 600 | — tabular | primary | Table fields, inline stats |
| `label` | 13 / 16 | 500 | Sentence | secondary | Table headers, chip labels, axis labels |
| `micro` | 11 / 14 | 600 | Sentence | secondary | Nav labels, units, badge text |

- **Tabular figures on every number that can change** — weights, counts, timers,
  dates. A column that shifts as it updates is unreadable.
- A unit is `body` beside a `value`, never the same size.
- **Uppercase appears in one place**: the page title's eyebrow. Uppercase
  micro-labels scattered over a page (`LAST SESSION`, `THIS CYCLE`) are what
  makes a screen look like a template — use `section`.
- Titles never wrap past two lines; ellipsize.
- Sentence case everywhere. A title is read by its word shapes; uppercase costs
  exactly that.

### The words

Every string the user reads is a sentence, or a fragment that could start one.

- **Capital first letter, always** — titles, subtitles, stat-tile labels, chips,
  toasts, empty states. A label after a `·` is a new item and takes its own
  capital: `Cycle 4 · 3 of 6 · Deload in progress`.
- **The one exception is a unit riding on a value** (rule 5): `12 sets`,
  `82.5 kg est. 1RM`, `since 6:12 pm`. One phrase, not two.
- **Two facts are two sentences, not one dash.** An em dash bolting a
  consequence onto a clause reads as a footnote — write the second half as its
  own sentence or join it with a real conjunction. Prose *about* the app, in
  comments and these documents, keeps the dash; the app does not.
- **A one-clause subtitle takes no full stop**; two sentences take both.
- **Length is the space, not the sentiment.** A row subtitle is one clause, a
  toast six words, a dialog body one or two sentences naming what happens. Where
  a screen has room to explain — an empty state, a confirmation — explain, and
  stop as soon as it is said.

---

## 5. Space, radius, elevation

**Spacing** is a 4pt scale: `2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40`.

| Where | Value |
| --- | --- |
| Page gutter | 16 |
| Card padding | 16 (dense rows 12) |
| Section header → its content | 12 |
| Section → section | 28 |
| Row height | 56, or 72 with a subtitle |
| Above a page title | 12 when something small sits on top of it, 24 when it is the first line under the status bar |

That last matters: at 12, thirty points of title sit hard against the notch and
the band reads as part of the system bar.

**Radius is named for what wears it, never for a size.** `Radii.card` 20 ·
`Radii.sheet` 24 · `Radii.control` 14 (buttons, fields) · `Radii.cell` 10 (table
cells, keypad keys, rail tiles) · `Radii.panel` 18 (notice, empty box) ·
`Radii.mark` 6 (checkbox, done square) · `Radii.pill` 999. Identity tiles take
30% of tile size, heat cells 4, bar-list bars 2.

The names were `xs … xxl`, the ladder `Space` uses — and not the same numbers,
since `Space.md` is 12 against a radius of 14. One set of suffixes over two
scales invites pairing a padding with a corner because they sound like a matched
pair, and they never were.

**Elevation — none, ever.** Depth is surface colour: a card is `surface` on
`bg`; a control on a card is `surfaceHigh`.

---

## 6. Motion and feedback

**Durations** — 140ms for a press, 220ms for a state or layout change, 340ms for
a transition. Easing `easeOutCubic`, `easeOutQuint` for anything travelling a
distance.

**Anything with a height animates to it.** A fold arriving in one frame reads as
the widget being replaced rather than as this one opening. Every expand/collapse
is an `AnimatedSize`, every chevron an `AnimatedRotation` rather than two glyphs
swapped.

**Press feedback is a scale to 0.97 plus a dim to 0.86 — except on a row.**
Scale reads on a card, chip or button because the whole shape travels. On a
full-width row against an identical row, 1% of scale is invisible, and a list
that does not answer the finger feels a frame behind. So **rows and nav
destinations get ink and nothing else does**: no-splash is the app-wide default,
the ripple asked for explicitly, white at 10%.

**A ripple is a circle, and it is the only press state.**

- `highlightShape` is never `rectangle` on a bare surface. A highlight is a
  filled shape held while the finger is down, and on anything not already a
  bounded row it draws an edge nobody asked for.
- **No highlight under a splash** — a second shape doing the same job. A row is
  the exception, and only because a row *is* a rectangle.
- The ripple is `InkSparkle`, bounded to what you pressed, and **plays to
  completion** after the finger leaves, so changing tab does not cut its own
  feedback short.

**Scrolling is damped everywhere.** Bouncing physics on every list on every
platform, overscroll glow dropped: a list that visibly resists has already said
it ended, and a stretch indicator says it twice.

**A reload never blanks what is on screen.** Every paged view skips its loading
state on reload — a write anywhere must not replace the list you are reading
with a spinner.

**Loading and empty are different states.** A screen with more than one query
either tells them apart or is rebuilt around one query, or the frame between
them renders "nothing here" at data that is merely late.

---

## 7. Components

The vocabulary. Everything on every screen is one of these.

### Buttons

| Kind | Spec |
| --- | --- |
| **Primary** | Full-width, height 54, radius 14, `accent` fill, `onAccent` label at `title` weight. One per screen. Pinned to the bottom when it ends a flow. |
| **Secondary** | Same metrics, `surfaceHigh` fill, primary label, no border. |
| **Destructive** | `negative` fill, white label. Only inside a confirmation, never on a page. |
| **Text link** | `title` size, primary colour, **no underline**, followed by an 18dp chevron. The "See all / Collapse" affordance. |
| **Circular icon** | 40dp `surfaceHigh` circle, white glyph at 18. Add, close, refresh. **Its label is required** — a glyph alone cannot say what it does, so the name is what has to be written for the code to compile, and it carries `Semantics` as well as a tooltip (a tooltip needs a long press, which is not a gesture made mid-set). |
| **Compact pill** | Height 36, radius 999, `surfaceHigh`, `label` text. "Edit", "Change". |
| **Primary, compact** | The same fill and label at height 46, sized to its own words. The floating form: *one more of something* — "New exercise" — resting over the list at the bottom right. |

Disabled is a `surfaceHigh` fill with a `textTertiary` label — never a faded
accent, never an enabled button that errors when tapped.

**When a surface ends in two actions, stack them**: secondary above, primary
below, both full width. Never side by side.

**Full width is a commitment, not a default.** It says *this is what the screen
is for*: finish the session, save the exercise, confirm the delete — and an
empty state's one button, which is the whole point of a page with nothing on it.

**An action that adds one more row to a list you are browsing floats instead.**
Compact, bottom right, over the rows rather than in a strip beneath them: a bar
across the foot of a screen that is nothing but list spends a row's worth of it
on page background, and reads as the end of a flow when it is the beginning of
one. The list keeps enough padding to scroll its last row clear of it, and it
carries no shadow — depth is surface colour, and the fill is already the
brightest thing on the screen. It hides while an empty state is up, because that
state's own button is the same action and two of them read as two different
things.

### Chips

Height 44, radius 999, icon 16 + gap 8 + `label`. Unselected is `surfaceHigh`
with primary text; **selected is an `accent` fill with `onAccent` text**. A
trailing caret means it opens a picker; without one it is a toggle. Chip rows
scroll horizontally and bleed off the right edge — the clipped chip is the
scroll affordance.

**A dense chip (26 tall)** sits *inside* a list row, on the subtitle line. A
full-height chip there makes the row 90 tall and reads as the row's control
rather than as one word in its description.

**A chip naming a category carries that category's hue.** Unselected, the hue is
an 8dp **dot before the label** and the pill stays grey — chrome is monochrome,
and a column of filled pills beside a column of names is the loudest thing on
screen. Selected, it **fills with the hue**, label taken down by
`IconTile.glyphOn`. A chip meaning "all" has no hue: it is every category and
therefore none.

### Cards

`surface` fill, radius 20, **no border, no shadow**, padding 16. A card is a
grouping device, not a frame — a page of six cards has no hierarchy. Prefer one
card holding rows over six cards holding one row each.

### List card and rows

The workhorse. One `surface` card, rows inside, **inset hairline dividers** that
start at the text rather than the card edge, none under the last row.

```
[ icon 24 ]  Title                      [ trailing ]
   ↑ 16      Subtitle (body, optional)      ↑ chevron / switch / value
```

A leading icon is a **bare white glyph**. A coloured rounded-square tile is
reserved for an *identity* — a programme, a saved thing — never decoration. The
trailing chevron is `textTertiary` at 18.

**Full-bleed rows** — no card, edge-to-edge dividers — are for a screen that is
*nothing but* rows under headings. Never one section of a mixed page: a card's
edge lands 12 under its heading and full-bleed text lands 28 under it, so the
two together give a page sections starting at different heights.

### Section headers

`section` type on the page background: no card, no uppercase, one line. An
optional trailing **text link** *or* one small figure, vertically centred with
the title. 12 below, 28 between sections.

**Every heading on a page background is the same component.** A hand-rolled
`Row` that looks like one drifts off every other heading within a week. A
heading needing something other than a link on its right gets a trailing slot —
it does not get rebuilt.

**A heading has no subtitle.** The sentence goes *inside* the card, under the
thing it describes, which is where it is read. A figure belonging to the heading
goes in the trailing slot, on the title's line.

### Toggles, radios, checkboxes

- **Switch** — on: `accent` track, dark knob. Off: `surfaceHighest` track,
  `textSecondary` knob. No hue.
- **Radio** — selected is a filled white disc with a dark dot; unselected a 2px
  `textTertiary` ring. Trailing control of a row, one choice per row. Reach for
  it over a segmented pill when the choice needs room to say what it means; the
  pill is for a control governing the page under it.
- **Checkbox** — 26 square, radius 6. Checked: white fill, dark tick. Unchecked:
  2px `textSecondary` outline, transparent.

### Sheets — the default for any choice

**A sheet reserves the gesture bar itself, and `SafeArea` is not how.** The
route consumes the bottom padding before the builder runs, so a `SafeArea`
inside sees zero and adds nothing — every sheet had its last row under the
system nav bar except the one passing `useSafeArea: true`. `AppSheet` reserves
`viewPadding.bottom`, taking **the larger** of that and `viewInsets.bottom`, not
the sum: with the keyboard up the gesture bar is behind it, and adding both
lifts the sheet off the keyboard by the height of a bar nobody can see.

`surface`, top radius 24, our own drag handle 36×4 eight points from the top.
Header row: **bold `title` centred, ✕ on the right** in a 48 tap target,
full-width hairline under it. Then rows.

- The ✕ is right and larger than a row's glyph — the only control that is not
  one of the choices; on the left it reads as the first item in the list. It
  sits on the **title's line**, never centred against a two-line header.
- **The subtitle identifies, or it is not there.** One short `body` line naming
  *which* thing is being edited, never wrapping. Not the place to state scope or
  explain the sheet. A sheet whose title already names the thing goes without
  one, as does a sheet opened from a screen already about that thing.
- Rows are **full-bleed, never in a card** — a card inside a sheet is a panel
  inside a panel. **No rules between them**: a sheet is one short list with a
  hairline already under its header, and a line under every row turns five
  choices into five boxes. Row padding is the separation.
- A picker lists options as `title` + `body` description + trailing radio,
  **commonest option first** — the one a mis-tap is corrected back to.
- **A red row is the last row.** Anything tinted `negative` sits at the foot of
  its list or card with nothing plain after it: red is where a list ends, and an
  ordinary row underneath reads as an afterthought. Where a row's tint depends
  on state, its *position* moves with the tint.
- **Cap the height at two thirds of the screen.** A taller sheet has no distance
  to travel, so its entrance and exit read as a cut.
- **Text entry lives in a sheet, not a dialog** — header, one `surfaceSunken`
  field, one white Save, riding above the keyboard. A centred alert lands
  mid-screen while the row that summoned it sits at the bottom, and fights the
  keyboard for the same space. Dialogs are for *names*: one line, nothing to lose.

### Dialogs — confirmations

Bottom-anchored card, never a centred alert. `surface`, radius 24, padding 20.

```
Title (section, bold)                    ✕
Body — what actually happens, in one sentence. (body)

[      Destructive / primary button      ]   ← full width
              Go back                        ← plain centred text button
```

Never two equal-weight text buttons side by side. The safe option is the quiet
one, the dangerous one the loud one, and the copy says **what happens** rather
than "are you sure".

**A confirmation names both ends of a change and lifts them out of the
sentence** — "its muscle changes from **Chest** to **Back**" — because the
question is "did I mean to touch this at all", and the value it currently holds
is half that answer.

### Notice

A stated limit or consequence: muted `warning` ground, a hairline of `warning`
at 45%, glyph and title in `warning` yellow, the sentence in `textPrimary`.

Yellow, not red: `negative` destroys something and a limit destroys nothing.
Never for an error, never dismissible — a notice states a rule that is currently
true. **The copy states the rule, not its cause**; an implementation detail in a
warning reads as an excuse.

### Toast

The one transient message. `surfaceHighest` fill, `border` hairline,
`Radii.control`, floating with a `Space.md` margin, body text at the size the
screen around it reads at — the same object every card and sheet is, not
Material's slab in its own type scale.

**Short.** Long enough to read six words, not long enough to still be covering
the log when you look back: ~1.8s, or ~3.2s carrying an action, because an
action needs time to be aimed at. Anything longer is not a toast, it is a sheet.
**One at a time** — the queue is cleared on every one, since a second message
means the first is in its way. A failure says so in `negative`; nothing else
uses colour here.

### Illustration

**One drawing, one screen, and only where a screen has nothing else to be.**
Today that is the welcome screen and nowhere else. An illustration inside a
working screen is decoration, and decoration is what rule 1 spends the whole
colour system avoiding.

- **A single continuous stroke**, hand-drawn rather than geometric — a barbell,
  a figure mid-rep, a plate. Weight 2, round caps and joins. It should look
  drawn by a person, not by a vector tool.
- **`textPrimary` on `surface`, nothing else.** No fill, no second weight, no
  shadow.
- **Monochrome, including the accent.** Most likely rule to be broken: the
  obvious reference — a line drawing with one coloured dot — puts a hue into
  chrome, and here a warm dot is `deload`, so the drawing means something it
  does not mean. Emphasis is `accent`, which inverts with the theme.
- **It themes by inverting**, not by having two assets. One path, one token.
- **Inline vector, not an image asset** — it must take the theme colour at build
  time and stay sharp at any size.
- **Never load-bearing.** Remove it and the screen still reads.

### Empty states

An outlined box: 1px `border`, radius 16, padding 20, muted glyph left, `body`
text saying what will appear and what to do. A full-page empty state centres the
glyph over a `section` title, a `body` message and one primary button.

**A section with nothing in it hides rather than printing a shelf of dashes.**
Dashes are for a card that has a reason to exist and one missing figure.

**"Not here" and "not yet" are different sentences.** An index built from what
you have *done* — History's exercises, the days in a filter — must not answer a
search with "no such thing" about something you own and have not used. At rest
it lists what happened; searched, it falls through to the catalog and lists the
rest **below** the matches, under one heading, each saying plainly that it has
never been logged. Only a name nothing is called gets an empty state.

**A thing with no data still has a page**, and it is the same page it will have
once there is some — the name, the controls, the figures as dashes. A separate
"nothing here yet" screen that disappears the first time you finish a set means
the first thing you learn about a screen is a layout you will never see again.

### Value and unit

`ValueUnit` is rule 5 as a widget: a number with its unit one step down beside
it, sharing a baseline. `dense` is the row form (`labelLarge`, trailing an
`AppRow`); the default is the page form (`displaySmall`, the number a card is
about). `StatTile` is this plus a label under it.

**Every value carrying a unit is this widget.** It was hand-built in seven
places, each deciding for itself whether the unit was `bodyMedium` or
`bodySmall` and whether the pair shared a baseline or a centre line.

### Stat tile

`surface` card: `title` ellipsized to one line → `body` window caption →
sparkline → hairline → `value` + unit + chevron. The zero state keeps the whole
layout and prints `——` where the value goes, so a grid stays a grid.

**The number outranks the name**, which is the tile's premise: `title` is 16 and
`value` 22, so the name reads as the label of a figure rather than the heading
of a card. A screen where the name should lead is a screen of rows.

**Two to a row, matching without being measured.** Every tile is the same shape
— title, caption, fixed chart, one figure — so a row is
`CrossAxisAlignment.start` and nothing else. `stretch` in a scrolling list asks
for infinite height and throws; `IntrinsicHeight` works but lays the subtree out
twice to discover what the tiles already agree on.

**The caption is the tile's readout.** It names the span at rest — what the
chart is scaled against and how many periods it covers — and names the period
under your finger while scrubbing.

### Charts

**One chart and one range control**, both shared. A plot written a second time
comes back with a different range control, no edge suppression and no
calendar-aware ticks. A chart is a language, not a per-screen widget.

**Every chart is driven by the same row**: `1W 1M 3M 6M 1Y All`, then the year
picker, then the averaging chip. A screen may offer *fewer* chips than that — a
week of weekly bars is one bar, so volume starts at `1M` — but never different
ones, never in a different order, and never a second control of its own
somewhere else on the page.

**No chart ever plots raw rows.** Fifty years of daily entries is eighteen
thousand marks across a phone, which is not a chart, it is a texture. Every
chart folds its data into buckets — daily, weekly, monthly, yearly — and draws
one mark per bucket, so the mark count stays under about sixty at *any* range.
`Auto` picks the **finest** level that stays under that ceiling rather than the
coarsest that fits, which is what makes a week open on days and fifty years open
on years without either being a special case. The chip always names the level in
force, because a silently smoothed chart is a chart lying about its resolution.

- **A measurement averages; a count totals — into a rate.** Bodyweight in March
  is the mean of March's weigh-ins, because the mean of measurements is a
  measurement. Sets are counted, so a coarser bucket sums them — and then states
  them **per week**, the unit the training is written in. A monthly bar reading
  `62` beside a weekly one reading `14` is the same training drawn twice, and
  the axis would rescale by four every time you changed the averaging; holding
  the unit still is what makes the control a smoothing control rather than a
  different chart.
- **An empty bucket is not a zero, except when it is.** A month with no weigh-in
  breaks the line — there is no weight to draw. A month with no training is zero
  sets and the bar sits on the baseline. Same absence, two truths, and the fold
  reports emptiness so each chart can say which its own data means.
- **A bucket is drawn at its middle, not its first day.** A month plotted on the
  1st is half a month early, and a yearly mark on New Year's Day reads as the
  wrong year.
- **Buckets are walked as calendar dates.** Adding seven days to a local date
  crosses a clock change correctly; adding `7 × 86400` seconds does not.

- **Seven date labels, and the last one is today.** The count is fixed at every
  range, and the ladder is anchored on the **right** and counted back, because
  every rolling window ends on the day you are standing in. Laid out from the
  left instead, `1W` printed whichever day the data happened to start on and
  never printed today at all. The plot is padded half a step either side so the
  first and last labels sit inside it with room to print.
- **The labels are named by how much time is on screen**: a week by its weekdays
  (`Fri Sat Sun … Thu`), a season by dates, a year by months, a decade by years.
  Four ticks a day apart all render as the same month and read as mush.
- Y bounds are the data plus air, snapped to a round step, and **never anchored
  at zero** unless zero is in the data — anchoring draws a year of bodyweight as
  a flat line an inch off the bottom.
- Dashed horizontal gridlines only, in `border`. **No vertical gridlines, no
  chart border.**
- Y labels **right** at `label` size; X labels below the baseline.
- A series is a 2px line with open circle markers, filled `bg`, stroked in the
  series colour. Sparklines drop the axes entirely.
- **Markers only while they mark something.** Past ~40 points the circles touch
  and the line is lost inside them; drop them and offer zoom.
- **A bucket is a bar, not a point on a line.** A line between two weeks claims
  the value between them means something, and weekly set counts have no between
  — you did eleven that week and nine the next. Bars carry a *count over a
  period*; a line carries a measurement taken at a moment.
- **A bar's gap is a share of its slot, never a constant.** At thirteen bars a
  fixed 2pt gap is a quarter of each column and reads as separation; at
  fifty-two it is three quarters, and the chart becomes a grey band with
  hairlines on it. Below ~4pt of slot the bars meet, and the corner radius goes
  with the gap — a 2pt radius on a 2pt bar is a lozenge.
- **A week that was trained never draws as a week that was not.** A bar rounded
  to zero pixels is the chart contradicting the data; clamp it to a point of ink.
- **Bars and lines share everything except the mark.** A line is a measurement
  taken at a moment, a bar is a count over a period, and no amount of visual
  consistency makes one honest as the other. What they do share is the whole of
  the rest of it: the range row, the averaging, the gridlines, the right-hand
  axis, the label ladder, and the motion.
- **Changing range zooms; it does not cut.** Every range ends today, so motion
  is anchored on the **right edge**: widening from three months to a year is
  stepping back from the same wall — the weeks you were looking at stay put and
  more arrive on the left. Scaling about the centre slides this week sideways,
  and this week is the bar the eye is holding. Bar pitch and value scale both
  interpolate; weeks that were off-screen fade in rather than arriving drawn.
- **Only a change of range animates** — and a change of averaging, which is the
  same act one level down. New data in the same range moves a bar and nothing
  else; animating a zoom when a set is ticked makes logging look like
  navigating.
- **The frame never resizes during a transition.** The box keeps its height and
  width and only its contents rescale, or the page under the chart moves while
  you are reading it.
- **Axis furniture cross-fades, it does not travel.** Gridlines and month labels
  belong to a scale that was replaced, not moved: `Jul` cannot slide to where
  `Jan` is, and a gridline snapping under moving bars reads as a glitch. Swap
  them under the motion at the same duration.
- **Many bars are one painter, not many boxes.** Fifty-two weeks across six
  tiles is three hundred render objects laid out and composited to draw what is
  a single path.
- **An empty bar keeps its slot**, drawn as the full-height `heatEmpty` track —
  the same absence a rest day is on the heatmap. A skipped week that closes up
  is a skipped week you cannot see.
- **A gridline is `border` on `surface` only.** Over a lighter fill —
  `heatEmpty`, `surfaceHighest` — `border` is *darker* than what it crosses and
  reads as a scratch. Use `textTertiary` there, or drop the line: a figure under
  the chart usually says it better.
- **A chart read by touch names the value in its caption, not a tooltip.** On a
  card half a phone wide a tooltip covers the chart it describes, and the
  caption is already the line saying what the chart is of.
- **A sparkline may omit its scale; a chart you navigated to may not.** The
  small version is read as a shape among siblings, so no axis and no figure
  beyond the one under it. The full-size one answers "how much" and states a y
  axis in the unit counted with calendar labels under the baseline. Printing
  `peak 21` beside a sparkline is a fact about the drawing rather than the
  training, and reads as neither.
- **A bar chart's y axis is anchored at zero and snapped to a round step** — 2s,
  5s, 10s — with the maximum at or above the peak so the tallest bar sits under
  the top gridline. The opposite of the trend chart's rule, for the opposite
  reason: there zero is not in the data and anchoring flattens a year of
  bodyweight; here a week you skipped *is* zero and sits on the baseline.
- **Scrub, don't tap, once the bars are thin.** A year is 52 bars across a
  phone; nothing that narrow is a target. One horizontal drag moves the readout,
  and it stays out of the list's way because a drag must clear `kTouchSlop`.
- **Zoom is horizontal only.** Time is the axis with too much in it; scaling the
  value axis makes the same progress look like whatever you last pinched.
- **A point the metric cannot score is not a zero** — it is left out.
- **One session is a chart with one dot on it.** A single point is where you
  are, and the next one is read against it; refusing to draw until there are two
  makes the first month of a new movement look like a bug. Its span is zero
  days, so a fortnight of air goes either side of it.
- **An empty range is an empty chart, not a box where the chart was.** Same
  height, same gridlines, same right-hand gutter, and the **time axis of the
  window you asked for** — so the range chips still mean something with nothing
  under them, and changing range zooms rather than resizing the page under your
  thumb. The value axis keeps the scale of the *whole* history, so an untrained
  month reads as an empty stretch of the same chart.
- **An empty chart still states its value axis.** With a history to scale
  against it uses that; with none it falls back to a plain zero-to-round-number
  band in the unit being counted — the one place the trend chart anchors at
  zero, because the rule against it exists to stop a real line being flattened
  and there is no line here. Dropping the labels was tried and reads as a chart
  that failed to draw. A scale under an empty plot claims nothing: there is
  nothing on it to read against.
- **A chart explains itself under the plot, never across it.** A sentence in the
  middle of the frame is a dialog box wearing a chart's clothes. And it only
  speaks when the emptiness is something you could not read off the plot —
  unscoreable days, or a range that is all deloads. A range you simply did not
  train in needs no caption; the empty graph is the sentence.
- **A chart that has not loaded yet claims nothing.** It draws its frame and
  waits. "Nothing logged" is a statement about the log, and a frame that has not
  read the log is not entitled to make it — and a header that collapses to
  nothing while it reads shoves the list under it down a chart's height when it
  arrives.

### Bar list

The chart that is a list: one row per category, name left, horizontal bar,
figure right. No axis, gridlines or legend — a bar list whose longest bar *is*
the maximum needs none, and they are what turn six rows into a chart nobody
reads.

- Bars are **normalised to the largest row**, never to a target the app invented.
- Height 10, **radius 2 — not a pill**. Pill ends read as lozenges of different
  lengths, and a full radius eats the short ones: a one-unit bar is about as
  wide as its own two end caps.
- The track is `surfaceHighest` at full width, so an empty row is still a row
  rather than a gap. A category with nothing prints `0` and an empty track.
- **One hue per row**, from the six in order, so a row's identity is its colour
  rather than its position.
- Name in `body`, figure in `valueSm` with its unit in `micro` beside it.
- **A row that opens carries a small caret that flips** — chevrons down the left
  of every row are a column of furniture over a column of data. A row with
  nothing to open offers no caret; a control that does nothing is worse than no
  control. What opens is inset, on `surfaceHigh`, drawn **against the same
  maximum as the rows above it**.

### Table

Column headings in `label` `textTertiary`, then one row per record, **on the
page rather than in a card** so the first column starts on the page gutter and
shares a vertical with everything else. Value columns are equal-width and
expanding: a fixed narrow column beside an expanding one makes one field twice
the other for no reason a reader can see.

| Element | Spec |
| --- | --- |
| **Index chip** | A circle filling the index column, `valueSm`. A row of a special kind is marked by **a letter *and* a colour**, the hue **blended into `surfaceHigh` rather than laid over it at low alpha** — a translucent tint picks up whatever is behind it and comes out different on different grounds. |
| **Value field** | `surfaceHigh` fill, radius 12, height 48, centred `valueSm`. Focused: **transparent fill plus a 2px `accent` outline** — focus is an outline on nothing, because a fill *and* a border is two signals for one state. |
| **Ghost value** | A suggestion sits **inside** the field as `textTertiary` — no dot, no italic — because you compare against it while deciding, and a separate column costs the width the value needs. No synthesised italic anywhere: with no italic face bundled, the renderer shears the upright glyphs. |
| **Completed row** | Values dim to `textSecondary`, fields drop from `surfaceHigh` to `surface`, checkbox goes solid. Dull, not black — at `surfaceSunken` a finished row reads as a hole cut in the table. Never struck through or recoloured. |
| **Split cell** | A value that is really two numbers is **two boxes with one seam** — square on the shared side, rounded away from it, 2px apart — not one box holding an expression. `13+1` asks the eye to do arithmetic at arm's length to find a number that is not even the sum. The halves are **50-50**: both are what the record is made of, and a sliver beside a wide box reads as an afterthought. The second half **only exists once there is something in it**: a number on the row, a number the ghost carries from last time, or the pad asking for one. The pad's toggle is plain — `P` opens the half, `F` closes it — and an empty half never outlives the toggle that opened it. It slides out from the right over `Motion.fast` rather than snapping, because the first half halves in width. Empty reads as a dim `–`, never `0`. **Both halves take focus on their own tap** — a field you can see and cannot type into is broken — but **a tap never closes the half**: only `F` does, or moving to another cell, since tapping the first half to correct it would take away the box the second number was opened for. The heading names the column once, not the halves, which are not always there. |
| **Delete** | **Swipe the row left** to uncover a `negative` button, then tap it. The **whole** row travels and the button is **carried in by the row** — parked one panel past the edge and clipped until the swipe brings it in, never a static panel uncovered underneath. The swipe reveals; it never deletes on release. A tap anywhere else, or a swipe on another row, closes it. |

### The numeric keypad

A docked pad, not the OS keyboard: small targets, a shifting layout, no notion
of "one plate more". This keeps the table visible.

`surfaceSunken` bed. Digits are bare glyphs, no key background; utility keys are
`surfaceHigh` rounded rects; the advance key is `accent`. **No title and no
readout** — the field is outlined in the table above and the digits land in it
as pressed. A pad that captions itself covers what it is captioning.

- **The digits run `1 2 3` on the top row.** Every pad this thumb already uses —
  dialler, passcode, timer — counts downwards, and a pad counting upwards has to
  be looked at.
- **Step keys move by the unit of the field**, and say so: one plate for a load,
  one rep for a count, half a minute for a time (`+0:30`, never `+30`).
- **On an empty buffer, a step starts from last time** — "one plate more than
  last time" is the most common intent there is.
- **A ceiling is on the value, not the digit count.** Counting characters lets
  `999.99` through and refuses `1000.5` for being long rather than wrong.
- **The advance key names what it does** — `Next`, `Done`, or a question when
  the field still owes an answer.
- Anything a movement's numbers imply — a plate diagram for a barbell load —
  grows in above the digits and **collapses to nothing** when it does not apply,
  rather than reserving a band that is empty most of the time.
- **`F` / `P` says whether the set is being given partials**, not which box the
  digits are in. `P` opens the partial half and puts the digits there; `F`
  closes it and is the **only** control that does — and because it says the set
  is all full reps, it **drops whatever partials were recorded**, rather than
  leaving a number behind a shut box. Tapping a box moves the digits there and
  leaves the key alone: the half is still open, so a key flipping back to `F`
  would report a mode change nobody made. Both halves stay lit so the state is
  readable without looking at the table. It appears only where partials exist —
  a count, never a load, never a hold — and takes the slot the decimal point
  sits in on a load. It is for changing your mind mid-entry; the way *in* is
  tapping the half of the count cell you meant.

### The stopwatch pad

Some values are found rather than known, and a value read off a clock elsewhere
and copied in is a value typed twice. Where that is true, the keypad's slot
takes a stopwatch.

- The clock in `value` at 44sp, `m:ss`. What the stopwatch showed is what the
  table shows.
- **It counts up with the previous figure marked** — a 4pt bar filling toward
  it, `accent` under and `positive` past, the clock turning `positive` at the
  same moment. Never a countdown: a target you stop at is the wrong shape for
  "as long as you can".
- **One key.** Start, then Stop in `accent`, where the advance key sits.
  Stopping writes the value and completes the record. A stop inside the first
  second writes nothing — that is a mis-tap.
- **A small pill returns the digits** for a value measured elsewhere. A pill
  with a glyph rather than a bare word, because a word beside a 44sp readout
  does not read as pressable, and it disappears while the clock runs.
- **A time is typed as a clock**: digits fill from the right (`2` → `0:02`,
  `225` → `2:25`), four wide, and a keystroke pushing the seconds past 59 is
  refused rather than carried silently into the next minute.

### Day picker

A month grid in a **dialog**, never the platform picker, which arrives with its
own type scale, ripples and framework accent and makes every screen asking
"which day?" answer in a different app.

The one picker **read before it is tapped**, which is why it is not a sheet: a
sheet puts the month you are reading under your thumb.

`‹ March 2026 ›` in `title` across the top, the name opening a year grid;
weekday initials in `label` `textTertiary`; 38dp day circles; **six rows
always**, so a page turn is not a resize. Three states stack on one circle,
ranked so none hides another: a **ring in the day's own colour** for a day with
something in it, an **`accent` fill** for the day chosen, a **`textTertiary`
ring** for today. A day outside the range is shown and dead rather than removed,
so the month keeps its shape and the hole says why.

### Mastheads and app bars

**A destination gets a masthead**: an eyebrow over a page title, the title
naming the screen in sentence case. The eyebrow states what the page holds — a
date, a span, an inventory. A destination with no honest eyebrow takes the wider
top gap rather than printing a number nothing measured.

**Everything pushed wears the app bar**: back arrow left, small centred `title`,
actions right. A detail screen in a 30sp masthead reads as somewhere you
navigated *to* rather than *into*, and there is then no way back up.

**The band does not scroll and holds only the masthead** — name, eyebrow, at
most one quiet line of state. Anything the centred title has no room for goes in
a `surface` block directly under the bar, sharing its colour so the two read as
one header. A block *inside* the band has no boundary of its own, which is how a
header ends up running half the screen with the first section starting somewhere
in the middle, unmarked.

**A control that governs the page pins; content scrolls under it.** What you
change stays reachable, and what you read never permanently owns half the screen.

### Bottom navigation

`surface` bar, 1px top hairline, height 62 plus safe area. Selected is a white
icon and white `micro` label at weight 700; unselected `textSecondary` for both.
**No pill, no indicator, no hue** — weight and brightness carry the state.

### Badges

A status pill: radius 999, a 14% tint of the semantic colour, text in that
colour at `micro`. Used sparingly, never for anything a row already says.

---

## 8. Composing a screen

**A screen is a masthead, then sections on the page background.** A section is a
heading and either one list card or a chart. Everything actionable lives in a
section, never in the band.

**One noun, one screen.** A thing is looked at, edited and created on the same
page. Three shapes for one noun — a read-only view, an edit sheet, a create
sheet — means editing something looks nothing like looking at it.

**Editing is rows that open one question at a time, not a form.** No dropdowns:
a menu dropped over the page has no room to say what an option *means*.

- **An existing thing saves as you go. A new one holds a draft** behind one
  create button, so a half-filled thing abandoned by a back-swipe never lands in
  the data.
- **Every question shows `Choose` until answered**, and the create button stays
  off until all are. A field pre-set to a plausible value is a guess wearing the
  clothes of an answer, and once the sheet closes the two are indistinguishable.
- The exception is a field with a **true default** — right unless stated
  otherwise. It shows that value rather than `Choose`, because a required
  question answered the same way ninety-nine times in a hundred is ceremony.
- **Changing a field on something that already exists asks first**, and a field
  that changes how existing records are *read* asks the harder version, counting
  what it is about to reinterpret.

**Creation is a sheet, or one screen. Never a wizard.** No illustrated intro, no
progress bar, no "we will build you a plan" — the user is the planner. One
question per sheet; a second genuinely required question is a second sheet.

**The welcome screen is the one illustrated page, and it is not a wizard.** The
rule above bans an illustrated intro in front of *creating something* — the
regime flow, where a drawing stands between the user and what they came to
build. The welcome screen is one screen, one question, asked once, with the
answer that skips it given equal standing.

It stays inside the rule while all of this holds:

- **One screen, never two.** No carousel, no progress dots, no "next".
- **One question**, and not about training: where the history is kept, the only
  thing the app cannot infer.
- **Declining is a real answer, not a delay.** `Use without an account` is a
  plain text action directly under the primary — not greyed, not small print,
  not a corner `Skip`. Final and repairable: Settings offers the same connection
  later, and nothing nags.
- **Seen once.** Answered either way, it never appears again.
- **It says what it will do before it asks.** The subtitle names the outcome — a
  history that survives a lost phone — rather than the mechanism.

Top to bottom: the mark, the illustration, a `display` line, a `body` line, the
primary button, an `OR` rule, the decline action. Centred, generous vertical
space, everything inside the gutter. The only screen with a centred `display`
line, which is what makes it read as a threshold rather than a page.

Choice cards handle a genuinely branching decision: `surface` fill, radius 16,
1px `border`, padding 16, icon left, `title`, one `body` line, radio right, and
**a selected state that is a 2px border rather than a fill change**, so the card
stays readable and the set stays scannable.

**Re-ordering is a drag from a handle, in a sheet, committed on Save.** The
handle owns the gesture so the list still scrolls; a re-order is one decision
made out of several movements, and writing each move pushes a stream update into
everything watching underneath. Up/down buttons per row are a fine control for
moving one thing and a bad one for arranging six.

**Fields are declared once, in the theme.** Fill, radius, focused outline, hint
colour and insets belong to the input theme; a call site passes a hint, a prefix
or a suffix and nothing else. Seven fields each carrying their own copy is how
one search box ends up with no focused outline and a different glyph than the
identical box on the next screen.

**Free text is capped and the counter says so** — a limit that fits where the
text is rendered, counted in `label`, turning `negative` on the last character.

---

## 9. Where the language lives in code

| Part | File |
| --- | --- |
| Colour tokens, the hues, `IconTile.glyphOn` | `lib/core/theme/tokens.dart` |
| Type roles, input theme, control themes | `lib/core/theme/theme.dart` |
| Components — cards, rows, chips, sheets, dialogs, radios, pills | `lib/core/widgets/primitives.dart` |
| The one chart | `lib/core/widgets/trend_chart.dart` |
| The day picker | `lib/core/widgets/calendar.dart` |
| The re-order sheet | `lib/core/widgets/reorder_sheet.dart` |
| Scroll physics | `lib/core/widgets/scroll.dart` |
| Table, keypad, stopwatch pad | `lib/features/log/widgets/` |
| Bar list | `lib/features/workouts/widgets/volume_bars.dart` |

Feature code composes these; it does not restyle them. **A component nothing
calls is deleted**, not left for later — it is a second answer to a question
that already has one.
