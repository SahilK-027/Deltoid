import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ids.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/database.dart';
import '../../data/repositories/training_repository.dart';
import '../log/widgets/exercise_sheets.dart';
import 'exercise_history_screen.dart';
import 'history_providers.dart';
import 'workout_detail_screen.dart';
import '../../domain/session_name.dart';
import '../account/backup_mark.dart';

/// Which reading of "history" is on screen.
enum HistoryView { sessions, exercises }

final historyViewProvider =
    StateProvider<HistoryView>((ref) => HistoryView.sessions);

/// Two ways in, because "what did I do" has two meanings: which day
/// (Sessions) and which lift (Exercises).
///
/// Not a third: a Notion-style table, exercises down the side and one column
/// per date, is answered better by the feed for "which day" and by the
/// per-exercise history for "how has this moved". A spreadsheet re-created
/// inside the app that replaced the spreadsheet is one screen of horizontally
/// scrolled cells nobody opens.
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
              // underneath. Stacked flush left it leaves the right half of the
              // band empty, which reads as unfinished rather than spare.
              eyebrow: _eyebrow(overview),
              // Without the eyebrow the title is the first line under the
              // status bar, and 12 leaves it sitting on the notch (THEME → Space).
              topGap: _eyebrow(overview) == null ? Space.xxl : Space.md,
              belowGap: Space.lg,
              actions: [const BackupMark(), _TotalStat(overview: overview)],
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

  /// `SINCE MARCH 2024`, the line above the title — but only once there is a
  /// span to state. A history one day old printing "since July 2026" is the
  /// same dishonesty as a sessions-per-week rate divided by three weeks that
  /// have not happened.
  ///
  /// An empty log says so rather than dropping the line: without it the title
  /// is the first thing under the status bar, and the one screen state where
  /// you most need telling what you are looking at is the one that says the
  /// least. Null while the count is still in flight — a line that appears
  /// a frame later is the staged reveal this app avoids.
  static String? _eyebrow(HistoryOverview? overview) {
    if (overview == null) return null;
    if (overview.firstDayKey == null) return 'Nothing logged';
    return _span(overview);
  }

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
    // An empty log says so in the eyebrow, and a `—— sessions` beside it is the
    // same fact twice on one screen (rule 6). On the light theme it also reads
    // as a black rule rather than as a pair of dashes: two em dashes at 22sp
    // bold in `#111111` is a line, not a zero state.
    //
    // The dash still stands for a count that has not *arrived* — that one is a
    // gap the next frame fills, not an absence the header already named.
    if (overview != null && total == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // A count that has not arrived prints a dash — never a 0 that the
          // next frame replaces.
          total == null
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
    final filter = ref.watch(historyFilterProvider);

    // The chip row is part of the list, above it: it belongs to the feed, not
    // to the masthead, which holds the screen's name and nothing else (THEME → Components).
    return Column(
      children: [
        // The bar arrives once there is more than one day in history, and
        // leaves when a filter is cleared on a short log. Either between two
        // frames jolts the list under it.
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.emphasized,
          alignment: Alignment.topCenter,
          child: const _FeedFilterBar(),
        ),
        Expanded(
          // A write anywhere in history invalidates this provider, and `when`
          // would drop the whole feed for a spinner while the page reloads —
          // the list you are reading vanishing because you ticked a set two
          // screens away. The rows stay until the new ones arrive.
          child: feed.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xxxl),
                child: Text('Your history could not be loaded.',
                    textAlign: TextAlign.center, style: context.t.bodyMedium),
              ),
            ),
            data: (page) => _list(context, page, filter),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, PagedHistory<WorkoutSummary> page,
      HistoryFilter filter) {
    if (page.isEmpty) {
      // An empty *filter* is not an empty history, and offering "finish a
      // session and it shows up here" to someone with 200 logged days reads as
      // the app having lost them.
      return filter.isEmpty
          ? const EmptyState(
              icon: Icons.history_toggle_off,
              title: 'Your log starts here',
              message: 'Finish a session and it appears here. Tap any day to '
                  'see exactly what you did.',
            )
          : EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing matches',
              message: 'No logged day fits what you have picked.',
              action: SecondaryButton(
                label: 'Clear filter',
                onPressed: () => ref
                    .read(historyFilterProvider.notifier)
                    .state = const HistoryFilter(),
              ),
            );
    }

    final rows = _withMonthHeaders(page.items);

    // No cards and no gutter: the rows run edge to edge under a spoken
    // date heading, which is what lets a year of training be scanned by
    // the tiles and the day names alone (THEME → Components).
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
              // A month is a section like any other, so it is a
              // `SectionHeader` — same 20sp, same 12 underneath, same gutter as
              // `Consistency` on Workouts or `Data` in Settings. Hand-rolled,
              // it drifts a few points off all of them.
              _MonthHeader(:final label, :final count) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    Space.gutter,
                    i == 0 ? Space.lg : Space.section,
                    Space.gutter,
                    0,
                  ),
                  child: SectionHeader(
                    label,
                    trailing: Text('$count', style: context.t.bodySmall),
                  ),
                ),
              // The rule separates one day from the next, so it belongs
              // between rows — never under the last one in a month, where it
              // would draw a line under the heading that follows.
              _SummaryRow(:final summary) => Column(
                  children: [
                    if (rows[i - 1] is _SummaryRow)
                      const Divider(),
                    _WorkoutRow(summary: summary),
                  ],
                ),
            };
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

/// The feed's filter: which training day, and whether to show only the light
/// weeks.
///
/// Chips rather than a bar of dropdowns, and the same chips the catalog filters
/// with (THEME → Components): unselected is `surfaceHigh`, a live filter is the `accent` fill,
/// and a caret means it opens a picker. There is no date range — the list is
/// ordered by date and scrolling is the range control; two date fields would
/// ask you to type the answer the list is already showing.
class _FeedFilterBar extends ConsumerWidget {
  const _FeedFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final sessions = ref.watch(loggedSessionsProvider).valueOrNull ?? const [];

    // Nothing to filter with until there is more than one day in history. A
    // control that can only ever return the same list is furniture.
    if (sessions.length < 2 && !filter.deloadOnly && filter.sessionId == null) {
      return const SizedBox(height: Space.sm);
    }

    final picked = () {
      for (final s in sessions) {
        if (s.sessionId == filter.sessionId) return s;
      }
      return null;
    }();

    // 12 + a 40pt chip + 12. At 52, with no bottom padding at all, the chips
    // sit flush on the strip's edge and the first row of the feed runs straight
    // into them — the row below has to clear a control, not touch it.
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.md),
        children: [
          AppChip(
            // The chip states the filter when there is one, and the question
            // when there isn't — a chip reading `Session` beside a list that is
            // already filtered says nothing about what you are looking at.
            label: picked?.name ?? 'All days',
            icon: Icons.calendar_view_week_rounded,
            selected: filter.sessionId != null,
            caret: true,
            onTap: () => _pickSession(context, ref, sessions, filter),
          ),
          const SizedBox(width: Space.sm),
          AppChip(
            label: 'Deloads',
            icon: Icons.trending_down_rounded,
            selected: filter.deloadOnly,
            onTap: () => ref.read(historyFilterProvider.notifier).state =
                filter.copyWith(deloadOnly: !filter.deloadOnly),
          ),
          if (!filter.isEmpty) ...[
            const SizedBox(width: Space.sm),
            AppChip(
              label: 'Clear',
              icon: Icons.close_rounded,
              onTap: () => ref.read(historyFilterProvider.notifier).state =
                  const HistoryFilter(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickSession(
    BuildContext context,
    WidgetRef ref,
    List<LoggedSession> sessions,
    HistoryFilter filter,
  ) async {
    final chosen = await showAppSheet<String>(
      context,
      builder: (sheet) => AppSheet(
        title: 'Training day',
        subtitle: 'Days you have actually logged',
        contentPadding: const EdgeInsets.only(bottom: Space.md),
        children: [
          AppRow(
            title: 'All days',
            onTap: () => Navigator.of(sheet).pop(''),
            trailing: AppRadio(selected: filter.sessionId == null),
          ),
          for (final s in sessions)
            AppRow(
              title: s.name,
              // Two regimes can both own a `Push 1`, and the count is the
              // reason to pick one row over another.
              subtitle: '${s.regimeName} · ${s.workouts} logged',
              onTap: () => Navigator.of(sheet).pop(s.sessionId),
              trailing: AppRadio(selected: filter.sessionId == s.sessionId),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    ref.read(historyFilterProvider.notifier).state = chosen.isEmpty
        ? filter.copyWith(clearSession: true)
        : filter.copyWith(sessionId: chosen);
  }
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.page});

  final PagedHistory<WorkoutSummary> page;

  @override
  Widget build(BuildContext context) {
    // "End of history" only means something to someone who has been
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
        child: Text('End of history', style: context.t.bodySmall),
      ),
    );
  }
}

/// One trained day. The day as a calendar page, what it was, and what was in
/// it.
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
    // Every session is the heatmap's blue; a deload is orange. The regime's
    // identity hue would make a deload unreadable in this column — orange
    // against six other colours, and invisible against the orange regime. Down
    // a feed the question is which of these days was light, and that is the
    // only thing the colour answers.
    final mark = summary.workout.isDeload ? c.deload : c.progress;

    // No programme name: the tile already carries it as colour, and spelled
    // out it is long enough to push the line into an ellipsis on a phone.
    // No `0 min` either — a duration under a minute is a clock that never ran,
    // and printing it as a zero is the bug face rule 4 is about.
    final minutes = summary.durationMinutes;
    // The date is the tile's, so the line under the name does not say it again
    // (THEME rule 6).
    final meta = <String>[
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
            horizontal: Space.gutter, vertical: Space.lg),
        // Centred, because the tile is a fixed page and the text beside it is
        // two lines or three: aligned to the top, the tile floated over the
        // shorter rows.
        child: Row(
          children: [
            DateTile(
              day: '${date.day}',
              weekday: DateFormat('EEE').format(date),
              hue: mark,
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          summary.sessionName ?? customSessionName,
                          style: context.t.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // The icon alone: the tile is already orange, and the
                      // word, the same down every light row, is a tap away.
                      if (summary.workout.isDeload) ...[
                        const SizedBox(width: Space.sm),
                        RevealPill(
                          'Deload',
                          icon: Icons.trending_down_rounded,
                          color: c.deload,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    meta.join(' · '),
                    style: context.t.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary.exerciseNames.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
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
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textTertiary),
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
    final trained = ref.watch(exercisesWithHistoryProvider).valueOrNull;
    final q = _query.trim().toLowerCase();

    if (trained == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // **The catalog is only read while you are searching.** At rest this is an
    // index of what you have trained, ordered by when — padding it with every
    // movement you have ever defined would bury the rows you came for under a
    // list you already have two other ways into. But a search that answers
    // "no such exercise" about an exercise you created this morning is telling
    // you it is gone, and the answer that is actually true is "you have not
    // trained it yet".
    final catalog = q.isEmpty
        ? const <Exercise>[]
        : (ref.watch(exerciseCatalogProvider).valueOrNull ?? const []);

    final matches = q.isEmpty
        ? trained
        : [
            for (final e in trained)
              if (e.exercise.name.toLowerCase().contains(q)) e,
          ];
    final untrained = q.isEmpty
        ? const <Exercise>[]
        : () {
            final logged = {for (final e in matches) e.exercise.id};
            return [
              for (final e in catalog)
                if (!logged.contains(e.id) && e.name.toLowerCase().contains(q))
                  e,
            ];
          }();

    return Column(
      children: [
        // Above the empty state as well as above the list: an empty history is
        // exactly when you want to look an exercise up and find out it has one
        // waiting.
        Padding(
          padding: searchFieldPadding,
          child: SearchField(
            hint: 'Search exercises',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: matches.isEmpty && untrained.isEmpty
              ? EmptyState(
                  icon: Icons.fitness_center,
                  title: q.isEmpty ? 'No exercise history' : 'No matches',
                  message: q.isEmpty
                      ? 'Once a session is finished, every movement in it gets '
                          'its own history here.'
                      : 'No exercise matches that search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: Space.huge),
                  // The heading is a row of its own, and only when both groups
                  // are on screen — a lone "Not yet logged" over the one thing
                  // you searched for labels the obvious.
                  itemCount: matches.length +
                      untrained.length +
                      (matches.isNotEmpty && untrained.isNotEmpty ? 1 : 0),
                  separatorBuilder: (_, _) =>
                      const Divider(),
                  itemBuilder: (context, i) {
                    if (i < matches.length) {
                      final e = matches[i];
                      return _exerciseRow(
                        id: e.exercise.id,
                        name: e.exercise.name,
                        subtitle: '${e.timesPerformed} session'
                            '${e.timesPerformed == 1 ? '' : 's'} · last '
                            '${DateFormat('d MMM yyyy').format(dateFromDayKey(e.lastDayKey))}',
                      );
                    }
                    var j = i - matches.length;
                    if (matches.isNotEmpty) {
                      if (j == 0) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(
                              Space.gutter, Space.xl, Space.gutter, Space.sm),
                          child: SectionHeader('Not yet logged'),
                        );
                      }
                      j -= 1;
                    }
                    final e = untrained[j];
                    return _exerciseRow(
                      id: e.id,
                      name: e.name,
                      subtitle: 'Never logged',
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _exerciseRow({
    required String id,
    required String name,
    required String subtitle,
  }) {
    return AppRow(
      title: name,
      subtitle: subtitle,
      chevron: true,
      // An untrained exercise opens the same screen as a trained one, which is
      // the screen saying it has never been logged.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExerciseHistoryScreen(exerciseId: id),
        ),
      ),
    );
  }
}
