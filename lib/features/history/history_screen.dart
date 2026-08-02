import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/units.dart';
import 'exercise_history_screen.dart';
import 'history_providers.dart';
import 'workout_detail_screen.dart';

/// Which reading of "history" is on screen.
enum HistoryView { sessions, exercises }

final historyViewProvider =
    StateProvider<HistoryView>((ref) => HistoryView.sessions);

/// Two ways in, because "what did I do" has two meanings: which day
/// (Sessions) and which lift (Exercises).
///
/// A third once existed — the old Notion table, exercises down the side and one
/// column per date. It was dropped: the feed answers "which day" better and the
/// per-exercise history answers "how has this moved" better, and a spreadsheet
/// re-created inside the app that replaced the spreadsheet is one screen of
/// horizontally scrolled cells nobody opened.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(historyViewProvider);
    final overview = ref.watch(historyOverviewProvider).valueOrNull;

    return Scaffold(
      body: Column(
        children: [
          HeaderBand(
            child: PageHeader(
              title: 'History',
              // The band is a full-width surface, so it is composed across its
              // width: title left, the total right, the control spanning both
              // underneath. Stacked flush left it left the right half of the
              // band empty, which is what made it read as unfinished rather
              // than spare.
              eyebrow: _span(overview),
              // Without the eyebrow the title is the first line under the
              // status bar, and 12 leaves it sitting on the notch (THEME §4).
              topGap: _span(overview) == null ? Space.xxl : Space.md,
              belowGap: Space.lg,
              actions: [_TotalStat(overview: overview)],
              below: SegmentedPill<HistoryView>(
                value: view,
                expand: true,
                onChanged: (v) =>
                    ref.read(historyViewProvider.notifier).state = v,
                segments: const [
                  (value: HistoryView.sessions, label: 'Sessions'),
                  (value: HistoryView.exercises, label: 'Exercises'),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (view) {
              HistoryView.sessions => const _WorkoutFeed(),
              HistoryView.exercises => const _ExerciseIndex(),
            },
          ),
        ],
      ),
    );
  }

  /// `SINCE MARCH 2024` — but only once there is a span to state. A history one
  /// day old printed "since July 2026", which is the same dishonesty as the
  /// sessions-per-week rate that divided by three weeks that hadn't happened.
  static String? _span(HistoryOverview? overview) {
    if (overview == null || !overview.spansMonths) return null;
    final first = dateFromDayKey(overview.firstDayKey!);
    return 'Since ${DateFormat('MMMM yyyy').format(first)}';
  }
}

/// How much is in here, against the right edge of the band.
///
/// One number, not a sentence: sessions, because it is the thing the page is a
/// list of, and because it stays two or three digits after years of training —
/// a set total runs to five and turns the header into a wall.
///
/// Deliberately not "how long since you trained": that is Today's question, and
/// Today answers it in the largest type in the app.
class _TotalStat extends StatelessWidget {
  const _TotalStat({required this.overview});

  final HistoryOverview? overview;

  @override
  Widget build(BuildContext context) {
    final total = overview?.sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Nothing logged prints a dash, and so does a count that has not
          // arrived yet — never a 0 that the next frame replaces.
          total == null || total == 0
              ? '——'
              : NumberFormat.decimalPattern().format(total),
          style: context.t.displaySmall,
        ),
        Text(
          total == 1 ? 'session' : 'sessions',
          style: context.t.labelSmall,
        ),
      ],
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
            title: 'Your log starts here',
            message: 'Finish a session and it shows up here — tap any day to '
                'see exactly what you did.',
          );
        }

        final rows = _withMonthHeaders(page.items);

        // No cards and no gutter: the rows run edge to edge under a spoken
        // date heading, which is what lets a year of training be scanned by
        // the tiles and the day names alone (§8).
        return ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.only(bottom: Space.huge),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == rows.length) return _FeedFooter(page: page);
            final row = rows[i];
            return switch (row) {
              // The count sits on the right of its month, where scanning back
              // through a year answers "how much did I train that month"
              // without reading the rows under it.
              _MonthHeader(:final label, :final count) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    Space.gutter,
                    i == 0 ? Space.lg : Space.section,
                    Space.gutter,
                    Space.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(label, style: context.t.headlineSmall),
                      ),
                      Text('$count', style: context.t.bodySmall),
                    ],
                  ),
                ),
              // The rule separates one day from the next, so it belongs
              // between rows — never under the last one in a month, where it
              // would draw a line under the heading that follows.
              _SummaryRow(:final summary) => Column(
                  children: [
                    if (rows[i - 1] is _SummaryRow)
                      Divider(height: 1, color: context.c.border),
                    _WorkoutRow(summary: summary),
                  ],
                ),
            };
          },
        );
      },
    );
  }

  /// Groups by calendar month, which is how anyone actually looks backwards.
  ///
  /// The count on a header is of the rows *loaded* under it. That is honest for
  /// every month but the oldest one on screen, which paging can still grow —
  /// and that one is only ever the last header in the list, with more coming
  /// under it as you scroll.
  static List<_FeedRow> _withMonthHeaders(List<WorkoutSummary> items) {
    final rows = <_FeedRow>[];
    final counts = <String, int>{};
    var currentMonth = '';
    for (final s in items) {
      final date = dateFromDayKey(s.workout.dayKey);
      final label = DateFormat('MMMM yyyy').format(date);
      counts[label] = (counts[label] ?? 0) + 1;
      if (label != currentMonth) {
        rows.add(_MonthHeader(label));
        currentMonth = label;
      }
      rows.add(_SummaryRow(s));
    }
    for (final row in rows) {
      if (row is _MonthHeader) row.count = counts[row.label] ?? 0;
    }
    return rows;
  }
}

sealed class _FeedRow {
  const _FeedRow();
}

class _MonthHeader extends _FeedRow {
  _MonthHeader(this.label);
  final String label;

  /// Filled once the whole page has been walked — a month's total is not known
  /// at the moment its header is emitted.
  int count = 0;
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
    // "That is everything" only means something to someone who has been
    // scrolling. On a list that never filled a page it is a caption under a
    // single row, floating in the empty half of the screen.
    if (!page.hasMore && page.items.length < historyPageSize) {
      return const SizedBox(height: Space.xl);
    }
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
        // No count here: the masthead already carries the total, and a second
        // one at the bottom of the list is the same fact twice.
        child: Text('That is everything', style: context.t.bodySmall),
      ),
    );
  }
}

/// One trained day. Identity tile, what it was, and what was in it.
///
/// The exercise line replaces the exercise *count*: they are the same fact, and
/// the names are the one that answers "which day was that" (rule 6).
class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.summary});

  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = dateFromDayKey(summary.workout.dayKey);
    // Every session is the heatmap's blue; a deload is orange. The tile carried
    // the regime's identity hue, which is what made a deload unreadable in this
    // column — orange against six other colours, and invisible against the
    // orange regime. Down a feed the question is which of these days was light,
    // and that is now the only thing the colour answers.
    final mark = summary.workout.isDeload ? c.deload : c.heatOn;

    // No programme name: the tile already carries it as colour, and spelled
    // out it was long enough to push the line into an ellipsis on a phone.
    // No `0 min` either — a duration under a minute is a clock that never ran,
    // and printing it as a zero is the bug face rule 4 is about.
    final minutes = summary.durationMinutes;
    final meta = <String>[
      DateFormat('EEE d').format(date),
      '${summary.setCount} set${summary.setCount == 1 ? '' : 's'}',
      if (minutes != null && minutes > 0) '$minutes min',
      if (summary.skippedCount > 0) '${summary.skippedCount} skipped',
    ];

    return Pressable(
      scale: 0.99,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutDetailScreen(workoutId: summary.workout.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              summary.workout.isDeload
                  ? Icons.trending_down_rounded
                  : Icons.bolt_rounded,
              color: mark,
              size: 44,
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
                          style: context.t.titleMedium,
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
                  const SizedBox(height: Space.xxs),
                  Text(
                    meta.join(' · '),
                    style: context.t.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary.exerciseNames.isNotEmpty) ...[
                    const SizedBox(height: Space.xxs),
                    Text(
                      summary.exerciseNames.join(' · '),
                      style: context.t.bodySmall
                          ?.copyWith(color: c.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: c.textTertiary),
            ),
          ],
        ),
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
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.sm, Space.gutter, Space.md),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search exercises',
              prefixIcon: Icon(Icons.search, size: 20, color: c.textTertiary),
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
            padding: const EdgeInsets.only(bottom: Space.huge),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
            itemBuilder: (context, i) {
              final e = filtered[i];
              return AppRow(
                title: e.exercise.name,
                subtitle: '${e.timesPerformed} session'
                    '${e.timesPerformed == 1 ? '' : 's'} · last '
                    '${DateFormat('d MMM yyyy').format(dateFromDayKey(e.lastDayKey))}',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ExerciseHistoryScreen(exerciseId: e.exercise.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Trailing zeros are noise on a gym screen: 22.5 stays 22.5, 60.0 becomes 60.
///
/// Takes a stored kilogram value and renders it in [unit]. Capped at two
/// decimals because this also formats *computed* numbers — an estimated 1RM is
/// an arbitrary double, and `55.733333333333334 kg` is not a weight anyone has
/// ever lifted.
///
/// [unit] is required on purpose. It was optional with a kilogram default for
/// exactly one commit, and in that commit two call sites forgot it and rendered
/// pounds as kilograms — next to a tooltip that had it right. An optional unit
/// makes "wrong" the thing that compiles.
String formatWeight(double kg, WeightUnit unit) {
  final v = unit.display(kg);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final rounded = (v * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
