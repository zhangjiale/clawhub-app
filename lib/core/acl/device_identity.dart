import 'dart:typed_data';

/// 设备身份值对象 — 由 [IDeviceIdentityProvider] 加载或生成。
///
/// - [deviceId] = SHA256(publicKey) 的十六进制串（64 hex chars）。
/// - [publicKeyB64] = Ed25519 公钥的 base64url 编码（32 bytes raw）。
/// - [seedBytes] = Ed25519 私钥种子（32 bytes），用于签名。
class DeviceIdentity {
  final String deviceId;
  final String? publicKeyB64;
  final Uint8List? seedBytes;

  const DeviceIdentity({
    required this.deviceId,
    this.publicKeyB64,
    this.seedBytes,
  });
}
