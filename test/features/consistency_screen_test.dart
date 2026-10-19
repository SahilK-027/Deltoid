import 'package:deltoid/core/ids.dart';
import 'package:deltoid/core/theme/theme.dart';
import 'package:deltoid/core/widgets/primitives.dart';
import 'package:deltoid/domain/consistency.dart';
import 'package:deltoid/features/home/heatmap_data.dart';
import 'package:deltoid/features/home/history_heatmap_screen.dart';
import 'package:deltoid/features/home/home_providers.dart';
import 'package:deltoid/features/home/widgets/session_bars.dart';
import 'package:deltoid/features/home/widgets/year_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Consistency screen: a year chosen from the year sheet, sessions per week
/// as bars read by a tooltip, and the year's days as month calendars.
void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  Future<void> pump(WidgetTester tester, Map<int, HeatDay> days) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fullHeatmapProvider.overrideWith(
            (ref) => Stream.value(HeatmapData(
              days: days,
              consistency: computeConsistency(
                completedDayKeys: days.keys,
                today: today,
              ),
            )),
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const HistoryHeatmapScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  const one = HeatDay(workouts: 1, isDeload: false);

  testWidgets('with nothing logged: the empty state', (tester) async {
    await pump(tester, const {});
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.byType(SessionBars), findsNothing);
  });

  testWidgets('opens on this year with both sections', (tester) async {
    await pump(tester, {dayKeyOf(today): one});

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(AppChip, '${today.year}'), findsOneWidget);
    expect(find.text('Sessions per week'), findsOneWidget);
    expect(find.text('Training calendar'), findsOneWidget);
    expect(find.text('1 session'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(find.byType(YearCalendar), findsOneWidget);
    // The first week of use has nothing whole to average over.
    expect(find.text('——'), findsNWidgets(2));
  });

  testWidgets('the year sheet lists every year, newest first', (tester) async {
    final lastYear = DateTime(today.year - 1, 6, 2);
    await pump(tester, {
      dayKeyOf(today): one,
      dayKeyOf(lastYear): const HeatDay(workouts: 2, isDeload: false),
    });

    await tester.tap(find.widgetWithText(AppChip, '${today.year}'));
    await tester.pumpAndSettle();

    expect(find.text('Which year?'), findsOneWidget);
    final rows = tester
        .widgetList<AppRow>(find.byType(AppRow))
        .map((r) => r.title)
        .toList();
    expect(rows, ['${today.year}', '${today.year - 1}']);
    expect(find.text('2 sessions'), findsWidgets);

    await tester.tap(find.text('${today.year - 1}'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppChip, '${today.year - 1}'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
  });

  testWidgets('pressing a bar names its week over it, and again lets it go', (
    tester,
  ) async {
    await pump(tester, {dayKeyOf(today): one});

    final bars = find.byType(SessionBars);
    // The plot's last week, which holds today: the right end of the plot,
    // inside the value gutter's left edge.
    final plot = tester.getRect(bars);
    final at = Offset(plot.right - 60, plot.top + 40);
    await tester.tapAt(at);
    await tester.pump();

    expect(find.text('This week'), findsOneWidget);
    expect(find.text('1 session so far'), findsOneWidget);

    await tester.tapAt(at);
    await tester.pump();
    expect(find.text('This week'), findsNothing);
  });
}
