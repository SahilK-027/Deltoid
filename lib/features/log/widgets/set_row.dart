import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/db/database.dart';
import '../../../domain/enums.dart';
import '../../../domain/metrics.dart';
import '../../../domain/prefill.dart';
import '../../../domain/units.dart';
import '../log_screen.dart';
import 'keypad.dart';

export 'keypad.dart'
    show
        SetField,
        SetFieldX,
        SetKeypad,
        applyKey,
        digitsFromSeconds,
        formatDigits,
        secondsFromDigits;

/// The colour a set type is marked in.
///
/// Warm-ups and drops are the two types this app actually has, and both are
/// facts about the set rather than chrome — so they get a hue, and a working
/// set stays grey. Without this the only difference between a warm-up and a
/// top set was one letter in the same colour as everything around it.
Color setTypeColour(BuildContext context, SetType type) => switch (type) {
  SetType.warmup => context.c.warmup,
  SetType.drop || SetType.restPause => context.c.dropSet,
  _ => context.c.textSecondary,
};

/// The column headings above the set table.
///
/// The units live here and nowhere else. A `kg` / `reps` suffix inside every
/// field is the same word printed five times down a column, and it takes a
/// chunk of the width of a field you have to read a number out of at arm's
/// length.
class SetTableHeader extends StatelessWidget {
  const SetTableHeader({
    super.key,
    required this.loadMode,
    required this.unit,
    this.measure = MeasureMode.reps,
  });

  final LoadMode loadMode;
  final WeightUnit unit;

  /// Names the second column: `Reps`, or `Time` for a hold. The heading is the
  /// only place a column's unit is said, and the clock in the cells under it
  /// does the rest — `2:25` cannot be mistaken for a rep count.
  final MeasureMode measure;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // `label`, the role THEME → Type gives table headers, and sentence case:
    // the spec's own header row reads `Set · kg · Reps · ✓`.
    final label = context.t.bodySmall?.copyWith(color: c.textTertiary);
    // The gutter is the page's, so the SET column starts on the same vertical
    // as the exercise name above it. In a card the table is inset a second
    // time by the card's own padding, and lines up with nothing.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          SizedBox(
            width: SetRow.indexColumn,
            child: Text('Set', style: label),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              loadMode == LoadMode.bodyweight ? 'Load' : unit.label,
              style: label,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: Space.sm),
          // Load and reps are the same width. Reps had a fixed 68 against an
          // expanding load column, which on a phone made one field twice the
          // other for no reason a reader could see.
          // One heading, whether or not a row below it has split its count
          // cell. The split comes and goes per row, and a `Part` column
          // standing over rows that mostly have no such cell is a heading for
          // something that is not there.
          Expanded(
            child: Text(
              measure.columnLabel,
              style: label,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: Space.sm),
          SizedBox(
            width: SetRow.doneColumn,
            child: Icon(Icons.check_rounded, size: 14, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One set: index, load, reps, done.
///
/// Last time's numbers sit in the fields as ghost text rather than in a
/// separate column — you compare against them at the exact moment you're
/// deciding what to lift, and beating one lights up immediately.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.loadMode,
    required this.unit,
    this.measure = MeasureMode.reps,
    required this.ghost,
    required this.editing,
    required this.buffer,
    required this.onEdit,
    required this.onEditPartial,
    required this.onToggleDone,
    this.partialShownFor,
    this.partialClosedFor,
    this.partialEditing = false,
  });

  static const indexColumn = 34.0;
  static const doneColumn = 40.0;
  static const fieldHeight = 42.0;

  /// The sliding partial half, so a test can measure whether it is actually
  /// on screen — it stays in the tree, clipped to nothing, while it is shut.
  static const partialHalfKey = ValueKey('set-row-partial-half');

  /// The seam between the two halves of a split count cell. They take half
  /// the column each; this is the hairline of background between them.
  static const splitGap = 2.0;

  /// A row's full height, fields plus their padding. The index column beside
  /// it is sized to this so a drop group's capsule lines up with its rows
  /// without stretching them — `CrossAxisAlignment.stretch` cannot do that job
  /// inside a scroll view, where the vertical constraint is unbounded.
  static const rowHeight = fieldHeight + Space.xs * 2;

  final SetLog set;
  final LoadMode loadMode;
  final WeightUnit unit;

  /// Decides what the count column holds — reps, or a clock.
  final MeasureMode measure;

  final PastSet? ghost;

  /// The set whose count cell is showing its partial half.
  ///
  /// Both halves take focus on their own tap — a field you can see and cannot
  /// type into is a broken field — but a tap never *closes* the half: only the
  /// pad's `F` does that, or moving to another cell. Tapping the reps to fix
  /// them would otherwise take away the box the partials were opened for.
  final String? partialShownFor;

  /// The set whose partials `F` has just dropped.
  ///
  /// Beats every reason to show the half. Without it the box would spring
  /// straight back open — on this set's own number, which the clearing write
  /// has not yet taken away, or on the ghost's, which nothing can.
  final String? partialClosedFor;

  /// Which half the digits are going into. Follows the last tap, and the pad's
  /// `F` / `P`.
  final bool partialEditing;

  final EditTarget? editing;
  final ValueListenable<String> buffer;
  final void Function(SetLog, SetField) onEdit;

  /// Opens the count field with the digits going into the partial half — what
  /// tapping that half means.
  final void Function(SetLog) onEditPartial;

  final void Function(SetLog, bool) onToggleDone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final beaten = _beatsGhost();

    // The count column is one cell until there is a second number in it.
    //
    // Partials are the exception, not the shape of every set, so the split is
    // asked for — by `P` on the pad, which closes it again on `F` — or already
    // earned by a number that is there to be read. Showing it on every row put
    // an empty box on the table five times an exercise and made the reps
    // narrower to do it. A hold never splits: there is no half-second.
    final editingThis = editing?.setId == set.id;
    final split =
        !measure.isHold &&
        partialClosedFor != set.id &&
        ((editingThis && partialShownFor == set.id) ||
            (set.partialReps ?? 0) > 0 ||
            // Last time's partials open it too. A ghost that quietly drops
            // half of what the set was is a ghost you cannot match: `8` where
            // the week before read `8+3` says you did the same set, and you
            // did not. Only until the set is ticked: a finished set with no
            // partials of its own was all full reps, and a box still holding
            // last week's number would claim halves that were not done.
            (!set.isDone && (ghost?.partialReps ?? 0) > 0));

    // Swipe-to-delete wraps this from the group above, so the index column
    // travels with the fields. See [SwipeToDelete].
    //
    // No indent for a drop set either. Indenting shifted every field on the row
    // out of its column, so the table stopped lining up exactly where it is
    // being read fastest — the letter in the index chip carries it instead.
    // The completed row's wash is painted by the group, not here: it has to
    // run under the index column too, and painting it inside the row left the
    // chip sitting in an unwashed notch at the start of every logged set.
    //
    // Horizontal padding is the group's, not this row's. Applying it here as
    // well inset every field a further [Space.lg] from the edge the header had
    // measured its columns against, so REPS sat off its column, the unit sat
    // off the load field, and the tick in the header pointed between the
    // checkbox and the edge of the card.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          if (loadMode == LoadMode.bodyweight)
            Expanded(
              child: Text(
                'Bodyweight',
                textAlign: TextAlign.center,
                style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            )
          else
            Expanded(
              child: _ValueCell(
                unit: unit,
                field: loadMode == LoadMode.bodyweightPlus
                    ? SetField.added
                    : SetField.weight,
                prefix: loadMode == LoadMode.bodyweightPlus ? 'BW +' : null,
                value: loadMode == LoadMode.bodyweightPlus
                    ? set.addedWeight
                    : set.weight,
                ghost: loadMode == LoadMode.bodyweightPlus
                    ? ghost?.addedWeight
                    : ghost?.weight,
                done: set.isDone,
                active:
                    editing?.setId == set.id &&
                    editing?.field ==
                        (loadMode == LoadMode.bodyweightPlus
                            ? SetField.added
                            : SetField.weight),
                buffer: buffer,
                onTap: () => onEdit(
                  set,
                  loadMode == LoadMode.bodyweightPlus
                      ? SetField.added
                      : SetField.weight,
                ),
              ),
            ),
          const SizedBox(width: Space.sm),
          Expanded(
            // Split, the two numbers get **half each**. The partial count is
            // not a lesser number than the reps once it exists — it is the
            // other half of what the set was — and a sliver beside a wide box
            // reads as an afterthought stuck on the end.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final half =
                    (constraints.maxWidth - SetRow.splitGap) / 2 +
                    SetRow.splitGap;
                return Row(
                  children: [
                    Expanded(
                      child: _ValueCell(
                        unit: unit,
                        field: SetField.reps,
                        isTime: measure.isHold,
                        value: set.reps?.toDouble(),
                        ghost: ghost?.reps?.toDouble(),
                        done: set.isDone,
                        active:
                            editingThis &&
                            editing?.field == SetField.reps &&
                            !partialEditing,
                        buffer: buffer,
                        onTap: () => onEdit(set, SetField.reps),
                        // Squared off against the partial half only while
                        // there is one to share a seam with. On its own the
                        // cell is an ordinary field, rounded all round.
                        radius: split
                            ? const BorderRadius.horizontal(
                                left: Radius.circular(Radii.cell),
                              )
                            : null,
                      ),
                    ),
                    // The half slides out from the right edge rather than
                    // appearing: the reps cell halves in width when it opens,
                    // and a field that jumps a thumb's width mid-set is a
                    // field you mis-tap. Laid out at its full width behind the
                    // clip throughout, so the number never reflows while it
                    // travels.
                    ClipRect(
                      child: AnimatedContainer(
                        key: SetRow.partialHalfKey,
                        duration: Motion.fast,
                        curve: Motion.curve,
                        width: split ? half : 0,
                        height: SetRow.fieldHeight,
                        child: OverflowBox(
                          alignment: Alignment.centerRight,
                          minWidth: half,
                          maxWidth: half,
                          child: Row(
                            children: [
                              const SizedBox(width: SetRow.splitGap),
                              Expanded(
                                child: _PartialCell(
                                  value: set.partialReps,
                                  ghost: set.isDone ? null : ghost?.partialReps,
                                  done: set.isDone,
                                  active: editingThis && partialEditing,
                                  buffer: buffer,
                                  onTap: () => onEditPartial(set),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: Space.sm),
          _DoneBox(
            done: set.isDone,
            beaten: beaten,
            onTap: () => onToggleDone(set, !set.isDone),
          ),
        ],
      ),
    );
  }

  /// True when this set beats the same slot last time.
  bool _beatsGhost() {
    final g = ghost;
    if (g == null || !set.isDone) return false;

    // Bodyweight is held constant: within a single comparison it is the same
    // number on both sides, so it cancels and cannot skew the result.
    const assumedBodyweight = 100.0;

    return beatsPrevious(
      load: effectiveLoad(
        mode: loadMode,
        weight: set.weight,
        addedWeight: set.addedWeight,
        bodyweightKg: assumedBodyweight,
      ),
      reps: set.reps,
      previousLoad: effectiveLoad(
        mode: loadMode,
        weight: g.weight,
        addedWeight: g.addedWeight,
        bodyweightKg: assumedBodyweight,
      ),
      previousReps: g.reps,
    );
  }
}

/// Slides a row left to uncover a delete button.
///
/// Not a [Dismissible]: that deletes on release, and a set logged an hour ago
/// should not be one careless flick from gone. This opens and stays open, so
/// the delete is a second, deliberate tap — and a tap anywhere else, or a swipe
/// on another row, closes it again.
///
/// Wraps the **whole** row — index column included — and not just the fields.
/// Wrapped around the fields alone, a swipe slid the weight, the reps and the
/// checkbox out from under a chip that stayed exactly where it was, which reads
/// as the table coming apart rather than as one row moving.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.rowId,
    required this.open,
    required this.onDelete,
    required this.child,
  });

  final String rowId;
  final ValueNotifier<String?> open;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  /// How far the row slides, and the width of the button it brings in with it.
  /// The done column's width, so the delete lands where the checkbox was.
  static const _panel = SetRow.doneColumn;

  double _dx = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.open.removeListener(_onOpenChanged);
    super.dispose();
  }

  void _onOpenChanged() {
    if (widget.open.value == widget.rowId || _dx == 0) return;
    setState(() => _dx = 0);
  }

  void _settle(double velocity) {
    // A flick counts even if it did not travel far: the gesture is over by the
    // time your thumb has left the screen, and re-dragging to a threshold is
    // not something anyone does twice.
    final opening = velocity < -300 || (velocity <= 300 && _dx < -_panel / 2);
    setState(() {
      _dragging = false;
      _dx = opening ? -_panel : 0;
    });
    if (opening) {
      widget.open.value = widget.rowId;
    } else if (widget.open.value == widget.rowId) {
      widget.open.value = null;
    }
  }

  void _close() {
    setState(() => _dx = 0);
    if (widget.open.value == widget.rowId) widget.open.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final revealed = _dx < 0;

    return GestureDetector(
      // Open, the row itself stops taking taps: a thumb landing on a field
      // that has been slid half a column to the left means "put it back", not
      // "type into this".
      onTap: revealed ? _close : null,
      // Opaque, not the default `deferToChild`. Open, the row under this is
      // wrapped in an [IgnorePointer] so a stray tap can't type into a field
      // that has slid half a column sideways — and with nothing beneath it
      // registering a hit, a `deferToChild` detector never saw the drag either.
      // The row could be swiped open and then not swiped shut again.
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (d) =>
          setState(() => _dx = (_dx + d.delta.dx).clamp(-_panel, 0.0)),
      onHorizontalDragEnd: (d) => _settle(d.velocity.pixelsPerSecond.dx),
      onHorizontalDragCancel: () => _settle(0),
      child: Stack(
        // The button lives past the row's right edge and is clipped away until
        // the swipe brings it in. Sitting still underneath, it does not read as
        // part of the row at all: the row leaves, and a red panel it was hiding
        // is simply there.
        clipBehavior: Clip.hardEdge,
        children: [
          AnimatedContainer(
            // Follows the thumb exactly while dragging; springs back after.
            duration: _dragging ? Duration.zero : Motion.fast,
            curve: Motion.curve,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: IgnorePointer(ignoring: revealed, child: widget.child),
          ),
          // Offset by the same [_dx] as the row, so the two travel as one
          // piece. `right: -_panel` parks it exactly one panel past the edge.
          AnimatedPositioned(
            duration: _dragging ? Duration.zero : Motion.fast,
            curve: Motion.curve,
            top: 0,
            bottom: 0,
            right: -_panel - _dx,
            width: _panel,
            child: Pressable(
              onTap: () {
                _close();
                widget.onDelete();
              },
              child: Center(
                // The checkbox's geometry, in the checkbox's place at the end
                // of the row: same 28dp square, same 18dp glyph. A 42dp-tall
                // slab was the biggest thing in the table and it only ever
                // appears when you are about to take a row away.
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.negative,
                    borderRadius: BorderRadius.circular(Radii.mark),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatefulWidget {
  const _ValueCell({
    required this.field,
    required this.unit,
    this.isTime = false,
    required this.value,
    required this.ghost,
    required this.done,
    required this.active,
    required this.buffer,
    required this.onTap,
    this.prefix,
    this.radius,
  });

  final SetField field;

  /// Reps are unitless; weights are stored in kg and shown in this.
  final WeightUnit unit;

  /// A hold's count is seconds, and is read as `2:25` — in the cell, in the
  /// ghost behind it, and while it is being typed.
  final bool isTime;

  final double? value;
  final double? ghost;
  final bool done;
  final bool active;
  final ValueListenable<String> buffer;
  final VoidCallback onTap;
  final String? prefix;

  /// Squared off on the side it shares a seam with, when this cell is one half
  /// of a split one. Null is the ordinary all-round [Radii.cell].
  final BorderRadius? radius;

  @override
  State<_ValueCell> createState() => _ValueCellState();
}

class _ValueCellState extends State<_ValueCell> {
  /// Brief wash after a ghost turns into a real value, so adoption is something
  /// you see happen rather than something you infer from grey becoming white in
  /// gym lighting.
  bool _flash = false;
  Timer? _flashEnd;

  @override
  void didUpdateWidget(_ValueCell old) {
    super.didUpdateWidget(old);
    if (old.value == null && widget.value != null && !widget.active) {
      _flashEnd?.cancel();
      setState(() => _flash = true);
      _flashEnd = Timer(Motion.slow, () {
        if (mounted) setState(() => _flash = false);
      });
    }
  }

  @override
  void dispose() {
    _flashEnd?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the cell being typed into listens to the keypad buffer, so a
    // keystroke repaints one cell rather than the page.
    if (!widget.active) return _build(context, _fmt(widget.value, widget));
    return ValueListenableBuilder<String>(
      valueListenable: widget.buffer,
      // A clock buffer holds the digits typed so far, not a number: `225` is
      // shown as `2:25` from the third keystroke, the way the field will read
      // once it is written.
      builder: (context, buffer, _) =>
          _build(context, widget.isTime ? formatDigits(buffer) : buffer),
    );
  }

  Widget _build(BuildContext context, String display) {
    final c = context.c;
    final hasValue = display.isNotEmpty;
    final ghostText = _fmt(widget.ghost, widget);
    // A suggestion must never look like a record — but colour alone carries
    // that, and it always did. The leading dot cost a fifth of a field that
    // has to hold `102.5` and be read from the floor, and it marked the one
    // thing on the row you most want to read as a number.
    //
    // Not italic either: no italic face is bundled, so Skia would synthesise a
    // slant by shearing the upright glyphs, and faux oblique is the
    // cheapest-looking thing that can go on this screen.

    // A logged set steps back: its numbers are settled, and the row you are
    // working on has to be the brightest thing in the table. This and the solid
    // checkbox say "done", rather than a wash running the width of the card,
    // which is the loudest band on the screen (THEME → Components).
    final valueColour = !hasValue
        ? c.textTertiary
        : (widget.done ? c.textSecondary : c.textPrimary);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: SetRow.fieldHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        decoration: BoxDecoration(
          // Focus is an outline on nothing, not a tinted box: the field being
          // typed into should read as open, and a fill plus a border is two
          // signals for one state.
          // A logged row keeps its boxes. Dropping them collapsed the two
          // columns into one run of text, so a finished set stopped lining up
          // with the unfinished ones underneath it.
          // A finished set goes dull, not black. `surfaceSunken` is very nearly
          // the page colour, so a logged row read as a hole cut in the table
          // instead of as work already done.
          color: widget.active
              ? Colors.transparent
              : (_flash
                    ? c.surfaceHighest
                    : (widget.done ? c.surface : c.surfaceHigh)),
          borderRadius: widget.radius ?? BorderRadius.circular(Radii.cell),
          border: Border.all(
            color: widget.active ? c.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.prefix != null) ...[
              // The same size as the number it qualifies. A size down reads as
              // a superscript on `BW + 10` rather than as the first half of one
              // value — the two are one reading, and the eye should not have to
              // change gear between them. Still tertiary:
              // quieter than the number, because the number is what changes.
              Text(
                widget.prefix!,
                style: context.t.labelLarge?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                hasValue ? display : (ghostText.isEmpty ? '—' : ghostText),
                style: context.t.labelLarge?.copyWith(color: valueColour),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double? v, _ValueCell cell) {
    if (v == null) return '';
    if (cell.isTime) return formatClock(v.round());
    if (cell.field == SetField.reps) {
      return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    }
    return formatInUnit(v, cell.unit);
  }
}

/// The other half of the count cell: reps that did not finish the range of
/// motion.
///
/// A cell of its own rather than a suffix on the reps. `13+1` in one box asks
/// the eye to parse an arithmetic expression to find out how many reps were
/// done, at arm's length, mid-set — and the answer is not the sum. Two boxes
/// with one seam say the same thing without being read twice.
///
/// Empty is the normal state and it stays quiet: a hairline outline and a dim
/// dash, not a zero. A zero is a number, and this column mostly has no number
/// in it.
class _PartialCell extends StatelessWidget {
  const _PartialCell({
    required this.value,
    required this.ghost,
    required this.done,
    required this.active,
    required this.buffer,
    required this.onTap,
  });

  final int? value;

  /// What this set's partials were last time, sitting in the cell the way
  /// every other ghost on the row does. Shown only — [PastSet.partialReps]
  /// explains why it is never adopted.
  final int? ghost;

  final bool done;
  final bool active;
  final ValueListenable<String> buffer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!active) return _build(context, (value ?? 0) == 0 ? '' : '$value');
    return ValueListenableBuilder<String>(
      valueListenable: buffer,
      builder: (context, buffer, _) => _build(context, buffer),
    );
  }

  Widget _build(BuildContext context, String display) {
    final c = context.c;
    final hasValue = display.isNotEmpty;
    final ghostText = (ghost ?? 0) == 0 ? '' : '$ghost';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        height: SetRow.fieldHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Dimmer than the reps half even when it holds a number: this is a
          // note on the set, not the result of it.
          color: active
              ? Colors.transparent
              : (done ? c.surface : c.surfaceHigh),
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(Radii.cell),
          ),
          border: Border.all(
            color: active ? c.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          hasValue ? display : (ghostText.isEmpty ? '–' : ghostText),
          style: context.t.labelLarge?.copyWith(
            color: hasValue
                ? (done ? c.textSecondary : c.textPrimary)
                : c.textTertiary,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

/// The set's number, or its letter. Also the way into the set's own actions —
/// type, note, delete — because the row has no room for a trailing menu and the
/// screen has no spare horizontal gesture to give a swipe.
class SetIndexChip extends StatelessWidget {
  const SetIndexChip({
    super.key,
    required this.type,
    required this.label,
    required this.done,
    required this.onTap,
  });

  final SetType type;
  final String label;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final typed = type != SetType.working;
    final colour = setTypeColour(context, type);

    // The chip fills the index column exactly, so on a drop group it covers the
    // head of the capsule rather than sitting proud of it as a second bulge.
    return Pressable(
      onTap: onTap,
      child: Container(
        width: SetRow.indexColumn,
        height: SetRow.indexColumn,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Blended, not translucent. A 18% amber laid over whatever happened
          // to be behind it picked up the drop capsule's grey and came out a
          // washed olive — the tint has to be the same colour on the capsule
          // as off it, and strong enough to read as amber at arm's length.
          color: typed
              ? Color.alphaBlend(colour.withValues(alpha: 0.32), c.surfaceHigh)
              : c.surfaceHigh,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: context.t.bodySmall?.copyWith(
            color: typed ? colour : (done ? c.textTertiary : c.textSecondary),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DoneBox extends StatelessWidget {
  const _DoneBox({
    required this.done,
    required this.beaten,
    required this.onTap,
  });

  final bool done;

  /// Beat the same slot last time. The one place on this row where colour is
  /// allowed, because it is the only thing here that is a finding rather than
  /// a record.
  final bool beaten;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // An actual checkbox: empty square when open, filled when ticked. A filled
    // grey block with a grey tick already in it reads as "completed" on every
    // row, which makes the real completed state invisible.
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: SetRow.doneColumn,
        height: SetRow.fieldHeight,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done
                  ? (beaten ? c.positive : c.accent)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.mark),
              border: Border.all(
                color: done ? Colors.transparent : c.textTertiary,
                width: 2,
              ),
            ),
            child: done
                ? Icon(
                    beaten ? Icons.trending_up_rounded : Icons.check_rounded,
                    size: 18,
                    color: c.onAccent,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
