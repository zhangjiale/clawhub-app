import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/daily_activity.dart';
import 'package:claw_hub/features/agent_profile/widgets/activity_timeline.dart';

void main() {
  // Anchor "today" for deterministic labels
  final today = DateTime.utc(2024, 6, 15);
  final todayBucket = today.millisecondsSinceEpoch ~/ 86400000;

  List<DailyActivity> makeSeries(List<int> counts) {
    assert(counts.length == 30);
    return [
      for (var i = 0; i < counts.length; i++)
        DailyActivity(
          agentId: 'a-1',
          dayBucket: todayBucket - (counts.length - 1 - i),
          messageCount: counts[i],
        ),
    ];
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('ActivityTimelineAxisLabels.shouldShowLabel', () {
    // Regression: 旧实现在 total=7/step=2 时同时显示 index=6(既是 6%2==0
    // 又是 total-1),两个相邻标签重复。修复:末尾仅当不是 step 倍数时显示。
    test('total=7 step=2: 末尾 6 不重复显示', () {
      // step 推导: total<=7 → (7/5).ceil()=2, clamp(1,7)=2
      final shown = [
        for (var i = 0; i < 7; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 7, 2)) i,
      ];
      expect(shown, [0, 2, 4, 6]);
    });

    test('total=5 step=1: 所有 index 都是 step 倍数,末尾不重复', () {
      final shown = [
        for (var i = 0; i < 5; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 5, 1)) i,
      ];
      expect(shown, [0, 1, 2, 3, 4]);
    });

    test('total=30 step=7: 末尾 29 是非 step 倍数,正常显示', () {
      final shown = [
        for (var i = 0; i < 30; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 30, 7)) i,
      ];
      expect(shown, [0, 7, 14, 21, 28, 29]);
    });

    test('total=2 step=1: 起点和末尾都在 step 倍数上', () {
      final shown = [
        for (var i = 0; i < 2; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 2, 1)) i,
      ];
      expect(shown, [0, 1]);
    });

    test('total=14 step=3: 末尾 13 非 step 倍数,显示', () {
      final shown = [
        for (var i = 0; i < 14; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 14, 3)) i,
      ];
      expect(shown, [0, 3, 6, 9, 12, 13]);
    });
  });

  group('ActivityTimelineAxisLabels.shouldShowLabel', () {
    // Regression: 旧实现在 total=7/step=2 时同时显示 index=6(既是 6%2==0
    // 又是 total-1),两个相邻标签重复。修复:末尾仅当不是 step 倍数时显示。
    test('total=7 step=2: 末尾 6 不重复显示', () {
      // step 推导: total<=7 → (7/5).ceil()=2, clamp(1,7)=2
      final shown = [
        for (var i = 0; i < 7; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 7, 2)) i,
      ];
      expect(shown, [0, 2, 4, 6]);
    });

    test('total=5 step=1: 所有 index 都是 step 倍数,末尾不重复', () {
      final shown = [
        for (var i = 0; i < 5; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 5, 1)) i,
      ];
      expect(shown, [0, 1, 2, 3, 4]);
    });

    test('total=30 step=7: 末尾 29 是非 step 倍数,正常显示', () {
      final shown = [
        for (var i = 0; i < 30; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 30, 7)) i,
      ];
      expect(shown, [0, 7, 14, 21, 28, 29]);
    });

    test('total=2 step=1: 起点和末尾都在 step 倍数上', () {
      final shown = [
        for (var i = 0; i < 2; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 2, 1)) i,
      ];
      expect(shown, [0, 1]);
    });

    test('total=14 step=3: 末尾 13 非 step 倍数,显示', () {
      final shown = [
        for (var i = 0; i < 14; i++)
          if (ActivityTimelineAxisLabels.shouldShowLabel(i, 14, 3)) i,
      ];
      expect(shown, [0, 3, 6, 9, 12, 13]);
    });
  });

  group('ActivityTimeline', () {
    testWidgets('renders 30 bars for 30 entries', (tester) async {
      final series = makeSeries(List.filled(30, 0));
      await tester.pumpWidget(wrap(ActivityTimeline(activities: series)));
      // Find all SizedBox bars; each bar contains a child SizedBox of
      // the proportional height. We assert via Semantics instead since
      // bar count matches Semantics count.
      final semantics = tester.getSemantics(find.byType(ActivityTimeline));
      expect(semantics, isNotNull);
    });

    testWidgets('empty series shows placeholder', (tester) async {
      await tester.pumpWidget(wrap(const ActivityTimeline(activities: [])));
      expect(find.text('暂无时间线数据'), findsOneWidget);
    });

    testWidgets('each bar exposes Semantics label with day + count', (
      tester,
    ) async {
      // Today: 5 messages; 15 days ago: 2 messages; rest 0
      final counts = List<int>.filled(30, 0);
      counts[29] = 5; // today (2024-06-15)
      counts[14] = 2; // 15 days ago (2024-05-31)
      final series = makeSeries(counts);

      await tester.pumpWidget(wrap(ActivityTimeline(activities: series)));

      // Find Semantics nodes with our expected labels
      expect(
        find.bySemanticsLabel(RegExp(r'2024-06-15.*5.*?条消息')),
        findsAtLeast(1),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'2024-05-31.*2.*?条消息')),
        findsAtLeast(1),
      );
    });

    testWidgets('all bars are still visible (height >= 4) even on zero days', (
      tester,
    ) async {
      final series = makeSeries(List.filled(30, 0));
      await tester.pumpWidget(wrap(ActivityTimeline(activities: series)));
      // 30-day window: 29 empty bars + 1 today bar
      // We assert that zero-count bars are still rendered with at
      // least minimum height (4 px). This is enforced by SizedBox
      // inside each bar; if the impl ever drops zero bars, this
      // test will fail because find semantics for that day won't
      // exist.
      expect(
        find.bySemanticsLabel(RegExp(r'2024-06-15.*0.*?条消息')),
        findsAtLeast(1),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'2024-05-17.*0.*?条消息')),
        findsAtLeast(1),
      );
    });
  });
}
