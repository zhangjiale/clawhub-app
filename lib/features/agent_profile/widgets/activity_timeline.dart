import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/models/daily_activity.dart';

/// 30 天活动柱状图(US-019 成长面板时间线)
///
/// **设计要点**:
/// - 30 根柱子固定,横轴每 7 天显示一次 `M/d` 月日标签
/// - 柱高 = `(count / maxCount) * 60`,最小 4px 确保空日仍可见
/// - **每个柱子包 `Semantics` 标签**(如 "2024-06-15: 5 条消息")— 屏幕阅读器
///   必须能感知"哪一天有几条消息",这是 a11y 必修
/// - 整体包 `RepaintBoundary` 避免父 `ListView` rebuild 时触发本 widget 重绘
/// - 数据为空时显示"暂无时间线数据"占位
///
/// **Law 11 笔记**:固定 30 根柱子用 `Row` + 30 个 `SizedBox` 而非
/// `ListView.builder`,因为 `ListView.builder` 只在 `>20` 滚动列表场景下
/// 强制要求。本 widget 是 horizontal 一次性渲染,不需要 lazy build。
class ActivityTimeline extends StatelessWidget {
  final List<DailyActivity> activities;

  const ActivityTimeline({super.key, required this.activities});

  static const double _barAreaHeight = 60;
  static const double _minBarHeight = 4;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s5,
          vertical: XiaSpacing.s4,
        ),
        child: Container(
          height: _barAreaHeight + 32,
          decoration: BoxDecoration(
            color: XiaColors.surface,
            borderRadius: BorderRadius.circular(XiaRadius.md),
            border: Border.all(color: XiaColors.border),
          ),
          alignment: Alignment.center,
          child: const Text(
            '暂无时间线数据',
            style: TextStyle(fontSize: 13, color: XiaColors.text4),
          ),
        ),
      );
    }

    final maxCount = activities
        .map((a) => a.messageCount)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: XiaSpacing.s5),
        child: Container(
          padding: const EdgeInsets.all(XiaSpacing.s4),
          decoration: BoxDecoration(
            color: XiaColors.surface,
            borderRadius: BorderRadius.circular(XiaRadius.md),
            border: Border.all(color: XiaColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '近 30 天活跃度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: XiaColors.text2,
                ),
              ),
              const SizedBox(height: XiaSpacing.s3),
              SizedBox(
                height: _barAreaHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final activity in activities)
                      Expanded(
                        child: _Bar(
                          activity: activity,
                          maxCount: maxCount,
                          minHeight: _minBarHeight,
                          maxHeight: _barAreaHeight,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: XiaSpacing.s2),
              ActivityTimelineAxisLabels(activities: activities),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单根柱子 — 包含 a11y Semantics 标签。
class _Bar extends StatelessWidget {
  final DailyActivity activity;
  final int maxCount;
  final double minHeight;
  final double maxHeight;

  const _Bar({
    required this.activity,
    required this.maxCount,
    required this.minHeight,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final height = maxCount == 0
        ? minHeight
        : (activity.messageCount / maxCount) * maxHeight;
    final isEmpty = activity.messageCount == 0;
    final bar = SizedBox(
      height: height.clamp(minHeight, maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isEmpty ? XiaColors.text4 : XiaColors.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    return Semantics(
      label: '${_formatDate(activity.dayBucket)}: ${activity.messageCount} 条消息',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: bar,
      ),
    );
  }
}

/// 横轴标签:每 7 天显示一次 `M/d` 格式月日。
@visibleForTesting
class ActivityTimelineAxisLabels extends StatelessWidget {
  final List<DailyActivity> activities;

  const ActivityTimelineAxisLabels({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    // 每 7 天显示一次标签(index 0, 7, 14, 21, 28),含末尾。
    // 若 length 非 30,fallback 到每 N/5 处显示一次。
    final total = activities.length;
    final step = total > 7 ? 7 : (total / 5).ceil().clamp(1, total);

    return SizedBox(
      height: 14,
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              // 只在「i 是 step 倍数」或「i 是末尾且不是 step 倍数」时
              // 显示标签 —— 避免末尾与 step 倍数重合时产生两个相邻标签。
              // 例如 total=7/step=2 时,旧实现会同时显示 index=6(既是 6%2==0
              // 又是 total-1),视觉上重复;total=30/step=7 时,index=28 与
              // 末尾 29 距离仅 1,虽不重叠但相邻标签信息密度低。
              child: ActivityTimelineAxisLabels.shouldShowLabel(i, total, step)
                  ? Text(
                      _formatShortDate(activities[i].dayBucket),
                      style: const TextStyle(
                        fontSize: 10,
                        color: XiaColors.text4,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  /// 是否在 i 处显示横轴标签。
  ///
  /// 规则:
  /// - 起点 (i == 0): 总显示。
  /// - step 倍数 (i % step == 0): 显示。
  /// - 末尾 (i == total - 1): 仅当末尾不是 step 倍数时显示(避免重复)。
  @visibleForTesting
  static bool shouldShowLabel(int i, int total, int step) {
    final isAtStep = i % step == 0;
    final isAtLast = i == total - 1;
    return isAtStep || (isAtLast && !isAtStep);
  }
}

/// `dayBucket` 转 `M/d` 短格式(本地时区,因为 UI 是面向用户的)。
String _formatShortDate(int dayBucket) {
  final dt = DailyActivity.formatBucketAsDate(dayBucket).toLocal();
  return '${dt.month}/${dt.day}';
}

/// `dayBucket` 转 ISO 格式 `YYYY-MM-DD` 用于 a11y 标签。
String _formatDate(int dayBucket) {
  final dt = DailyActivity.formatBucketAsDate(dayBucket).toLocal();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}
