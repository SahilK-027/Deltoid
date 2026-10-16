import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/failure.dart';
import '../../core/ids.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/calendar.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/enums.dart';
import '../../domain/phases.dart';
import 'home_providers.dart';

/// Opens the phase sheet (THEME → Phase sheet), from the Phase card's
/// `Change` or its `Set a phase`.
Future<void> showPhaseSheet(BuildContext context, PhaseCardData data) =>
    showAppSheet<void>(
      context,
      builder: (_) => PhaseSheet(data: data),
    );

/// Bulk, cut or maintenance, the day it started and how long it is planned
/// to run.
///
/// **Choosing a different phase starts a new one; keeping the phase edits
/// it.** With the current phase still selected, `Save` corrects its start day
/// and length. With another, it starts a new phase on the chosen day, and the
/// one before ends there; on the current phase's own start day it replaces
/// it, which is how a mis-tapped phase is corrected.
class PhaseSheet extends ConsumerStatefulWidget {
  const PhaseSheet({super.key, required this.data});

  final PhaseCardData data;

  @override
  ConsumerState<PhaseSheet> createState() => _PhaseSheetState();
}

class _PhaseSheetState extends ConsumerState<PhaseSheet> {
  late final DateTime _today = _midnight(DateTime.now());
  late final PhaseSpan? _current =
      currentPhase(widget.data.spans, todayKey: dayKeyOf(_today));

  /// No selection with no phase set, and `Save` off until there is one: a
  /// pre-set phase is a guess that would tint every cycle from that day.
  late PhaseKind? _kind = _current?.kind;

  /// The two start days are kept apart, so trying another phase and coming
  /// back leaves the current one's start where it was.
  late DateTime _editStart = switch (_current) {
    null => _today,
    final current => dateFromDayKey(current.startKey),
  };

  /// A new phase is usually set on the day it begins.
  late DateTime _newStart = _today;

  /// Twelve weeks for a new phase, the commonest plan.
  late int? _weeks = switch (_current) {
    null => 12,
    final current => current.phase.plannedWeeks,
  };

  bool _saving = false;

  bool get _editing => _current != null && _kind == _current.kind;

  DateTime get _start => _editing ? _editStart : _newStart;

  /// Phases follow one another and never overlap, so the picker refuses the
  /// days that would make them.
  ///
  /// Correcting the current phase may not reach the previous phase's start:
  /// two live phases on one day is a pair the schema refuses, and the previous
  /// phase would cover nothing. Starting a new one may reach back to the
  /// current phase's start, where it replaces it, and no further. With no
  /// phase current, a new one starts after the last one began, so starting a
  /// phase never discards a past one.
  DateTime? get _firstDay {
    final spans = widget.data.spans;
    final current = _current;
    if (_editing && current != null) {
      final before = [
        for (final s in spans)
          if (s.startKey < current.startKey) s,
      ];
      return before.isEmpty
          ? null
          : daysBefore(dateFromDayKey(before.last.startKey), -1);
    }
    if (current != null) return dateFromDayKey(current.startKey);
    if (spans.isEmpty) return null;
    return daysBefore(dateFromDayKey(spans.last.startKey), -1);
  }

  Future<void> _pickStart() async {
    final c = context.c;
    final first = _firstDay;
    final picked = await pickDay(
      context,
      initial: _start,
      first: first,
      last: _today,
      title: 'When did it start?',
      // The weigh-ins, because a phase is read against them.
      marks: {for (final e in widget.data.log) e.dayKey: c.weighIn},
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_editing) {
        _editStart = picked;
      } else {
        _newStart = picked;
      }
    });
  }

  Future<void> _pickLength() async {
    // `0` stands for open-ended, because null already means dismissed.
    final picked = await showAppSheet<int>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Planned length',
        contentPadding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        children: [
          for (final weeks in [12, 8, 16, 0])
            AppRow(
              title: _lengthLabel(weeks == 0 ? null : weeks),
              onTap: () => Navigator.of(sheet).pop(weeks),
              trailing: AppRadio(selected: (_weeks ?? 0) == weeks),
              ink: false,
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _weeks = picked == 0 ? null : picked);
  }

  Future<void> _save() async {
    final kind = _kind;
    if (kind == null || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(phaseRepositoryProvider);
    final navigator = Navigator.of(context);
    final current = _current;
    try {
      if (_editing && current != null) {
        final unchanged = dayKeyOf(_editStart) == current.startKey &&
            _weeks == current.phase.plannedWeeks;
        if (!unchanged) {
          await repo.editPhase(
            current.phase.id,
            from: _editStart,
            plannedWeeks: _weeks,
          );
        }
      } else {
        await repo.startPhase(kind, from: _newStart, plannedWeeks: _weeks);
      }
      navigator.pop();
    } catch (e, st) {
      reportFailure(e, st, what: 'That phase could not be saved.');
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Ends the current phase today, leaving Home with no phase.
  ///
  /// Its last day is yesterday, so from today no phase is current. A phase
  /// that began today has covered no finished day, and the schema refuses an
  /// end before a start, so it is removed instead.
  Future<void> _clear() async {
    final current = _current;
    if (current == null || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(phaseRepositoryProvider);
    final navigator = Navigator.of(context);
    try {
      if (current.startKey >= dayKeyOf(_today)) {
        await repo.discardPhase(current.phase.id);
      } else {
        await repo.clearPhase(current.phase.id, on: daysBefore(_today, 1));
      }
      navigator.pop();
    } catch (e, st) {
      reportFailure(e, st, what: 'That phase could not be cleared.');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving;
    return AppSheet(
      title: 'Phase',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grey, not red: the phase it ends stays in the history and keeps
          // tinting the cycles it covered.
          if (_current != null) ...[
            SecondaryButton(
              label: 'Clear phase',
              onPressed: busy ? null : _clear,
            ),
            const SizedBox(height: Space.md),
          ],
          PrimaryButton(
            label: 'Save',
            onPressed: _kind == null || busy ? null : _save,
          ),
        ],
      ),
      children: [
        SegmentedPill<PhaseKind?>(
          expand: true,
          segments: [
            for (final kind in PhaseKind.values)
              (value: kind, label: kind.label),
          ],
          value: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: Space.lg),
        _Field(
          label: 'Started',
          value: DateFormat('d MMM y').format(_start),
          onTap: _pickStart,
        ),
        const SizedBox(height: Space.md),
        _Field(
          label: 'Planned length',
          value: _lengthLabel(_weeks),
          onTap: _pickLength,
        ),
      ],
    );
  }

  static String _lengthLabel(int? weeks) =>
      weeks == null ? 'Open-ended' : '$weeks weeks';

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// One of the sheet's two answers: an inset panel, `label` over `valueSm`,
/// that opens its picker.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: InsetPanel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.t.bodySmall),
                  const SizedBox(height: Space.xxs),
                  Text(value, style: context.t.labelLarge),
                ],
              ),
            ),
            const LinkAction('Change'),
          ],
        ),
      ),
    );
  }
}
