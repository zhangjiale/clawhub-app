// Debug CLI script — print() is the intended I/O channel, not a leak.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

/// 连接诊断 — 测试编码格式 & 签名方式
///
/// 用法: `dart run test/debug_connection.dart <ws_url> <token>`
void main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('用法: dart run test/debug_connection.dart <ws_url> <token>');
    exit(1);
  }
  final rawUrl = args[0];
  final token = args[1];
  final t = token.length > 12
      ? '${token.substring(0, 8)}...${token.substring(token.length - 4)}'
      : token;
  print('Token: $t\n');

  // 同一个密钥对用于所有测试
  final keyPair = ed25519.generateKey();
  final pubBytes = Uint8List.fromList(keyPair.publicKey.bytes);
  final pubHex = hex.encode(pubBytes);
  final pubB64 = base64Encode(pubBytes);
  final deviceId = sha256.convert(pubBytes).toString();
  print('publicKey (hex, 64 chars): $pubHex');
  print('publicKey (base64, 44 chars): $pubB64');
  print('deviceId (SHA256): ${deviceId.substring(0, 16)}...\n');

  // ── 测试 1: publicKey hex, signature hex, 签名 nonce ──
  await _test(
    rawUrl,
    token,
    deviceId,
    pubHex,
    keyPair,
    label: 'pub=hex, sig=hex, sign(nonce)',
    pubEncode: (b) => hex.encode(b),
    sigEncode: (b) => hex.encode(b),
    buildMsg: (nonce) => Uint8List.fromList(nonce.codeUnits),
  );

  // ── 测试 2: publicKey hex, signature base64, 签名 nonce ──
  await _test(
    rawUrl,
    token,
    deviceId,
    pubHex,
    keyPair,
    label: 'pub=hex, sig=base64, sign(nonce)',
    pubEncode: (b) => hex.encode(b),
    sigEncode: (b) => base64Encode(b),
    buildMsg: (nonce) => Uint8List.fromList(nonce.codeUnits),
  );

  // ── 测试 3: publicKey base64, signature hex, 签名 nonce ──
  await _test(
    rawUrl,
    token,
    deviceId,
    pubB64,
    keyPair,
    label: 'pub=base64, sig=hex, sign(nonce)',
    pubEncode: (b) => base64Encode(b),
    sigEncode: (b) => hex.encode(b),
    buildMsg: (nonce) => Uint8List.fromList(nonce.codeUnits),
  );

  // ── 测试 4: 签名 nonce 的 raw hex bytes ──
  await _test(
    rawUrl,
    token,
    deviceId,
    pubHex,
    keyPair,
    label: 'pub=hex, sig=hex, sign(nonce hex bytes)',
    pubEncode: (b) => hex.encode(b),
    sigEncode: (b) => hex.encode(b),
    buildMsg: (nonce) => _hexToBytes(nonce.replaceAll('-', '')),
  );

  // ── 测试 5: 签名 "v3|deviceId|...|signedAt|token|nonce|..." (hex pub/sig) ──
  await _test(
    rawUrl,
    token,
    deviceId,
    pubHex,
    keyPair,
    label: 'pub=hex, sig=hex, sign(V3 payload)',
    pubEncode: (b) => hex.encode(b),
    sigEncode: (b) => hex.encode(b),
    buildMsg: (nonce) => Uint8List.fromList(
      'v3|$deviceId|cli|node|node||${DateTime.now().millisecondsSinceEpoch}|$token|$nonce|flutter|'
          .codeUnits,
    ),
  );

  // ── 测试 6: 不带 signedAt/nonce 字段 ──
  await _testMinimal(rawUrl, token, deviceId, pubHex, keyPair);

  print('\n═══════════════════════════════════════════');
}

Future<void> _test(
  String rawUrl,
  String token,
  String deviceId,
  String pubEncoded,
  ed25519.KeyPair keyPair, {
  required String label,
  required String Function(Uint8List) pubEncode,
  required String Function(Uint8List) sigEncode,
  required Uint8List Function(String nonce) buildMsg,
}) async {
  print('── $label ──');
  final uri = Uri.parse(rawUrl).replace(
    queryParameters: {...Uri.parse(rawUrl).queryParameters, 'token': token},
  );
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 10));
    final reqId = 'd${DateTime.now().millisecondsSinceEpoch}';
    final gc = Completer<String?>(), gr = Completer<Map<String, dynamic>>();
    ws.listen((d) {
      try {
        final j = jsonDecode(d as String) as Map<String, dynamic>;
        if (j['event'] == 'connect.challenge' && !gc.isCompleted) {
          gc.complete(
            (j['payload'] as Map<String, dynamic>?)?['nonce'] as String?,
          );
        } else if (j['type'] == 'res' && j['id'] == reqId && !gr.isCompleted) {
          gr.complete(j);
        }
      } catch (
        _
      ) {} // iron-law-allow: Law8 -- ignore malformed JSON in debug listener
    });
    final nonce = await gc.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (nonce == null) {
      print('  ❌ no nonce');
      return;
    }

    final msg = buildMsg(nonce);
    final sig = ed25519.sign(keyPair.privateKey, msg);
    final signedAt = DateTime.now().millisecondsSinceEpoch;

    final p = <String, dynamic>{
      'minProtocol': 4,
      'maxProtocol': 4,
      'client': {
        'id': 'cli',
        'version': '1.0.0',
        'platform': 'flutter',
        'mode': 'node',
        'displayName': 'ClawHub',
      },
      'role': 'node',
      'scopes': <String>[],
      'caps': <String>[],
      'commands': <String>[],
      'permissions': <String, bool>{},
      'device': {
        'id': deviceId,
        'publicKey': pubEncode(Uint8List.fromList(keyPair.publicKey.bytes)),
        'signature': sigEncode(sig),
        'signedAt': signedAt,
        'nonce': nonce,
      },
      'auth': {'token': token},
      'locale': 'zh-CN',
      'userAgent': 'clawhub/1.0.0',
    };
    ws.add(
      jsonEncode({
        'type': 'req',
        'id': reqId,
        'method': 'connect',
        'params': p,
      }),
    );
    final r = await gr.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => <String, dynamic>{'timeout': true},
    );
    if (r['timeout'] == true) {
      print('  ⏰ timeout');
    } else if (r['ok'] == true) {
      print('  🟢🟢🟢 HELLO-OK! 🟢🟢🟢');
    } else {
      final e = r['error'] as Map<String, dynamic>?;
      print('  ❌ ${e?['code']}: ${e?['message']}');
    }
  } catch (e) {
    print('  ❌ $e');
  } finally {
    await ws?.close();
  }
}

Future<void> _testMinimal(
  String rawUrl,
  String token,
  String deviceId,
  String pubEncoded,
  ed25519.KeyPair keyPair,
) async {
  print('── minimal: no signedAt/nonce, sign(nonce) ──');
  final uri = Uri.parse(rawUrl).replace(
    queryParameters: {...Uri.parse(rawUrl).queryParameters, 'token': token},
  );
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 10));
    final reqId = 'd${DateTime.now().millisecondsSinceEpoch}';
    final gc = Completer<String?>(), gr = Completer<Map<String, dynamic>>();
    ws.listen((d) {
      try {
        final j = jsonDecode(d as String) as Map<String, dynamic>;
        if (j['event'] == 'connect.challenge' && !gc.isCompleted) {
          gc.complete(
            (j['payload'] as Map<String, dynamic>?)?['nonce'] as String?,
          );
        } else if (j['type'] == 'res' && j['id'] == reqId && !gr.isCompleted) {
          gr.complete(j);
        }
      } catch (
        _
      ) {} // iron-law-allow: Law8 -- ignore malformed JSON in debug listener
    });
    final nonce = await gc.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (nonce == null) {
      print('  ❌ no nonce');
      return;
    }

    final sig = ed25519.sign(
      keyPair.privateKey,
      Uint8List.fromList(nonce.codeUnits),
    );
    final p = <String, dynamic>{
      'minProtocol': 4,
      'maxProtocol': 4,
      'client': {
        'id': 'cli',
        'version': '1.0.0',
        'platform': 'flutter',
        'mode': 'node',
        'displayName': 'ClawHub',
      },
      'role': 'node',
      'scopes': <String>[],
      'caps': <String>[],
      'commands': <String>[],
      'permissions': <String, bool>{},
      'device': {
        'id': deviceId,
        'publicKey': pubEncoded,
        'signature': hex.encode(sig),
      },
      'auth': {'token': token},
      'locale': 'zh-CN',
      'userAgent': 'clawhub/1.0.0',
    };
    ws.add(
      jsonEncode({
        'type': 'req',
        'id': reqId,
        'method': 'connect',
        'params': p,
      }),
    );
    final r = await gr.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => <String, dynamic>{'timeout': true},
    );
    if (r['timeout'] == true) {
      print('  ⏰ timeout');
    } else if (r['ok'] == true) {
      print('  🟢🟢🟢 HELLO-OK! 🟢🟢🟢');
    } else {
      final e = r['error'] as Map<String, dynamic>?;
      print('  ❌ ${e?['code']}: ${e?['message']}');
    }
  } catch (e) {
    print('  ❌ $e');
  } finally {
    await ws?.close();
  }
}

Uint8List _hexToBytes(String hexStr) {
  final bytes = <int>[];
  for (var i = 0; i < hexStr.length; i += 2) {
    bytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}
