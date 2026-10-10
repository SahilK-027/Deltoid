import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ids.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/enums.dart';
import '../../../domain/metrics.dart';
import '../../../domain/set_format.dart';
import '../../../domain/units.dart';
import '../../settings/bodyweight_screen.dart';
import '../log_providers.dart';

/// The bodyweight a bodyweight movement is being scored against today, and how
/// much of it the movement moves.
///
/// A pull-up's load is the person doing it, and the log is the one screen where
/// that number is otherwise invisible: the load column reads `Bodyweight` and
/// the figure behind it lives in Settings. The pill prints it under the
/// exercise header with the share the movement takes from it, marks it when it
/// is old or assumed, and opens the weigh-in from where the lift is being
/// logged.
///
/// Drawn only for a movement whose score reads bodyweight. A hold carries no
/// estimated 1RM and adds nothing to volume, so a bodyweight under a dead hang
/// would be a number nothing uses.
class BodyweightPill extends ConsumerWidget {
  const BodyweightPill({
    super.key,
    required this.loadMode,
    required this.measureMode,
    required this.bodyweightPct,
    required this.dayKey,
  });

  final LoadMode loadMode;
  final MeasureMode measureMode;

  /// `exercises.bodyweight_pct`: how much of the bodyweight the movement moves.
  final int bodyweightPct;

  /// The day the session is logged on, which is the day the lift is scored on.
  final int dayKey;

  static bool appliesTo(LoadMode load, MeasureMode measure) =>
      !measure.isHold &&
      (load == LoadMode.bodyweight || load == LoadMode.bodyweightPlus);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!appliesTo(loadMode, measureMode)) return const SizedBox.shrink();

    // Nothing until the series has loaded. An empty list and a list that has
    // not arrived are different states (RULES § 5), and reading the second as
    // the first would flash `60 kg assumed` at someone who weighed in today.
    final series = ref.watch(bodyweightSeriesProvider).valueOrNull;
    if (series == null) return const SizedBox.shrink();

    final c = context.c;
    final unit = ref.watch(weightUnitProvider).valueOrNull ?? WeightUnit.kg;
    final basis = bodyweightBasis(dayKey, series);
    final figure = bodyweightBasisLabel(basis, unit);
    final moved = bodyweightMovedLabel(basis.kg, bodyweightPct, unit);

    return FigurePill(
      figure: figure,
      detail: moved,
      // Green while the weigh-in is recent, and the warning yellow the sheet's
      // notice is drawn in when it is old or assumed.
      hue: basis.trust == BodyweightTrust.logged ? c.positive : c.warning,
      // The ring is filled to the share of the body the movement moves, so a
      // push-up's is two thirds drawn and a pull-up's is all but closed.
      fraction: bodyweightPct / 100,
      semanticLabel: 'Bodyweight $figure, $moved on this movement',
      onTap: () => _open(context, ref, basis, unit),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    BodyweightBasis basis,
    WeightUnit unit,
  ) async {
    // Captured before the first await: logging a weight re-reads the series,
    // which rebuilds the page this pill sits on (RULES § 4).
    final container = ProviderScope.containerOf(context);
    final loggedToday = basis.lastDayKey == dayKeyOf(DateTime.now());

    final log = await showAppSheet<bool>(
      context,
      builder: (sheet) => _BodyweightSheet(
        basis: basis,
        unit: unit,
        loadMode: loadMode,
        bodyweightPct: bodyweightPct,
        loggedToday: loggedToday,
      ),
    );
    if (log != true || !context.mounted) return;

    await logBodyweightPrompt(
      context,
      ref,
      date: loggedToday ? DateTime.now() : null,
      initial: loggedToday ? basis.kg : null,
    );
    // The series is a one-shot read, so whoever changes it says so.
    container.invalidate(bodyweightSeriesProvider);
  }
}

/// What the pill opens: the scale weight the lift is scored on, and the part
/// of it that counts as resistance on this movement.
///
/// The scale weight is shown as a figure in a panel rather than as a field. It
/// is read here and changed in the weigh-in sheet, which `Edit scale weight`
/// opens, so the panel does not take a tap it cannot answer.
class _BodyweightSheet extends StatelessWidget {
  const _BodyweightSheet({
    required this.basis,
    required this.unit,
    required this.loadMode,
    required this.bodyweightPct,
    required this.loggedToday,
  });

  final BodyweightBasis basis;
  final WeightUnit unit;
  final LoadMode loadMode;
  final int bodyweightPct;
  final bool loggedToday;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hue = basis.trust == BodyweightTrust.logged ? c.positive : c.warning;
    final moved = formatBodyweight(
      bodyweightMoved(basis.kg, bodyweightPct),
      unit,
    );
    final recorded = basis.lastDayKey != null;

    return AppSheet(
      title: 'Bodyweight contribution',
      // One action. The sheet is read and closed by its ✕, and the only thing
      // to do from it is change the weight.
      footer: PrimaryButton(
        label: recorded ? 'Edit scale weight' : 'Log scale weight',
        onPressed: () => Navigator.of(context).pop(true),
      ),
      children: [
        Text('Scale weight', style: context.t.titleSmall),
        const SizedBox(height: Space.sm),
        InsetPanel(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatBodyweight(basis.kg, unit),
                  style: context.t.labelLarge,
                ),
              ),
              Text(
                unit.label,
                style: context.t.labelSmall?.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          bodyweightRecordedLine(
            basis,
            unit,
            lastRecorded: recorded
                ? DateFormat('d MMM yyyy').format(
                    dateFromDayKey(basis.lastDayKey!),
                  )
                : null,
          ),
          style: context.t.bodySmall?.copyWith(
            color: basis.trust == BodyweightTrust.logged
                ? c.textSecondary
                : c.warning,
          ),
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          fill: Colors.transparent,
          outline: BorderSide(color: c.border),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.monitor_weight_outlined,
                    size: 22,
                    color: c.textPrimary,
                  ),
                  const Spacer(),
                  Pill('$bodyweightPct%', color: hue),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                '+$moved ${unit.label} of resistance',
                style: context.t.titleMedium,
              ),
              const SizedBox(height: Space.xxs),
              Text(
                bodyweightLoadBlurb(loadMode, bodyweightPct),
                style: context.t.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
