import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'i_device_token_store.dart';

/// [IDeviceTokenStore] 的安全存储实现 — 使用 [FlutterSecureStorage] 持久化设备令牌。
///
/// 存储键格式：`clawhub_device_token_<instanceId>`，每个实例独立存储。
///
/// 设备令牌本身已是高熵的不透明字符串（由 Gateway Ed25519 私钥签发），
/// 不需要额外加密；但仍使用 Keychain/Keystore 防止明文落盘。
///
/// [secureStorage] 可注入 fake 以便单元测试。
class SecureStorageDeviceTokenStore implements IDeviceTokenStore {
  final FlutterSecureStorage _secureStorage;

  /// Key prefix for all device tokens.  The suffix is the instance UUID.
  /// Chosen to coexist with Ed25519IdentityProvider's keys
  /// (`clawhub_device_ed25519_*`) without collision.
  static const String _keyPrefix = 'clawhub_device_token_';

  SecureStorageDeviceTokenStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String _key(String instanceId) => '$_keyPrefix$instanceId';

  @override
  Future<void> save(String instanceId, String deviceToken) async {
    await _secureStorage.write(key: _key(instanceId), value: deviceToken);
  }

  @override
  Future<String?> load(String instanceId) async {
    final value = await _secureStorage.read(key: _key(instanceId));
    // Treat empty string as absent — prevents sending an empty bearer
    // token to the Gateway if the storage layer ever returns one.
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> delete(String instanceId) async {
    await _secureStorage.delete(key: _key(instanceId));
  }
}
