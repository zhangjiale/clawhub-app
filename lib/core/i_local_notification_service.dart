/// 平台本地通知服务抽象 (US-018 ACL)
///
/// 收敛 `flutter_local_notifications` 平台 API，业务层 (NotificationDispatcher)
/// 只依赖此接口，便于单测注入 fake，不触碰真实平台插件。
///
/// 点击通知的深链跳转由 [setupOnTap] 注册的回调处理；调用方 (bootstrap)
/// 负责把 routePath 解析为实际路由跳转 (AppRouter.router.go)。
abstract class ILocalNotificationService {
  /// 初始化平台插件、创建通知通道。App 启动时调用一次。
  Future<void> initialize();

  /// 请求系统通知权限 (iOS authorization / Android 13+ POST_NOTIFICATIONS)。
  /// 返回是否已授权。
  Future<bool> requestPermissions();

  /// 发出一条通知。
  ///
  /// [id] 通知 id (相同 id 会覆盖上一条)；[channel] 通道类别；
  /// [title]/[body] 标题与正文；[routePath] 点击跳转路径，存入 payload。
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    String? routePath,
  });

  /// 取消单条通知。
  Future<void> cancel(int id);

  /// 注册"通知被点击"回调。回调参数为通知 payload 中的 routePath (可空)。
  void setupOnTap(void Function(String? routePath) onTap);

  /// 释放资源。
  Future<void> dispose();
}

/// 通知通道类别 — 回复 / 错误 / 连接变化。
enum NotificationChannelId { reply, error, connection }
