import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../domain/enums.dart';
import '../../domain/set_format.dart';
import '../../domain/units.dart';

/// What the sheet came back with: the corrected numbers, or a deletion.
///
/// A field left as it was opened is null rather than its old value, so the
/// caller writes only the columns that were retyped. A load shown in pounds
/// does not survive a round trip through its own display rounding, and saving
/// a corrected rep count must not move the weight beside it by a fraction of a
/// kilogram.
typedef LoggedSetEdit = ({
  bool delete,
  ({double? kg})? load,
  int? count,
  ({int? reps})? partial,
  SetType? setType,
});

/// Corrects one set of a session that has already ended.
///
/// Opened from the set's line on the logged day, which is where the wrong
/// number is noticed. Returns null when dismissed.
Future<LoggedSetEdit?> showLoggedSetSheet(
  BuildContext context, {
  required SetLog set,
  required Exercise exercise,
  required WeightUnit unit,

  /// The working-set number on the line's chip, as `setTitle` takes it.
  required String label,

  /// Which leg of a drop group, counting the head as 1. Null outside one.
  int? leg,

  /// How many rows a delete removes. A drop group's head takes its legs.
  int deleteCount = 1,
}) {
  return showAppSheet<LoggedSetEdit>(
    context,
    builder: (_) => _LoggedSetSheet(
      set: set,
      exercise: exercise,
      unit: unit,
      label: label,
      leg: leg,
      deleteCount: deleteCount,
    ),
  );
}

/// The ceilings the log's keypad holds a typed number to (`maxEntry` and
/// `maxHoldSeconds` in `keypad.dart`), repeated as limits on a field the OS
/// keyboard types into.
const _maxLoad = 1000.0;
const _maxReps = 999;
const _maxHoldSeconds = 99 * 60 + 59;

class _LoggedSetSheet extends StatefulWidget {
  const _LoggedSetSheet({
    required this.set,
    required this.exercise,
    required this.unit,
    required this.label,
    required this.leg,
    required this.deleteCount,
  });

  final SetLog set;
  final Exercise exercise;
  final WeightUnit unit;
  final String label;
  final int? leg;
  final int deleteCount;

  @override
  State<_LoggedSetSheet> createState() => _LoggedSetSheetState();
}

class _LoggedSetSheetState extends State<_LoggedSetSheet> {
  late final String _loadWas = _storedLoad == null
      ? ''
      : formatWeight(_storedLoad!, widget.unit);
  late final String _countWas = widget.set.reps?.toString() ?? '';
  late final String _partialWas = widget.set.partialReps?.toString() ?? '';

  late final _load = TextEditingController(text: _loadWas);
  late final _count = TextEditingController(text: _countWas);
  late final _partial = TextEditingController(text: _partialWas);
  late SetType _type = widget.set.setType;

  LoadMode get _loadMode => widget.exercise.loadMode;
  bool get _isHold => widget.exercise.measureMode.isHold;

  /// A bodyweight movement has no load to correct.
  bool get _hasLoad => _loadMode != LoadMode.bodyweight;

  /// The column the load field edits: the added weight on a weighted
  /// bodyweight movement, the weight everywhere else.
  double? get _storedLoad => _loadMode == LoadMode.bodyweightPlus
      ? widget.set.addedWeight
      : widget.set.weight;

  @override
  void dispose() {
    _load.dispose();
    _count.dispose();
    _partial.dispose();
    super.dispose();
  }

  /// The typed load in the display unit. Null when the field does not hold one.
  ///
  /// An empty field is a valid answer and reads as no load recorded, which is
  /// what a row logged without one already says.
  ({double? value})? get _typedLoad {
    final text = _load.text.trim();
    if (text.isEmpty) return (value: null);
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0 || parsed > _maxLoad) return null;
    return (value: parsed);
  }

  /// The typed reps, or seconds for a hold. Null when the field holds neither.
  int? get _typedCount {
    final parsed = int.tryParse(_count.text.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed > (_isHold ? _maxHoldSeconds : _maxReps) ? null : parsed;
  }

  /// The typed partials. Empty and zero both mean the set had none.
  ({int? value})? get _typedPartial {
    final text = _partial.text.trim();
    if (text.isEmpty) return (value: null);
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0 || parsed > _maxReps) return null;
    return (value: parsed == 0 ? null : parsed);
  }

  bool get _loadChanged => _hasLoad && _load.text.trim() != _loadWas;
  bool get _countChanged => _count.text.trim() != _countWas;
  bool get _partialChanged => !_isHold && _partial.text.trim() != _partialWas;
  bool get _typeChanged => _type != widget.set.setType;

  bool get _valid =>
      (!_hasLoad || _typedLoad != null) &&
      _typedCount != null &&
      (_isHold || _typedPartial != null);

  bool get _changed =>
      _loadChanged || _countChanged || _partialChanged || _typeChanged;

  void _save() {
    if (!_valid || !_changed) return;
    final load = _typedLoad?.value;
    Navigator.of(context).pop<LoggedSetEdit>((
      delete: false,
      load: _loadChanged
          ? (kg: load == null ? null : widget.unit.toKg(load))
          : null,
      count: _countChanged ? _typedCount : null,
      partial: _partialChanged ? (reps: _typedPartial!.value) : null,
      setType: _typeChanged ? _type : null,
    ));
  }

  Future<void> _pickType() async {
    final picked = await showAppSheet<SetType>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Set type',
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          // Working first, the type a mis-tagged row is put back to. A drop is
          // not offered: it needs a leg under it, and a leg added to a day
          // that is over is an empty row nothing can fill. A set that already
          // carries another type keeps it on the list, so the row that is
          // ticked is always on screen.
          for (final type in {
            SetType.working,
            SetType.warmup,
            widget.set.setType,
          })
            AppRow(
              title: type.label,
              subtitle: setTypeBlurb(type).isEmpty ? null : setTypeBlurb(type),
              trailing: AppRadio(selected: type == _type),
              onTap: () => Navigator.of(sheet).pop(type),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _type = picked);
  }

  Future<void> _delete() async {
    final group = widget.deleteCount > 1;
    final ok = await confirmAction(
      context,
      title: group ? 'Delete this drop set?' : 'Delete this set?',
      message:
          '${group ? 'All ${widget.deleteCount} legs' : 'The set'} will be '
          'removed from history, the charts and every last-time suggestion.'
          '\n\nThis cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).pop<LoggedSetEdit>((
      delete: true,
      load: null,
      count: null,
      partial: null,
      setType: null,
    ));
  }

  String get _loadLabel {
    final unit = widget.unit.label;
    return switch (_loadMode) {
      LoadMode.perSide => 'Per hand ($unit)',
      LoadMode.bodyweightPlus => 'Added ($unit)',
      _ => 'Weight ($unit)',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppSheet(
      title: setTitle(widget.set.setType, widget.label, widget.leg),
      subtitle: widget.exercise.name,
      footer: PrimaryButton(
        label: 'Save',
        onPressed: _valid && _changed ? _save : null,
      ),
      // Full-width rows with the fields carrying their own gutter, as the
      // weigh-in sheet is built.
      contentPadding: const EdgeInsets.only(bottom: Space.md),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasLoad) ...[
                Expanded(
                  child: _NumberField(
                    label: _loadLabel,
                    controller: _load,
                    decimal: true,
                    onChanged: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: _NumberField(
                  label: _isHold ? 'Seconds' : 'Reps',
                  controller: _count,
                  onChanged: () => setState(() {}),
                ),
              ),
              if (!_isHold) ...[
                const SizedBox(width: Space.md),
                Expanded(
                  child: _NumberField(
                    label: 'Partial reps',
                    controller: _partial,
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
        ),
        AppRow(
          icon: Icons.label_outline_rounded,
          title: 'Set type',
          trailing: RowValue(_type.label),
          onTap: _pickType,
        ),
        AppRow(
          icon: Icons.delete_outline_rounded,
          title: widget.deleteCount > 1
              ? 'Delete this drop set'
              : 'Delete this set',
          tint: c.negative,
          onTap: _delete,
        ),
      ],
    );
  }
}

/// One number of a logged set, under the name of what it is.
///
/// The decoration is the theme's own (THEME → Fields). What the field does —
/// its keyboard, its formatters and its type role — is set here, because those
/// are facts about the value being typed.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.t.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          // A number keyboard is a request, not a constraint: a paste or a
          // hardware keyboard bypasses it, so the characters are filtered too.
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(decimal ? r'[0-9.]' : r'[0-9]'),
            ),
            LengthLimitingTextInputFormatter(decimal ? 7 : 4),
          ],
          textAlign: TextAlign.center,
          style: context.t.labelLarge,
          cursorColor: context.c.textPrimary,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}
