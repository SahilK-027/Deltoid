# Deltoid — the design system

Everything Deltoid is drawn with: the character it aims for, the rules that
decide a close call, the tokens, and the component vocabulary every screen is
built from.

**Use it as the single source for anything visual.** Compose screens out of the
components below rather than styling widgets one screen at a time, and if
something you need is not here, add it here first. A component invented in a
feature folder is a second answer to a question that already has one, and the
two drift apart within a week.

This file holds no status and no data rules. Those are [TODO.md](TODO.md) and
[RULES.md](RULES.md).

---

## 1. The character

Deltoid is a tool used **mid-set, one-handed, at arm's length, with chalk on
your hands**. Every decision below follows from that sentence.

- **Quiet.** Near-black, two greys and white. Nothing glows, nothing pulses,
  nothing congratulates you.
- **Dense but never crowded.** A screen answers the question it was opened with
  in one glance, and everything else is one tap away.
- **Instrument, not dashboard.** Numbers are the interface. Chrome gets out of
  their way.
- **Honest.** The app shows what it measured. It never fills a gap with a
  plausible number, a badge, or encouragement.
- **Still.** Motion confirms a change; it never performs.

If a proposed screen would look at home in a fitness app's marketing shots, it
is wrong for this one.

---

## 2. The six rules

When a decision is not covered anywhere below, decide it with these.

1. **Chrome is monochrome; colour is data.** Buttons, chips, nav, headers and
   selection states are white, black and grey. Hue is reserved for things that
   *mean* something — a chart series, a deload, a muscle region, a destructive
   action. A blue button beside a blue chart line makes the button look like
   data and the data look tappable.
2. **Depth is surface colour, not decoration.** Two greys and a hairline. No
   card borders, no shadows, no gradients, no glows, ever.
3. **One primary action per screen, and it is white.** Everything else is a grey
   pill or a quiet text link.
4. **Zero states print dashes, not zeros.** `—— kg`, `-- sets`. A real `0` is a
   measurement; a dash is "nothing here yet". Never fabricate a number.
5. **Every value carries its unit, and the unit is smaller than the value.**
   `87` at value size, `kg` one step down in grey.
6. **Say it once.** A fact appears in exactly one place on a screen. When it
   appears twice, one of the two is **deleted** — not shrunk, not moved
   somewhere quieter.
   - The screen's subject is named once. A card inside a screen called Today
     does not also say "today".
   - A number gets one representation: a bar *or* a count. Where a graphic and a
     figure say the same thing, the graphic stays only if it says it faster.
   - A control states its action once — not a chevron *and* an "Edit" label
     *and* a tap hint.
   - Repetition *down* a list is not duplication: six rows each showing their
     own count is a column. Repetition *across levels* is — a total in the
     header and the same total again in the last row.

   The reason is not tidiness. Every duplicated element is one more thing to
   read before the screen answers the question it was opened for.

---

## 3. Colour

Pure neutrals, with no blue tint in the greys. That single choice is most of
what separates "designed" from "themed".

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

The ramp inverts; it is never tinted. `bg #F4F4F4` · `surface #FFFFFF` ·
`surfaceHigh #EDEDED` · `surfaceHighest #E0E0E0` · `border #E4E4E4` · text
`#111111 / #5F5F5F / #8C8C8C` · `accent #111111` with white labels.

### The hues

**Six, plus one red.** `orange #FF8660` · `blue #689FFA` · `yellow #FFD15E` ·
`green #5DBA86` · `lavender #B28DF7` · `cyan #77D4E3`, and `red #F83446`.

They are named on `DeltoidColors` and referenced by name. **Never write a hex at
a call site**: a chart series, a regime's mark and the deload orange have to be
the same tone wherever they appear, not near-misses picked one screen at a time.

**A hue has to stay the hue.** Evenness of contrast is worth solving for only
where it costs nothing else. These run 7.0:1 to 13.0:1 on `bg` — a wide spread,
and the right trade, because yellow is bright because yellow is bright. A set
solved for equal contrast turned yellow into an ochre, which is a number
satisfying a constraint rather than a colour.

**The same six in both themes.** A mark is the same mark whichever theme draws
it, and a colour that changes with the phone's setting is one you have to learn
twice. The cost, stated plainly: on a white card `yellow` measures 1.4:1 and
`cyan` 1.7:1, so in the light theme **the six are fills and marks only — never
text, never a hairline.** Where a hue must carry text in both themes, use
`textPrimary` and let the hue be the shape behind it.

**Red is deliberately outside the six.** `negative` must never read as
information, so it stays out of the palette everything else draws from — and it
is allowed to shout where the six are not.

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

Two rules keep those from colliding:

- **A closed set may be reused only where the two never share a screen.** The
  six serve both programme identity and muscle regions, and no screen shows
  both.
- **Identity marks appear only where they separate programmes** — the regime
  library. Everywhere else a mark means *what kind of day this was*: `heatOn`
  for a session, `deload` for a light week. That distinction is the one a feed
  of trained days is scanned for, and a programme hue drawn in the same slot
  hides it.

### A filled mark's glyph is its own hue, taken down

Not white, not black. `#FF8660` carries `#9E2600`; `#5DBA86` carries `#275C3E`.
A tile is one colour with a shape cut out of it, and a white or black shape
makes it two.

`IconTile.glyphOn` solves for it: same hue, same saturation, lightness walked
down until the glyph clears **3.2:1 against its own fill**, which lands every
tile at 3.24–3.35:1. A fixed multiplier ranges 2.9–3.7 depending on where the
hue sits, which is the uneven-set problem one level down.

This is why a palette is only ever a list of fills. Nothing about a glyph is
attached to it, so a hue retuned later cannot break its own mark — and it is
what frees the fills to be light enough to serve both themes.

---

## 4. Type

One family, nine roles. **Minimum 11sp, maximum 30sp.** Nothing is larger than a
page title or smaller than a nav label.

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

- **Tabular figures on every number that can change** — weights, counts,
  timers, dates. A column of numbers that shifts as it updates is unreadable.
- A unit is `body` beside a `value`, never the same size.
- **Uppercase appears in exactly two places**: the page title's eyebrow, and
  nothing else. Uppercase micro-labels scattered over a page (`LAST SESSION`,
  `THIS CYCLE`) are what makes a screen look like a template — use `section`.
- Titles never wrap past two lines; ellipsize.
- Sentence case everywhere. A title is read by its word shapes, and uppercase
  costs exactly that.

### The words

Every string the user reads is a sentence, or a fragment that could start one.

- **Capital first letter, always.** Titles, subtitles, stat-tile labels, chips,
  toasts, empty states. A label sitting after a `·` separator is a new item and
  takes its own capital: `Cycle 4 · 3 of 6 · Deload in progress`.
- **The one exception is a unit riding on a value** (rule 5): `12 sets`,
  `82.5 kg est. 1RM`, `since 6:12 pm`. That is one phrase, not two.
- **Two facts are two sentences, not one dash.** An em dash used to bolt a
  consequence onto a clause reads as a footnote — write the second half as its
  own sentence, or join it with a real conjunction. Prose *about* the app, in
  comments and these documents, keeps the dash; the app itself does not.
- **A subtitle of one clause takes no full stop**; two sentences take both.
- **Length is the space, not the sentiment.** A row subtitle is one clause, a
  toast is six words, a dialog body is one or two sentences that name what
  happens. Where a screen has room to explain — an empty state, a confirmation
  — explain, and stop as soon as it is said.

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

That last one matters more than it looks: at 12, thirty points of title sit hard
against the notch and the header band reads as part of the system bar.

**Radius is named for what wears it, never for a size.** `Radii.card` 20 ·
`Radii.sheet` 24 · `Radii.control` 14 (buttons and fields) · `Radii.cell` 10
(table cells, keypad keys, rail tiles) · `Radii.panel` 18 (notice, empty box) ·
`Radii.mark` 6 (checkbox, done square) · `Radii.pill` 999. Identity tiles take
30% of tile size, heat cells 4, bar-list bars 2.

The names used to be `xs … xxl`, the same ladder `Space` uses — and not the same
numbers, since `Space.md` is 12 against a radius of 14. One set of suffixes over
two scales invites you to pair a padding with a corner because they sound like a
matched pair, and they never were.

**Elevation — none, ever.** Depth is surface colour. A card is `surface` on
`bg`; a control on a card is `surfaceHigh`.

---

## 6. Motion and feedback

**Durations** — 140ms for a press, 220ms for a state or layout change, 340ms for
a transition. Easing is `easeOutCubic`, and `easeOutQuint` for anything
travelling a distance.

**Anything with a height animates to it.** A fold that arrives in one frame
reads as the widget being replaced rather than as this one opening. Every
expand/collapse is an `AnimatedSize`, and every chevron marking one is an
`AnimatedRotation` rather than two glyphs swapped.

**Press feedback is a scale to 0.97 plus a dim to 0.86 — except on a row.**
Scale reads on a card, a chip or a button because the whole shape travels. On a
full-width row against an identical row above it, 1% of scale is invisible, and
a list that does not answer the finger makes the app feel a frame behind. So
**rows and nav destinations get ink and nothing else does**: no-splash is the
app-wide default and the ripple is asked for explicitly, white at 10%.

**A ripple is a circle, and it is the only press state.**

- `highlightShape` is never `rectangle` on a bare surface. A highlight is a
  filled shape held for as long as the finger is down, and on anything that is
  not already a bounded row it draws an edge nobody asked for.
- **No highlight under a splash.** The ripple is the press state; a highlight
  beneath it is a second shape doing the same job. A row is the one exception,
  and only because a row *is* a rectangle.
- The ripple is `InkSparkle` — a soft radial wash bounded to what you pressed,
  falling off at its edges — and it **plays to completion** after the finger
  leaves, so changing tab does not cut its own feedback short.

**Scrolling is damped everywhere.** Bouncing physics on every list on every
platform, with the overscroll glow dropped. A list that visibly resists has
already said it has ended, and a stretch indicator says it twice.

**A reload never blanks what is on screen.** Every paged view skips its loading
state on reload: a write anywhere must not replace the list you are reading with
a spinner.

**Loading and empty are different states.** A screen with more than one query
either tells them apart or is rebuilt around one query, or the frame between
them renders "nothing here" at data that is simply late.

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
| **Circular icon** | 40dp `surfaceHigh` circle, white glyph at 18. Add, close, refresh. |
| **Compact pill** | Height 36, radius 999, `surfaceHigh`, `label` text. "Edit", "Change". |

Disabled is a `surfaceHigh` fill with a `textTertiary` label — never a faded
accent, and never an enabled button that shows an error when tapped.

**When a surface genuinely ends in two actions, stack them**: secondary above,
primary below, both full width. Never side by side.

### Chips

Height 44, radius 999, icon 16 + gap 8 + `label`. Unselected is `surfaceHigh`
with primary text; **selected is an `accent` fill with `onAccent` text**. A
trailing caret means it opens a picker; without one it is a toggle. Rows of
chips scroll horizontally and bleed off the right edge — the clipped chip is the
scroll affordance.

**A dense chip (26 tall)** is the one that sits *inside* a list row, on the
subtitle line. A full-height chip there makes the row 90 tall and reads as the
row's control rather than as one word in its description.

**A chip that names a category carries that category's hue.** Unselected, the
hue is an 8dp **dot before the label** and the pill stays grey, because chrome
is monochrome and a column of filled pills beside a column of names is the
loudest thing on screen. Selected, it **fills with the hue** and the label is
taken down out of that fill by `IconTile.glyphOn`. A chip meaning "all" or
"none of the above" has no hue: it is every category and therefore none.

### Cards

`surface` fill, radius 20, **no border and no shadow**, padding 16. A card is a
grouping device, not a frame — a page of six cards has no hierarchy. Prefer one
card holding rows over six cards holding one row each.

### List card and rows

The workhorse. One `surface` card, rows inside it, **inset hairline dividers**
that start at the text rather than the card edge, and none under the last row.

```
[ icon 24 ]  Title                      [ trailing ]
   ↑ 16      Subtitle (body, optional)      ↑ chevron / switch / value
```

A leading icon is a **bare white glyph**. A coloured rounded-square tile is
reserved for an *identity* — a programme, a saved thing — never for decoration.
The trailing chevron is `textTertiary` at 18.

**Full-bleed rows** — no card, edge-to-edge dividers — are for a screen that is
*nothing but* rows under headings. They are never one section of a mixed page,
because a card's edge lands 12 under its heading and full-bleed text lands 28
under it, so the two together give a page sections that start at different
heights.

### Section headers

`section` type on the page background: no card, no uppercase, one line. An
optional trailing **text link** *or* one small figure, vertically centred with
the title. 12 below it, 28 between one section and the next.

**Every heading on a page background is the same component.** A hand-rolled
`Row` that happens to look like one drifts off every other heading in the app
within a week. If a heading needs something on its right that is not a link, it
gets a trailing slot — it does not get rebuilt.

**A heading has no subtitle.** The sentence goes *inside* the card, under the
thing it describes, which is also where it is read. A figure that belongs to the
heading itself goes in the trailing slot, on the title's line.

### Toggles, radios, checkboxes

- **Switch** — on: `accent` track, dark knob. Off: `surfaceHighest` track,
  `textSecondary` knob. No hue.
- **Radio** — selected is a filled white disc with a dark dot; unselected is a
  2px `textTertiary` ring. It is the trailing control of a row, one choice per
  row. Reach for it over a segmented pill when the choice needs room to say what
  it means; the pill is for a control that governs the page under it.
- **Checkbox** — 26 square, radius 6. Checked: white fill, dark tick. Unchecked:
  2px `textSecondary` outline, transparent.

### Sheets — the default for any choice

**A sheet reserves the gesture bar itself, and `SafeArea` is not how.** A modal
bottom sheet's route consumes the bottom padding before its builder runs, so a
`SafeArea` inside sees zero and adds nothing — every sheet in the app had its
last row under the system navigation bar, and only the one call site passing
`useSafeArea: true` escaped it. `AppSheet` reserves `viewPadding.bottom`
instead, and takes **the larger** of that and `viewInsets.bottom` rather than
the sum: with the keyboard up the gesture bar is behind it, and adding both
lifts the sheet off the keyboard by the height of a bar nobody can see.


`surface`, top radius 24, our own drag handle 36×4 eight points from the top.
Header row: **bold `title` centred, ✕ on the right** in a 48 tap target, with a
full-width hairline under it. Then rows.

- The ✕ is on the right and larger than a row's glyph. It is the only control on
  the sheet that is not one of the choices; on the left it reads as the first
  item in the list. It sits on the **title's line**, never centred against a
  two-line header.
- **The subtitle identifies, or it is not there.** One short `body` line naming
  *which* thing is being edited, and it never wraps. It is not the place to
  state scope or explain the sheet. A sheet whose title already names the thing
  goes without one, and so does a sheet opened from a screen that is already
  about that thing.
- Rows are **full-bleed, never in a card** — a card inside a sheet is a panel
  inside a panel. **No rules between them**: a sheet is one short list with a
  hairline already under its header, and a line under every row turns five
  choices into five boxes. Row padding is the separation.
- A picker sheet lists options as `title` + `body` description + trailing radio,
  **commonest option first** — the one a mis-tap is being corrected back to.
- **A red row is the last row.** Anything tinted `negative` sits at the foot of
  its list or card, and nothing plain follows it: red is where a list ends, and
  an ordinary row underneath one reads as an afterthought. Where a row's tint
  depends on state, its *position* moves with the tint.
- **Cap the height at two thirds of the screen.** A sheet taller than the phone
  has no distance to travel, so its entrance and exit both read as a cut.
- **Text entry lives in a sheet, not a dialog** — header, one `surfaceSunken`
  field, one white Save, riding above the keyboard. A centred alert lands in the
  middle of the screen while the row that summoned it sits at the bottom, and it
  fights the keyboard for the same space. Dialogs are for *names*: one line,
  nothing to lose.

### Dialogs — confirmations

Bottom-anchored card, never a centred alert. `surface`, radius 24, padding 20.

```
Title (section, bold)                    ✕
Body — what actually happens, in one sentence. (body)

[      Destructive / primary button      ]   ← full width
              Go back                        ← plain centred text button
```

Never two equal-weight text buttons side by side. The safe option is the quiet
one, the dangerous one is the loud one, and the copy says **what happens**
rather than "are you sure".

**A confirmation names both ends of a change and lifts them out of the
sentence** — "its muscle changes from **Chest** to **Back**" — because the
question being answered is "did I mean to touch this at all", and the value it
currently holds is half that answer.

### Notice

A stated limit or consequence: a muted `warning` ground, a hairline of `warning`
at 45%, the glyph and title in `warning` yellow, and the sentence itself in
`textPrimary`.

Yellow, not red: `negative` is for destroying something and a limit destroys
nothing. Never for an error, never dismissible — a notice states a rule that is
currently true. **The copy states the rule, not its cause**; an implementation
detail in a warning reads as an excuse.

### Toast

The one transient message. `surfaceHighest` fill, `border` hairline, `Radii.md`,
floating with a `Space.md` margin, and body text at the size the screen around
it reads at — the same object every card and sheet is, not Material's slab in
its own type scale.

**Short.** Long enough to read six words, not long enough to still be covering
the log when you look back at it: ~1.8s, or ~3.2s when it carries an action,
because an action needs time to be aimed at. Anything needing longer is not a
toast, it is a sheet. **One at a time** — the queue is cleared on every one, as
a second message means the first is in its way. A failure says so in `negative`
text; nothing else uses colour here.

### Illustration

**One drawing, one screen, and only where a screen has nothing else to be.**
Today that is the welcome screen and nowhere else. An illustration inside a
working screen is decoration, and decoration is what rule 1 spends the whole
colour system avoiding.

- **A single continuous stroke**, hand-drawn rather than geometric — a barbell,
  a figure mid-rep, a plate. Weight 2, round caps, round joins. It should look
  drawn by a person and not by a vector tool.
- **`textPrimary` on `surface`, and nothing else.** No fill, no second weight,
  no shadow.
- **Monochrome, including the accent.** This is the rule most likely to be
  broken, because the obvious reference for the form — a line drawing with one
  coloured dot resting on it — puts a hue into chrome. In this app a warm dot is
  `deload`, an orange one is a light week, and a drawing that borrows either is
  a drawing that means something it does not mean. If a point of emphasis is
  wanted it is `accent`, which is white on dark and black on light, and it
  inverts with the theme like everything else.
- **It themes by inverting, not by having a light and a dark asset.** One path,
  one colour token.
- **Inline vector, not an image asset.** It has to take the theme colour at
  build time and stay sharp at any size.
- **Never load-bearing.** Nothing is only said by the drawing. Remove it and the
  screen still reads.

### Empty states

An outlined box: 1px `border`, radius 16, padding 20, muted glyph left, `body`
text saying what will appear here and what to do. A full-page empty state
centres the glyph over a `section` title, a `body` message and one primary
button.

**A section with nothing in it hides rather than printing a shelf of dashes.**
Dashes are for a card that has a reason to exist and one missing figure.

### Stat tile

`surface` card: `title` ellipsized to one line → `body` window caption →
sparkline → hairline → `value` + unit + chevron. The zero state keeps the whole
layout and prints `——` where the value goes, so a grid stays a grid.

**The number outranks the name**, and it is the tile's whole premise: `title` is
16 and `value` is 22, so the name reads as the label of a figure rather than the
heading of a card. A screen where the name should lead is a screen of rows, not
of tiles.

**Two to a row, and they match without being measured.** Every tile is the same
shape — one line of title, one of caption, a fixed chart, one figure — so a row
is `CrossAxisAlignment.start` and nothing else. `stretch` inside a scrolling
list asks for an infinite height and throws; `IntrinsicHeight` works and lays
the whole subtree out a second time to discover what the tiles already agree on.

**The caption is the tile's readout.** It names the span at rest — what the
chart is scaled against and how many periods it covers — and names the period
under your finger while the chart is being scrubbed.

### Charts

**There is one chart and one range control**, and both are shared. A plot
written a second time for one screen comes back with a different range control,
no edge suppression and no calendar-aware ticks. A chart is a language, not a
widget you write per screen.

- **Both axes drop their edge ticks.** A label at min or max has half a line of
  room and prints over its neighbour.
- **Tick spacing is calendar-shaped** — a week, a fortnight, a month, a quarter,
  a year. Ticks every 97 days label three different months and read as noise.
- Y bounds are the data plus air, snapped to a round step, and **never anchored
  at zero** unless zero is in the data — anchoring draws a year of bodyweight as
  a flat line an inch off the bottom.
- Dashed horizontal gridlines only, in `border`. **No vertical gridlines and no
  chart border.**
- Y labels on the **right** at `label` size; X labels below the baseline.
- A series is a 2px line with open circle markers, filled `bg`, stroked in the
  series colour. Sparklines drop the axes entirely.
- **Markers only while they mark something.** Past roughly 40 points the circles
  touch and the line is lost inside them; drop them and offer zoom instead.
- **A bucket is a bar, not a point on a line.** A line between two weeks claims
  the value between them means something, and weekly set counts have no between
  — you did eleven that week and nine the next. Bars carry a *count over a
  period*; the line carries a measurement taken at a moment.
- **A bar's gap is a share of its slot, never a constant.** At thirteen bars a
  fixed 2pt gap is a quarter of each column and reads as separation; at
  fifty-two it is three quarters of it, and the chart becomes a grey band with
  hairlines drawn on it. Below roughly four points of slot the bars simply
  meet, and the corner radius goes with the gap — a 2pt radius on a 2pt bar is
  a lozenge.
- **A week that was trained never draws as a week that was not.** A bar rounded
  from a real count to zero pixels is the chart contradicting the data; clamp it
  to a point of ink.
- **Changing a chart's range zooms it; it does not cut to the new one.** Every
  range ends today, so the motion is anchored on the **right edge**: widening
  from three months to a year is stepping back from the same wall — the weeks
  you were looking at stay put and more arrive on the left. Scaling about the
  centre slides this week sideways, and this week is the bar the eye is holding.
  Both the bar pitch and the value scale interpolate; weeks that were off-screen
  fade in rather than arriving fully drawn.
- **Only a change of range animates.** New data in the same range moves a bar
  and nothing else — animating a zoom when a set is ticked makes logging a set
  look like navigating somewhere.
- **Axis furniture cross-fades, it does not travel.** Gridlines and month labels
  belong to a scale that was replaced, not moved: `Jul` cannot slide to where
  `Jan` is, and a gridline that snaps under moving bars reads as a glitch. Swap
  them under the motion at the same duration.
- **Many bars are one painter, not many boxes.** Fifty-two weeks across six
  tiles is three hundred render objects laid out and composited to draw what is
  a single path.
- **A bar chart's empty bar keeps its slot**, drawn as the full-height
  `heatEmpty` track. It is the same absence a rest day is on the heatmap, and a
  skipped week that closes up is a skipped week you cannot see.
- **A gridline is `border` on `surface` only.** Over a lighter fill —
  `heatEmpty`, `surfaceHighest` — `border` is *darker* than what it crosses and
  reads as a scratch rather than a rule. Use `textTertiary` there, or drop the
  line: a figure printed under the chart usually says it better.
- **A chart read by touch names the value in its caption, not in a tooltip.** On
  a card half a phone wide, a tooltip covers the chart it is describing. The
  caption is already the line saying what the chart is of, so it is the line
  that says which week you are on.
- **A sparkline may omit its scale; a chart you navigated to may not.** The
  small version is read as a shape among siblings, so it carries no axis and no
  figure beyond the one under it. The full-size one is the answer to "how much",
  and it states a y axis in the unit counted and calendar labels under the
  baseline. Printing `peak 21` beside a sparkline instead is a fact about the
  drawing rather than about the training, and reads as neither.
- **A bar chart's y axis is anchored at zero and snapped to a round step** — 2s,
  5s, 10s — with the maximum at or above the peak so the tallest bar sits under
  the top gridline rather than over it. This is the opposite of the trend
  chart's rule, and for the opposite reason: there, zero is not in the data and
  anchoring flattens a year of bodyweight; here, a week you skipped *is* zero
  and has to sit on the baseline.
- **Scrub, don't tap, once the bars are thin.** A year is 52 bars across a
  phone; nothing that narrow is a target. One horizontal drag over the plot
  moves the readout, and it stays out of the list's way because a drag has to
  clear `kTouchSlop` to claim the gesture.
- **Zoom is horizontal only.** Time is the axis with too much in it; scaling the
  value axis makes the same progress look like whatever you last pinched.
- **A point the metric cannot score is not a zero** — it is left out.

### Bar list

The chart that is a list: one row per category, name left, a horizontal bar,
the figure right. No axis, no gridlines, no legend — a bar list whose longest
bar *is* the maximum needs none of them, and they are what turn six rows into a
chart nobody reads.

- Bars are **normalised to the largest row**, never to a target the app has
  invented.
- Height 10, **radius 2 — not a pill**. Pill-ended bars read as lozenges of
  different lengths, and a full radius eats the short ones: a one-unit bar is
  about as wide as its own two end caps.
- The track is `surfaceHighest` and shows full width, so an empty row is still a
  row rather than a gap. A category with nothing in it prints `0` and an empty
  track.
- **One hue per row**, from the six in order, so a row's identity is its colour
  rather than its position.
- Name in `body`, figure in `valueSm` with its unit in `micro` beside it.
- **A row that opens carries a small caret that flips**; chevrons down the left
  of every row are a column of furniture over a column of data. A row with
  nothing to open offers no caret — a control that does nothing is worse than no
  control. What opens is inset, on `surfaceHigh`, and drawn **against the same
  maximum as the rows above it**.

### Table

Column headings in `label` `textTertiary`, then one row per record, **on the
page rather than in a card** so the first column starts on the page gutter and
shares a vertical with everything else on the screen. Value columns are
equal-width and expanding: a fixed narrow column beside an expanding one makes
one field twice the other for no reason a reader can see.

| Element | Spec |
| --- | --- |
| **Index chip** | A circle filling the index column, `valueSm`. A row of a special kind is marked by **a letter *and* a colour**, the hue **blended into `surfaceHigh` rather than laid over it at low alpha** — a translucent tint picks up whatever is behind it and comes out a different colour on different grounds. |
| **Value field** | `surfaceHigh` fill, radius 12, height 48, centred `valueSm`. Focused: **transparent fill plus a 2px `accent` outline** — focus is an outline on nothing, because a fill *and* a border is two signals for one state. |
| **Ghost value** | A suggestion sits **inside** the field as `textTertiary` text — no dot, no italic — because you compare against it at the moment you are deciding, and a separate column costs the width the value needs. No synthesised italic anywhere: with no italic face bundled, the renderer shears the upright glyphs. |
| **Completed row** | Values dim to `textSecondary`, fields drop from `surfaceHigh` to `surface`, and the checkbox goes solid. Dull, not black — at `surfaceSunken` a finished row reads as a hole cut in the table. Never struck through or recoloured. |
| **Split cell** | A value that is really two numbers is **two boxes with one seam** — square on the shared side, rounded away from it, 2px apart — not one box holding an expression. `13+1` asks the eye to do arithmetic at arm's length to find a number that is not even the sum. Split, the halves are **50-50**: both are what the record is made of, and a sliver beside a wide box reads as an afterthought stuck on the end. The second half **only exists once there is something in it**: a number recorded on the row, a number the ghost is carrying from last time, or the pad asking for one. The pad's toggle is a **plain toggle** — `P` opens the half, `F` closes it — and an empty half never outlives the toggle that opened it. It slides out from the right edge over `Motion.fast` rather than snapping, because the first half halves in width when it opens. Empty reads as a dim `–`, never a `0`. **Both halves take focus on their own tap** — a field you can see and cannot type into is a broken field — but **a tap never closes the half**: only the pad's `F` does, or moving to another cell. Tapping the first half to correct it would otherwise take away the box the second number was opened for. The heading names the column once — not the halves, which are not always there. |
| **Delete** | **Swipe the row left** to uncover a `negative` button, then tap it. The **whole** row travels, and the button is **carried in by the row** — parked one panel past the edge and clipped until the swipe brings it in, never a static panel uncovered underneath. The swipe reveals; it never deletes on release. A tap anywhere else, or a swipe on another row, closes it. |

### The numeric keypad

A docked pad instead of the OS keyboard: the system keyboard has small targets,
a layout that shifts, and no notion of "one plate more". This one keeps the
table visible above it.

`surfaceSunken` bed. Digits are bare glyphs with no key background; utility keys
are `surfaceHigh` rounded rects; the advance key is `accent`. **No title and no
readout** — the field being typed into is outlined in the table above, and the
digits land in it as they are pressed. A pad that captions itself is a pad
covering the thing it is captioning.

- **The digits run `1 2 3` on the top row.** Every pad this thumb already uses
  — the dialler, the passcode, the timer — counts downwards, and a pad that
  counts upwards is one that has to be looked at.
- **Step keys move by the unit of the field**, and say so: one plate for a load,
  one rep for a count, half a minute for a time (`+0:30`, never `+30`).
- **On an empty buffer, a step starts from last time.** "One plate more than
  last time" is the most common intent there is.
- **A ceiling is on the value, not the digit count.** Counting characters lets
  `999.99` through and refuses `1000.5` for being long rather than for being
  wrong.
- **The advance key names what it does** — `Next`, `Done`, or a question when
  the field still owes an answer.
- Anything a movement's numbers imply — a plate diagram for a barbell load —
  grows in above the digits and **collapses to nothing** when it does not apply,
  rather than reserving a band that is empty most of the time.
- **`F` / `P` says whether the set is being given partials**, not which box the
  digits are in. `P` opens the partial half in the table above and puts the
  digits there; `F` closes it again, and is the **only** control that does —
  and because it says the set is all full reps, it **drops whatever partials
  were recorded on it**, rather than leaving a number behind a shut box.
  Tapping a box moves the digits into that box and leaves the key alone — the
  half is still open, so a key that flipped back to `F` would be reporting a
  mode change nobody made. Both halves stay lit so the state is readable
  without looking at the table. It appears only where partials exist — a count, never a load and never
  a hold — and it takes the slot the decimal point sits in on a load. It is for
  changing your mind mid-entry; the way *in* is tapping the half of the count
  cell you meant.

### The stopwatch pad

Some values are found rather than known, and a value you read off a clock
elsewhere and copy in is a value typed twice. Where that is true, the keypad's
slot takes a stopwatch instead.

- The clock in `value` at 44sp, `m:ss`. Whatever the stopwatch showed is what
  the table shows.
- **It counts up with the previous figure marked** — a 4pt bar filling toward
  it, `accent` under and `positive` past, the clock turning `positive` at the
  same moment. Never a countdown: a target you stop at is the wrong shape for
  "as long as you can".
- **One key.** Start, then Stop in `accent`, in the place the advance key sits.
  Stopping writes the value and completes the record. A stop inside the first
  second writes nothing — that is a mis-tap.
- **A small pill returns the digits** for a value measured elsewhere. It is a
  pill with a glyph rather than a bare word, because a word beside a 44sp
  readout does not read as pressable, and it disappears while the clock runs.
- **A time is typed as a clock**: digits fill from the right (`2` → `0:02`,
  `225` → `2:25`), four wide, and a keystroke that would push the seconds past
  59 is refused rather than carried silently into the next minute.

### Day picker

A month grid in a **dialog**, never the platform picker — which arrives centred
with its own type scale, its own ripples and an accent from the framework's
colour scheme, and makes every screen that asks "which day?" answer in a
different app.

It is the one picker **read before it is tapped**, which is why it is not a
sheet: a sheet puts the month you are reading under your thumb.

`‹ March 2026 ›` in `title` across the top, the name itself opening a year grid;
weekday initials in `label` `textTertiary`; 38dp day circles; **six rows
always**, so a page turn is not a resize. Three states stack on one circle,
ranked so none hides another: a **ring in the day's own colour** for a day with
something in it, an **`accent` fill** for the day chosen, a **`textTertiary`
ring** for today. A day outside the range is shown and dead rather than removed,
so the month keeps its shape and the hole says why.

### Mastheads and app bars

**A destination gets a masthead: an eyebrow over a page title, and the title
names the screen** in sentence case. The eyebrow states what the page holds — a
date, a span, an inventory. A destination with no honest eyebrow yet takes the
wider top gap rather than printing a number nothing measured.

**Everything pushed wears the app bar instead**: back arrow left, small centred
`title`, actions right. A detail screen in a 30sp masthead reads as somewhere
you navigated *to* rather than *into*, and there is then no way back up.

**The band does not scroll and holds only the masthead** — the name, the
eyebrow, and at most one quiet line about the state of things. Anything the
centred title has no room for goes in a `surface` block directly under the bar,
sharing its colour so the two read as one header. A block put *inside* the band
shares its surface and so has no boundary of its own, which is how a header ends
up running half the screen with the first real section starting somewhere in the
middle of it, unmarked.

**A control that governs the page pins; the content scrolls under it.** The
thing you change stays reachable, and the thing you read never permanently owns
half the screen.

### Bottom navigation

`surface` bar, 1px top hairline, height 62 plus safe area. Selected is a white
icon and a white `micro` label at weight 700; unselected is `textSecondary` for
both. **No pill, no indicator, no hue** — weight and brightness carry the state.

### Badges

A status pill: radius 999, a 14% tint of the semantic colour, text in that
colour at `micro`. Used sparingly, and never for anything a row already says.

---

## 8. Composing a screen

**A screen is a masthead, then sections on the page background.** A section is a
heading and either one list card or a chart. Everything actionable lives in a
section, never in the band.

**One noun, one screen.** A thing is looked at, edited and created on the same
page. Three shapes for one noun — a read-only view, an edit sheet and a create
sheet — means editing something looks nothing like looking at it.

**Editing is rows that open one question at a time, not a form.** No dropdowns:
a menu dropped over the page has no room to say what an option *means*.

- **An existing thing saves as you go. A new one holds a draft** behind one
  create button, so a half-filled thing abandoned by a back-swipe never lands in
  the data.
- **Every question shows `Choose` until it is answered**, and the create button
  stays off until all of them are. A field pre-set to a plausible value is a
  guess wearing the clothes of an answer, and once the sheet closes the two are
  indistinguishable.
- The exception is a field with a **true default** — a value that is right
  unless stated otherwise. It shows that value rather than `Choose`, because a
  required question whose answer is the same ninety-nine times in a hundred is
  ceremony.
- **Changing a field on something that already exists asks first**, and a field
  that changes how existing records are *read* asks the harder version, counting
  what it is about to reinterpret.

**Creation is a sheet, or one screen. Never a wizard.** No illustrated intro, no
progress bar, no "we will build you a plan" framing — the user is the planner.
One question per sheet; if a second is genuinely required it is a second sheet.

**The welcome screen is the one illustrated page, and it is not a wizard.** The
rule above bans an illustrated intro in front of *creating something* — the
regime flow, where a drawing would stand between the user and the thing they
came to build. The welcome screen is a different object: one screen, one
question, asked once, with the answer that skips it given equal standing on the
page.

It stays inside the rule as long as all of this is true:

- **One screen, never two.** No carousel, no progress dots, no "next".
- **One question**, and it is not about training. It is where the history is
  kept, which is the only thing the app cannot infer.
- **Declining is a real answer, not a delay.** `Use without an account` is a
  plain text action directly under the primary — not greyed, not small print,
  not a corner `Skip`. Choosing it is final and repairable: Settings offers the
  same connection later, and nothing nags.
- **Seen once.** Answered either way, it never appears again.
- **It says what it will do before it asks.** The subtitle names the outcome —
  a history that survives a lost phone — rather than the mechanism.

The composition, top to bottom: the mark, the illustration, a `display` line, a
`body` line under it, the primary button, an `OR` rule, the decline action.
Centred, generous vertical space, everything inside the gutter. It is the only
screen in the app with a centred `display` line, which is what makes it read as
a threshold rather than as a page.
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
| Bar list | `lib/features/today/widgets/volume_bars.dart` |

Feature code composes these; it does not restyle them. **A component nothing
calls is deleted**, not left for later — it is a second answer to a question
that already has one.
