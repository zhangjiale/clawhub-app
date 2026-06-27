/// 设备令牌（deviceToken）存储接口 — 持久化 Gateway 签发的设备令牌。
///
/// 背景：OpenClaw 协议 §2.2 规定，首次配对成功后，hello-ok 响应中包含
/// `auth.deviceToken` 字段。客户端**必须**持久化此令牌；后续重连时
/// 复用该令牌可避免重复走配对审批流程（§4.11）。
///
/// 令牌可被服务端 `device.token.rotate` 轮换（替换）或 `device.token.revoke`
/// 撤销（删除），客户端应通过 [save]/[delete] 同步这些状态变更。
///
/// 实现类：[SecureStorageDeviceTokenStore]（使用 FlutterSecureStorage）。
/// 通过抽象接口注入，使单元测试可使用 fake 实现替换。
abstract class IDeviceTokenStore {
  /// 持久化 [instanceId] 对应的设备令牌。
  ///
  /// 覆盖语义：重复调用会覆盖旧值，对应 §4.11 `device.token.rotate` 流程。
  /// [deviceToken] 不可为空字符串；调用方需自行校验。
  Future<void> save(String instanceId, String deviceToken);

  /// 加载缓存的设备令牌。
  ///
  /// 返回 `null` 的情况：
  /// - 从未配对过（首次连接）
  /// - 配对被撤销（`device.token.revoke`）
  /// - 持久化层损坏（FlutterSecureStorage 异常已捕获时）
  ///
  /// 返回空字符串也视作 `null` 处理，避免向 Gateway 发送空 bearer token。
  Future<String?> load(String instanceId);

  /// 删除缓存的设备令牌 — 通常在设备被解绑或本地用户登出时调用。
  Future<void> delete(String instanceId);
}
