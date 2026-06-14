import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../debug_print_logger.dart';
import '../i_logger.dart';
import 'device_identity.dart';
import 'i_device_identity_provider.dart';

/// Ed25519 设备身份提供者 — 实现 [IDeviceIdentityProvider]。
///
/// 职责：
/// - Ed25519 密钥对生成与持久化（通过 [FlutterSecureStorage]）
/// - 旧版 ECDSA P-256 密钥自动迁移
/// - V3 签名 payload 的 Ed25519 签名
/// - 并发安全的身份加载（多个并发调用只触发一次密钥生成）
///
/// [secureStorage] 可注入 fake 以便单元测试。
class Ed25519IdentityProvider implements IDeviceIdentityProvider {
  final FlutterSecureStorage _secureStorage;
  final ILogger _logger;

  static const _privateKeyKey = 'clawhub_device_ed25519_seed';
  static const _publicKeyKey = 'clawhub_device_ed25519_pubkey';

  // Legacy keys (ECDSA P-256) — for migration detection
  static const _legacyPrivateKeyKey = 'clawhub_device_private_key';
  static const _legacyPublicKeyKey = 'clawhub_device_public_key';

  /// 设备唯一标识（SHA256 of Ed25519 public key, 64 hex chars）。
  String? _deviceId;

  /// Ed25519 公钥（base64url，32 字节 raw）。
  String? _publicKeyB64;

  /// Ed25519 私钥种子（32 字节）。
  Uint8List? _seedBytes;
  bool _identityLoaded = false;
  Future<DeviceIdentity>? _identityFuture;

  Ed25519IdentityProvider({
    FlutterSecureStorage? secureStorage,
    ILogger? logger,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _logger = logger ?? const DebugPrintLogger();

  // ---------------------------------------------------------------------------
  // IDeviceIdentityProvider 实现
  // ---------------------------------------------------------------------------

  @override
  Future<DeviceIdentity> ensureDeviceIdentity() async {
    if (_identityLoaded) {
      return DeviceIdentity(
        deviceId: _deviceId!,
        publicKeyB64: _publicKeyB64,
        seedBytes: _seedBytes,
      );
    }

    // 防止并发调用同时进入加载路径：用 _identityFuture 作为 pending gate，
    // 让后续调用者等待同一个加载操作完成，避免重复生成密钥或 TOCTOU 崩溃。
    if (_identityFuture != null) {
      return _identityFuture!;
    }
    final completer = Completer<DeviceIdentity>();
    _identityFuture = completer.future;

    try {
      // 1. 尝试加载 Ed25519 密钥对
      final storedSeedB64 = await _secureStorage.read(key: _privateKeyKey);
      final storedPubKeyB64 = await _secureStorage.read(key: _publicKeyKey);

      if (storedSeedB64 != null &&
          storedSeedB64.isNotEmpty &&
          storedPubKeyB64 != null &&
          storedPubKeyB64.isNotEmpty) {
        _seedBytes = base64Url.decode(storedSeedB64);
        _publicKeyB64 = storedPubKeyB64;

        if (!_validateKeypair()) {
          _logger.error(
            '[Ed25519Identity] Loaded keypair failed validation — '
            'clearing and regenerating',
          );
          await _secureStorage.delete(key: _privateKeyKey);
          await _secureStorage.delete(key: _publicKeyKey);
          _seedBytes = null;
          _publicKeyB64 = null;
          // Fall through to generation path below
        } else {
          _logger.info('[Ed25519Identity] Loaded existing Ed25519 keypair');
        }
      }

      if (_seedBytes == null || _publicKeyB64 == null) {
        // 2. 检查旧版 ECDSA P-256 密钥（迁移检测）
        final legacySeed = await _secureStorage.read(key: _legacyPrivateKeyKey);
        if (legacySeed != null && legacySeed.isNotEmpty) {
          _logger.info(
            '[Ed25519Identity] Detected legacy ECDSA P-256 keypair — migrating to Ed25519',
          );
          await _secureStorage.delete(key: _legacyPrivateKeyKey);
          await _secureStorage.delete(key: _legacyPublicKeyKey);
        }

        // 3. 生成新 Ed25519 密钥对
        await _generateAndPersistEd25519Keypair();
      }

      // deviceId = SHA256(publicKeyRaw) — 协议要求 §2.5
      final publicKeyBytes = base64Url.decode(_publicKeyB64!);
      _deviceId = sha256.convert(publicKeyBytes).toString();
      _logger.info(
        '[Ed25519Identity] deviceId (SHA256 of publicKey): $_deviceId',
      );

      // _identityLoaded 必须在 _deviceId 赋值之后才能设为 true，
      // 否则快速路径 DeviceIdentity(deviceId: _deviceId!) 会空指针崩溃。
      _identityLoaded = true;

      final identity = DeviceIdentity(
        deviceId: _deviceId!,
        publicKeyB64: _publicKeyB64,
        seedBytes: _seedBytes,
      );
      completer.complete(identity);
      return identity;
    } catch (error) {
      _identityLoaded = false;
      completer.completeError(error);
      rethrow;
    } finally {
      _identityFuture = null;
    }
  }

  @override
  Future<String> signPayload(String v3Payload) async {
    final identity = await ensureDeviceIdentity();
    final seedBytes = identity.seedBytes;
    if (seedBytes == null) {
      throw StateError(
        'Device identity has no seed bytes — key generation may have failed.',
      );
    }
    // 从种子重建 PrivateKey（ed25519_edwards 的 PrivateKey = 64B seed+pubkey）
    final privateKey = ed.newKeyFromSeed(seedBytes);
    final message = Uint8List.fromList(v3Payload.codeUnits);

    // sign(PrivateKey, Uint8List) → 64 字节签名
    final sig = ed.sign(privateKey, message);
    return base64Url.encode(sig);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// 验证当前内存中的密钥对是否一致且可用。
  ///
  /// 从种子重建私钥，提取内嵌公钥并与持久化公钥比对。
  /// 若种子损坏（例如安全存储写入部分失败），重建的公钥将不匹配，
  /// 此时返回 `false`，调用方应清除并重新生成。
  ///
  /// ed25519_edwards 的 PrivateKey 为 64 字节（32B seed + 32B pubkey），
  /// 因此可从 bytes[32..63] 直接提取公钥，无需额外构造 PublicKey 对象。
  bool _validateKeypair() {
    try {
      final privateKey = ed.newKeyFromSeed(_seedBytes!);

      // PrivateKey = 64 bytes: [32B seed] [32B publicKey]
      // ed25519_edwards 的 PrivateKey 未暴露独立的 .publicKey getter，
      // 因此从 bytes 中直接提取后 32 字节作为公钥。
      _validateKeypairBytesMatch(privateKey);

      // sign 调用成功即证明密钥可用（内部会验证数学一致性）
      const testMessage = 'clawhub-ed25519-validation';
      ed.sign(privateKey, Uint8List.fromList(testMessage.codeUnits));

      return true;
    } catch (error, stackTrace) {
      _logger.error(
        '[Ed25519Identity] Key validation failed: $error',
        stackTrace,
      );
      return false;
    }
  }

  /// 从重建的 [privateKey] 中提取内嵌公钥，与持久化的 [_publicKeyB64] 比对。
  ///
  /// 若两者不匹配，说明安全存储中的种子或公钥已损坏，抛出 [StateError]。
  void _validateKeypairBytesMatch(dynamic privateKey) {
    // PrivateKey.bytes → 64 字节（32B seed + 32B pubkey）
    final rawBytes = privateKey.bytes as List<int>;
    final embeddedPubKey = Uint8List.fromList(
      rawBytes.sublist(32, 64),
    ); // 后 32 字节
    final embeddedPubKeyB64 = base64Url.encode(embeddedPubKey);

    if (embeddedPubKeyB64 != _publicKeyB64) {
      throw StateError(
        'Public key mismatch: embedded=$embeddedPubKeyB64 '
        '!= stored=$_publicKeyB64',
      );
    }
  }

  /// 生成 Ed25519 密钥对并持久化到安全存储。
  ///
  /// 生成后执行 [validateKeypair] 往返检查，确保安全存储未损坏数据。
  Future<void> _generateAndPersistEd25519Keypair() async {
    // generateKey() 返回 KeyPair，内含 privateKey (64B = 32B seed + 32B pubkey)
    // 和 publicKey (32B)。
    final keyPair = ed.generateKey();

    // 提取 32 字节种子用于持久化
    _seedBytes = ed.seed(keyPair.privateKey);
    // 提取 32 字节公钥
    _publicKeyB64 = base64Url.encode(
      Uint8List.fromList(keyPair.publicKey.bytes),
    );

    await _secureStorage.write(
      key: _privateKeyKey,
      value: base64Url.encode(_seedBytes!),
    );
    await _secureStorage.write(key: _publicKeyKey, value: _publicKeyB64);

    if (!_validateKeypair()) {
      _logger.error(
        '[Ed25519Identity] Generated keypair failed validation — '
        'clearing and will retry on next ensureDeviceIdentity()',
      );
      await _secureStorage.delete(key: _privateKeyKey);
      await _secureStorage.delete(key: _publicKeyKey);
      _seedBytes = null;
      _publicKeyB64 = null;
      throw StateError('Ed25519 keypair validation failed after generation');
    }

    _logger.info('[Ed25519Identity] Generated new Ed25519 keypair');
  }
}
