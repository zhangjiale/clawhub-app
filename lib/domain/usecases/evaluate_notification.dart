import '../models/notification_event.dart';
import '../models/user_preferences.dart';

/// 通知判定决策 (US-018)
///
/// [EvaluateNotificationUseCase.evaluate] 的返回值。密封类，三个分支：
/// - [ShowDecision]：应立即发出系统通知
/// - [DndSuppressedDecision]：命中免打扰时段，入静默队列待汇总
/// - [DroppedDecision]：开关关闭 / 噪音事件，丢弃
sealed class NotificationDecision {
  const NotificationDecision();
}

/// 应立即发出通知。
class ShowDecision extends NotificationDecision {
  /// 通知标题 (通常含虾名 / 实例名)。
  final String title;

  /// 通知正文 (摘要，≤50 字)。
  final String body;

  /// 原始事件，供 dispatcher 决定深链路由路径。
  final NotificationEvent event;

  const ShowDecision({
    required this.title,
    required this.body,
    required this.event,
  });
}

/// 命中 DND，静默入队待汇总。
class DndSuppressedDecision extends NotificationDecision {
  final NotificationEvent event;

  const DndSuppressedDecision(this.event);
}

/// 丢弃 (开关关闭 / 噪音)。
class DroppedDecision extends NotificationDecision {
  const DroppedDecision();
}

/// 通知摘要 (正文) 的最大字符数 — PRD AC-1 要求 ≤50 字。
const _maxSummaryChars = 50;

/// 判定一个 [NotificationEvent] 是否应发出通知，以及如何处理 (US-018 AC-1/AC-3)。
///
/// 纯 domain UseCase (Law 1)，无任何 Flutter / drift / riverpod 依赖。
/// 所有时间相关的判定都接收外部传入的 [DateTime now]，便于单测注入固定时间。
///
/// 判定规则 (按顺序短路)：
/// 1. 通知总开关 [UserPreferences.notificationsEnabled] 关 → [DroppedDecision]
/// 2. 按事件类别对应开关关 → [DroppedDecision]
/// 3. 命中 DND 时段 ([isInDnd]) → [DndSuppressedDecision]
/// 4. 否则 → [ShowDecision] (摘要已截断 ≤50 字)
///
/// 连接变化事件额外规则：仅 [ConnectionChangeEvent.isOnlineDrop] (任意非离线
/// 状态 → offline，含 reconnecting→offline 的重连耗尽终态) 视为可通知；其他
/// 转换（重连成功、短暂的 online↔reconnecting 抖动）视为噪音丢弃，避免
/// 弱网刷屏。
class EvaluateNotificationUseCase {
  const EvaluateNotificationUseCase();

  /// 评估单个事件，返回决策。
  NotificationDecision evaluate(
    NotificationEvent event,
    UserPreferences prefs,
    DateTime now,
  ) {
    // 1. 总开关
    if (!prefs.notificationsEnabled) {
      return const DroppedDecision();
    }

    // 2. 类别开关 + 噪音过滤
    if (!_isWantedByCategorySwitch(event, prefs)) {
      return const DroppedDecision();
    }

    // 3. DND 静默
    if (isInDnd(prefs, now)) {
      return DndSuppressedDecision(event);
    }

    // 4. 立即发出
    final (title, body) = _compose(event);
    return ShowDecision(title: title, body: body, event: event);
  }

  /// 当前时间是否落在 DND 时段内。
  ///
  /// DND 关闭直接返回 false。窗口判定支持跨午夜 (start > end)：
  /// - 跨午夜 (如 22:00–08:00)：now >= start 或 now < end
  /// - 同日 (如 13:00–14:00)：start <= now < end
  /// 起点包含、终点排除 (与"结束时刻即恢复通知"语义一致)。
  bool isInDnd(UserPreferences prefs, DateTime now) {
    if (!prefs.dndEnabled) return false;

    final nowMin = now.hour * 60 + now.minute;
    final startMin = prefs.dndStartHour * 60 + prefs.dndStartMinute;
    final endMin = prefs.dndEndHour * 60 + prefs.dndEndMinute;

    if (startMin == endMin) {
      // start == end 视为全天 DND
      return true;
    }
    if (startMin < endMin) {
      // 同日窗口
      return nowMin >= startMin && nowMin < endMin;
    }
    // 跨午夜窗口
    return nowMin >= startMin || nowMin < endMin;
  }

  /// 距 DND 结束的时刻；当前不在 DND 内 (或 DND 关闭 / 全天 DND) 时返回 null。
  ///
  /// 供 dispatcher/coordinator 计算 Timer 延迟，在前台存活期间到期后
  /// 触发汇总推送。跨午夜场景下结束时刻可能在次日。
  ///
  /// 全天 DND (start == end) 没有离散的"结束时刻"，返回 null —— 此时
  /// coordinator 不排 Timer、不周期性补发；积压条目改由用户关闭 DND 时
  /// 通过 [NotificationCoordinator.onPrefsChanged] 触发补发。
  DateTime? nextDndEndTime(UserPreferences prefs, DateTime now) {
    if (!isInDnd(prefs, now)) return null;

    final startMin = prefs.dndStartHour * 60 + prefs.dndStartMinute;
    final endMin = prefs.dndEndHour * 60 + prefs.dndEndMinute;
    if (startMin == endMin) {
      // 全天 DND —— 永远在 DND 内，但没有结束时刻。
      return null;
    }

    final nowEndOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      prefs.dndEndHour,
      prefs.dndEndMinute,
    );

    // 若结束时刻在当前时刻之后 (同日)，直接用今日结束时刻；
    // 否则结束时刻在次日。
    if (nowEndOfDay.isAfter(now)) {
      return nowEndOfDay;
    }
    return nowEndOfDay.add(const Duration(days: 1));
  }

  /// 距下一次 DND **开始**的时刻；当前已在 DND 内 (或 DND 关闭 / 全天 DND)
  /// 时返回 null。
  ///
  /// 供 coordinator 在非 DND 时段排定"进入 DND"的 Timer —— 进入后再由
  /// [nextDndEndTime] 排定结束 Timer。这保证了：
  /// - 非DND 时启动可立即补发积压 (跨重启 catch-up)，并排定下一个 DND 起点；
  /// - 前台存活期间跨入 DND 再结束也能正确触发汇总。
  DateTime? nextDndStartTime(UserPreferences prefs, DateTime now) {
    if (!prefs.dndEnabled) return null;
    if (isInDnd(prefs, now)) return null;

    final startMin = prefs.dndStartHour * 60 + prefs.dndStartMinute;
    final endMin = prefs.dndEndHour * 60 + prefs.dndEndMinute;
    if (startMin == endMin) {
      // 全天 DND —— 没有"进入"时刻 (始终在 DND 内，由 isInDnd 分支返回 null)。
      return null;
    }

    final nowStartOfDay = DateTime(
      now.year,
      now.month,
      now.day,
      prefs.dndStartHour,
      prefs.dndStartMinute,
    );

    // 若今日起点在当前时刻之后，用今日；否则下一个起点在次日。
    if (nowStartOfDay.isAfter(now)) {
      return nowStartOfDay;
    }
    return nowStartOfDay.add(const Duration(days: 1));
  }

  // ---------------------------------------------------------------------------

  /// 类别开关 + 噪音过滤。返回 false 表示该事件不被任何分支接受。
  bool _isWantedByCategorySwitch(
    NotificationEvent event,
    UserPreferences prefs,
  ) {
    switch (event) {
      case ReplyEvent():
        return prefs.notifyOnReply;
      case ErrorEvent():
        return prefs.notifyOnError;
      case ConnectionChangeEvent(:final isOnlineDrop):
        // 仅"掉线"视为可通知；重连成功等噪音丢弃 (notifyOnConnectionChange 开关仍要尊重)。
        if (!prefs.notifyOnConnectionChange) return false;
        return isOnlineDrop;
    }
  }

  /// 生成 (title, body)。
  /// body 已做空白折叠 + 截断 (≤50 字)。
  (String, String) _compose(NotificationEvent event) {
    switch (event) {
      case ReplyEvent(:final agentName, :final contentPreview):
        return (agentName, _truncate(contentPreview));
      case ErrorEvent(:final agentName, :final errorSummary):
        return ('$agentName 出错了', _truncate(errorSummary));
      case ConnectionChangeEvent(:final instanceName, :final isOnlineDrop):
        final title = isOnlineDrop ? '$instanceName 已断开' : instanceName;
        return (title, isOnlineDrop ? '虾连接已断开，点击查看' : '连接状态变化');
    }
  }

  String _truncate(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _maxSummaryChars) return collapsed;
    return collapsed.substring(0, _maxSummaryChars);
  }
}
