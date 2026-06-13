import 'device_identity.dart';

/// 设备身份提供者 — 抽象 Ed25519 密钥管理与签名。
///
/// 从 [WsGatewayClient] 中分离，遵循单一职责原则：
/// - Ed25519 密钥生命周期管理（生成、持久化、迁移）
/// - V3 签名 payload 签名
///
/// 实现类：[Ed25519IdentityProvider]（使用 FlutterSecureStorage）。
///
/// 注入到 [WsGatewayClient] 后，客户端无需感知存储后端或加密算法，
/// 且可通过 fake 实现进行单元测试。
abstract class IDeviceIdentityProvider {
  /// 加载或生成设备身份（Ed25519 密钥对）。
  ///
  /// - 首次调用：从 SecureStorage 读取或生成新密钥对并持久化。
  /// - 后续调用：返回缓存的 [DeviceIdentity]。
  /// - 并发安全：多次并发调用只触发一次加载。
  /// - 如果检测到旧版 ECDSA P-256 密钥，自动迁移到 Ed25519。
  Future<DeviceIdentity> ensureDeviceIdentity();

  /// 用设备的 Ed25519 私钥对 [v3Payload] 签名。
  ///
  /// [v3Payload] 由 [buildV3SignaturePayload] 构造。
  /// 返回 base64url 编码的 64 字节 Ed25519 签名。
  Future<String> signPayload(String v3Payload);
}
