import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/enums.dart';
import 'exercise_history_screen.dart';
import 'history_providers.dart';
import 'workout_detail_screen.dart';

/// Which of the three readings of "history" is on screen.
enum HistoryView { sessions, exercises, table }

final historyViewProvider = StateProvider<HistoryView>((ref) => HistoryView.sessions);
final selectedHistorySessionProvider = StateProvider<String?>((ref) => null);

/// Three ways in, because "what did I do" has three different meanings:
/// which day (Sessions), which lift (Exercises), and how one session's numbers
/// have moved week over week (Table — the old Notion layout).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(historyViewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.xs, Space.lg, Space.md),
            child: _ViewSwitcher(
              value: view,
              onChanged: (v) => ref.read(historyViewProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: switch (view) {
              HistoryView.sessions => const _WorkoutFeed(),
              HistoryView.exercises => const _ExerciseIndex(),
              HistoryView.table => const _SessionTable(),
            },
          ),
        ],
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.value, required this.onChanged});

  final HistoryView value;
  final ValueChanged<HistoryView> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          for (final v in HistoryView.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  decoration: BoxDecoration(
                    color: v == value ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    switch (v) {
                      HistoryView.sessions => 'Sessions',
                      HistoryView.exercises => 'Exercises',
                      HistoryView.table => 'Table',
                    },
                    textAlign: TextAlign.center,
                    style: context.t.titleSmall?.copyWith(
                      color: v == value ? c.onAccent : c.textSecondary,
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

// ── Sessions ────────────────────────────────────────────────────────────────

/// Every session ever finished, newest first, paged as you scroll.
///
/// Nothing is held in memory beyond what has been scrolled to, so this stays
/// usable with years of training in the database.
class _WorkoutFeed extends ConsumerStatefulWidget {
  const _WorkoutFeed();

  @override
  ConsumerState<_WorkoutFeed> createState() => _WorkoutFeedState();
}

class _WorkoutFeedState extends ConsumerState<_WorkoutFeed> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Fetch the next page while there is still a screenful left to scroll, so
  /// the list never visibly stops.
  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter > 600) return;
    ref.read(workoutFeedProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(workoutFeedProvider);

    return feed.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxxl),
          child: Text('Could not load history.\n\n$e',
              textAlign: TextAlign.center, style: context.t.bodyMedium),
        ),
      ),
      data: (page) {
        if (page.isEmpty) {
          return const EmptyState(
            icon: Icons.history_toggle_off,
            title: 'Nothing logged yet',
            message: 'Finish a session and it shows up here — tap any day to '
                'see exactly what you did.',
          );
        }

        final rows = _withMonthHeaders(page.items);

        return ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.fromLTRB(
              Space.lg, 0, Space.lg, Space.huge),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) return _FeedFooter(page: page);
            final row = rows[i];
            return switch (row) {
              _MonthHeader(:final label) => Padding(
                  padding: const EdgeInsets.only(
                      top: Space.lg, bottom: Space.sm, left: Space.xs),
                  child: Text(label.toUpperCase(), style: context.t.labelSmall),
                ),
              _SummaryRow(:final summary) => Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _WorkoutCard(summary: summary),
                ),
            };
          },
        );
      },
    );
  }

  /// Groups by calendar month, which is how anyone actually looks backwards.
  static List<_FeedRow> _withMonthHeaders(List<WorkoutSummary> items) {
    final rows = <_FeedRow>[];
    var currentMonth = '';
    for (final s in items) {
      final date = dateFromDayKey(s.workout.dayKey);
      final label = DateFormat('MMMM yyyy').format(date);
      if (label != currentMonth) {
        rows.add(_MonthHeader(label));
        currentMonth = label;
      }
      rows.add(_SummaryRow(s));
    }
    return rows;
  }
}

sealed class _FeedRow {
  const _FeedRow();
}

class _MonthHeader extends _FeedRow {
  const _MonthHeader(this.label);
  final String label;
}

class _SummaryRow extends _FeedRow {
  const _SummaryRow(this.summary);
  final WorkoutSummary summary;
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.page});

  final PagedHistory<WorkoutSummary> page;

  @override
  Widget build(BuildContext context) {
    if (page.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xl),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xl),
      child: Center(
        child: Text(
          '${page.items.length} session${page.items.length == 1 ? '' : 's'} '
          '· that is everything',
          style: context.t.labelSmall,
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.summary});

  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = dateFromDayKey(summary.workout.dayKey);
    final accent = summary.workout.isDeload ? c.deload : c.accent;

    final facts = <String>[
      '${summary.exerciseCount} exercise'
          '${summary.exerciseCount == 1 ? '' : 's'}',
      '${summary.setCount} set${summary.setCount == 1 ? '' : 's'}',
      if (summary.durationMinutes != null) '${summary.durationMinutes} min',
      if (summary.skippedCount > 0) '${summary.skippedCount} skipped',
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutDetailScreen(workoutId: summary.workout.id),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('d').format(date),
                  style: context.t.titleLarge?.copyWith(color: accent),
                ),
                Text(DateFormat('EEE').format(date), style: context.t.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        summary.sessionName ?? 'Ad-hoc session',
                        style: context.t.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (summary.workout.isDeload) ...[
                      const SizedBox(width: Space.sm),
                      Pill('Deload', color: c.deload),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(facts.join('  ·  '), style: context.t.labelSmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
        ],
      ),
    );
  }
}

// ── Exercises ───────────────────────────────────────────────────────────────

/// Every exercise that has been trained, as a way into its own history.
class _ExerciseIndex extends ConsumerStatefulWidget {
  const _ExerciseIndex();

  @override
  ConsumerState<_ExerciseIndex> createState() => _ExerciseIndexState();
}

class _ExerciseIndexState extends ConsumerState<_ExerciseIndex> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exercisesWithHistoryProvider).valueOrNull;
    final c = context.c;
    final q = _query.trim().toLowerCase();
    final filtered = all == null
        ? const <ExerciseHistorySummary>[]
        : q.isEmpty
            ? all
            : all
                .where((e) => e.exercise.name.toLowerCase().contains(q))
                .toList();

    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.fitness_center,
        title: 'No exercise history',
        message: 'Once a session is finished, every movement in it gets its '
            'own history here.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search exercises',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: c.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding:
                const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              final e = filtered[i];
              return AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg, vertical: Space.md),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ExerciseHistoryScreen(exerciseId: e.exercise.id),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.exercise.name, style: context.t.titleSmall),
                          const SizedBox(height: Space.xs),
                          Text(
                            '${e.timesPerformed} session'
                            '${e.timesPerformed == 1 ? '' : 's'}  ·  last '
                            '${DateFormat('d MMM yyyy').format(dateFromDayKey(e.lastDayKey))}',
                            style: context.t.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: c.textTertiary),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Table ───────────────────────────────────────────────────────────────────

/// The Notion table, made infinite.
///
/// Same shape as the spreadsheet this app replaced — exercises down the side,
/// one column per date — but scrolling right walks backwards through history,
/// pulling in more columns as it goes.
class _SessionTable extends ConsumerWidget {
  const _SessionTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every session that has actually been trained, not just the active
    // regime's: this is a history view, and switching programmes must not hide
    // the history of the one before it.
    final sessions = ref.watch(sessionsWithHistoryProvider).valueOrNull ?? const [];

    // A stored id survives a regime switch and a session delete. Fall back
    // instead of showing an empty table for a session that isn't on the tabs.
    final stored = ref.watch(selectedHistorySessionProvider);
    final selected = sessions.any((s) => s.id == stored)
        ? stored
        : (sessions.isEmpty ? null : sessions.first.id);

    if (sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.view_column_outlined,
        title: 'Nothing logged yet',
        message: 'Finish a session and it gets a column here, newest on the '
            'left — the old spreadsheet, one session at a time.',
      );
    }

    return Column(
      children: [
        _SessionTabs(
          sessions: sessions,
          selected: selected,
          onSelect: (id) =>
              ref.read(selectedHistorySessionProvider.notifier).state = id,
        ),
        if (selected != null)
          Expanded(child: _HistoryTable(sessionId: selected)),
      ],
    );
  }
}

class _SessionTabs extends StatelessWidget {
  const _SessionTabs({
    required this.sessions,
    required this.selected,
    required this.onSelect,
  });

  final List<Session> sessions;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final s = sessions[i];
          final isSelected = s.id == selected;
          return Center(
            child: GestureDetector(
              onTap: () => onSelect(s.id),
              child: AnimatedContainer(
                duration: Motion.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(
                    color: isSelected ? c.accent : c.border,
                  ),
                ),
                child: Text(
                  s.name,
                  style: context.t.titleSmall?.copyWith(
                    color: isSelected ? c.onAccent : c.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

const _rowHeight = 62.0;
const _nameColumnWidth = 132.0;
const _dataColumnWidth = 104.0;

class _HistoryTable extends ConsumerStatefulWidget {
  const _HistoryTable({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_HistoryTable> createState() => _HistoryTableState();
}

class _HistoryTableState extends ConsumerState<_HistoryTable> {
  final _dates = ScrollController();

  @override
  void initState() {
    super.initState();
    _dates.addListener(_onScroll);
  }

  @override
  void dispose() {
    _dates.removeListener(_onScroll);
    _dates.dispose();
    super.dispose();
  }

  /// Scrolling far enough right pulls in older columns. The table has no
  /// vertical axis to spare for a "load more" button.
  void _onScroll() {
    if (!_dates.hasClients || _dates.position.extentAfter > 400) return;
    final limit = ref.read(sessionTableLimitProvider(widget.sessionId));
    final loaded =
        ref.read(sessionHistoryProvider(widget.sessionId)).valueOrNull;
    if (loaded == null || loaded.workouts.length < limit) return;
    ref.read(sessionTableLimitProvider(widget.sessionId).notifier).state =
        limit + 12;
  }

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(sessionHistoryProvider(widget.sessionId)).valueOrNull;
    final c = context.c;

    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history_toggle_off,
        title: 'Nothing logged yet',
        message: 'Finish this session once and it will show up here, '
            'newest on the left.',
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, 0, Space.huge),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Frozen exercise column — the row labels must stay put while the
            // dates scroll, or the table is unreadable on a phone.
            SizedBox(
              width: _nameColumnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 44),
                  for (final id in history.exerciseOrder)
                    SizedBox(
                      height: _rowHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          history.exercises[id]?.name ?? '',
                          style: context.t.bodySmall
                              ?.copyWith(color: c.textPrimary),
                          maxLines: 3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _dates,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final workout in history.workouts)
                      _DateColumn(workout: workout, history: history),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateColumn extends StatelessWidget {
  const _DateColumn({required this.workout, required this.history});

  final Workout workout;
  final SessionHistory history;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = dateFromDayKey(workout.dayKey);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutDetailScreen(workoutId: workout.id),
        ),
      ),
      child: Container(
        width: _dataColumnWidth,
        margin: const EdgeInsets.only(right: Space.sm),
        decoration: BoxDecoration(
          color: workout.isDeload ? c.deloadMuted.withValues(alpha: 0.35) : null,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('d MMM').format(date),
                    style: context.t.titleSmall?.copyWith(
                      color: workout.isDeload ? c.deload : c.textPrimary,
                    ),
                  ),
                  Text(
                    workout.isDeload
                        ? 'Deload'
                        : DateFormat('yyyy').format(date),
                    style: context.t.labelSmall?.copyWith(
                      color: workout.isDeload ? c.deload : c.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            for (final exerciseId in history.exerciseOrder)
              SizedBox(
                height: _rowHeight,
                child: _Cell(
                  cell: history.cells[workout.id]?[exerciseId],
                  exercise: history.exercises[exerciseId],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.exercise});

  final HistoryCell? cell;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    if (cell == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('·', style: context.t.labelMedium?.copyWith(color: c.textTertiary)),
      );
    }
    if (cell!.skipReason != SkipReason.none) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Pill(cell!.skipReason.label, color: c.negative),
      );
    }

    final done = cell!.sets.where((s) => s.isDone).toList();
    if (done.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('—', style: context.t.labelMedium),
      );
    }

    // Weight first and large, reps beneath — the same reading order as the
    // Notion table, where the weight column carried the progression.
    final weights = done
        .map((s) => s.weight ?? s.addedWeight)
        .whereType<double>()
        .toSet();
    final weightLabel = weights.isEmpty
        ? 'BW'
        : weights.length == 1
            ? formatWeight(weights.first)
            : weights.map(formatWeight).join('/');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          exercise?.loadMode == LoadMode.bodyweightPlus && weights.isNotEmpty
              ? 'BW+$weightLabel'
              : weightLabel,
          style: context.t.labelLarge,
        ),
        const SizedBox(height: 2),
        Text(
          done.map((s) => '${s.reps ?? 0}').join(' · '),
          style: context.t.labelMedium?.copyWith(color: c.textTertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Trailing zeros are noise on a gym screen: 22.5 stays 22.5, 60.0 becomes 60.
///
/// Capped at two decimals because this also formats *computed* numbers — an
/// estimated 1RM is an arbitrary double, and `55.733333333333334 kg` is not a
/// weight anyone has ever lifted.
String formatWeight(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final rounded = (v * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
