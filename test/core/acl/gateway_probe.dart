// Debug CLI script — print() is the intended I/O channel, not a leak.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

/// Phase 2: Gateway 协议探测 — 捕获原始帧验证 chat.* 生命周期
///
/// 用法: `dart run test/core/acl/gateway_probe.dart <ws_url> <token>`
///
/// 输出:
///   - 完整握手流程 (connect.challenge → connect → hello-ok)
///   - chat.send 请求的原始响应
///   - chat.typing / chat.delta / chat.done 各事件的时间戳和 payload
///   - 协议验证结论

// ============================================================================
// 验证条目
// ============================================================================

final _verification = <String, String?>{};

void _verify(String item, bool condition, String detail) {
  _verification[item] = condition ? '✅' : '❌ $detail';
}

// ============================================================================
// Main
// ============================================================================

void main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      '用法: dart run test/core/acl/gateway_probe.dart <ws_url> <token> [--agents-only]',
    );
    stderr.writeln(
      '示例: dart run test/core/acl/gateway_probe.dart ws://192.168.1.100:18789 my-token',
    );
    stderr.writeln(
      '      --agents-only  : 只验证 agents.list 后退出（跳过 chat.send 验证）',
    );
    exit(1);
  }

  final rawUrl = args[0];
  final token = args[1];
  final agentsOnly = args.length >= 3 && args[2] == '--agents-only';
  final uri = Uri.parse(rawUrl).replace(
    queryParameters: {...Uri.parse(rawUrl).queryParameters, 'token': token},
  );

  print('═══════════════════════════════════════════════════════');
  print('  OpenClaw Gateway Protocol Probe');
  print('═══════════════════════════════════════════════════════');
  print('URL:   $rawUrl');
  print(
    'Token: ${token.length > 12 ? '${token.substring(0, 8)}...${token.substring(token.length - 4)}' : token}',
  );
  print('');

  // ── 生成 Ed25519 密钥对 ──────────────────────────────────
  final keyPair = ed25519.generateKey();
  final pubBytes = Uint8List.fromList(keyPair.publicKey.bytes);
  final pubB64 = base64Encode(pubBytes);
  final deviceId = sha256.convert(pubBytes).toString();
  print('deviceId: ${deviceId.substring(0, 16)}...');
  print('');

  // ── 连接 WebSocket ──────────────────────────────────────
  print('── 连接 ──');
  final ws = await WebSocket.connect(
    uri.toString(),
  ).timeout(const Duration(seconds: 10));
  print('Connected to ${ws.readyState}');
  print('');

  final responseCompleters = <String, Completer<Map<String, dynamic>>>{};
  final events = <Map<String, dynamic>>[];
  final eventTimestamps = <String, DateTime>{};

  Completer<Map<String, dynamic>> newCompleter(String id) {
    final c = Completer<Map<String, dynamic>>();
    responseCompleters[id] = c;
    return c;
  }

  ws.listen(
    (data) {
      final frame = jsonDecode(data as String) as Map<String, dynamic>;
      final type = frame['type'] as String?;
      final event = frame['event'] as String?;
      final id = frame['id'] as String?;
      final ok = frame['ok'];

      final timestamp = DateTime.now();
      final tsStr =
          '${timestamp.hour.toString().padLeft(2, '0')}:'
          '${timestamp.minute.toString().padLeft(2, '0')}:'
          '${timestamp.second.toString().padLeft(2, '0')}.'
          '${timestamp.millisecond.toString().padLeft(3, '0')}';

      switch (type) {
        case 'event':
          events.add(frame);
          final evt = event ?? 'unknown';
          eventTimestamps[evt] = timestamp;
          print(
            '[$tsStr] EVENT  $evt'
            '${frame['payload'] != null ? ' payload=${_truncate(jsonEncode(frame['payload']), 120)}' : ''}',
          );
        case 'res':
          final errorInfo = frame['error'] as Map<String, dynamic>?;
          final errorStr = errorInfo != null
              ? ' error=${errorInfo['code']} message=${errorInfo['message']}'
                    '${errorInfo['details'] != null ? ' details=${jsonEncode(errorInfo['details'])}' : ''}'
              : '';
          print(
            '[$tsStr] RES    id=$id ok=$ok$errorStr'
            '${frame['payload'] != null ? ' payload=${_truncate(jsonEncode(frame['payload']), 80)}' : ''}',
          );
          if (id != null && responseCompleters.containsKey(id)) {
            responseCompleters[id]!.complete(frame);
          }
        default:
          print('[$tsStr] ???    $frame');
      }
    },
    onError: (error) {
      stderr.writeln('WebSocket error: $error');
      for (final c in responseCompleters.values) {
        if (!c.isCompleted) c.completeError(error);
      }
    },
    onDone: () {
      print('WebSocket closed');
    },
  );

  // ── 等待 connect.challenge ──────────────────────────────
  print('Waiting for connect.challenge...');
  await Future.delayed(const Duration(seconds: 1));

  final challenge = events.firstWhere(
    (f) => f['event'] == 'connect.challenge',
    orElse: () => <String, dynamic>{},
  );

  if (challenge.isEmpty) {
    stderr.writeln('ERROR: Did not receive connect.challenge');
    exit(1);
  }

  final nonce = challenge['payload']?['nonce'] as String? ?? '';
  print('');
  print('Received nonce: $nonce');
  print('');

  // ── 构造 connect 请求 ───────────────────────────────────
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final scopes = [
    'operator.admin',
    'operator.read',
    'operator.write',
    'operator.approvals',
    'operator.pairing',
  ];

  final v3Payload =
      'v3|$deviceId|gateway-client|ui|operator|'
      '${scopes.join(',')}|$nowMs|$token|$nonce|flutter|phone';

  final sig = ed25519.sign(
    keyPair.privateKey,
    Uint8List.fromList(v3Payload.codeUnits),
  );

  final connectRequest = {
    'type': 'req',
    'id': 'probe-connect',
    'method': 'connect',
    'params': {
      'minProtocol': 3,
      'maxProtocol': 4,
      'client': {
        'id': 'gateway-client',
        'version': '1.0.0-probe',
        'platform': 'flutter',
        'mode': 'ui',
        'deviceFamily': 'phone',
      },
      'role': 'operator',
      'scopes': scopes,
      'caps': ['tool-events'],
      'commands': [],
      'permissions': {},
      'device': {
        'id': deviceId,
        'publicKey': pubB64,
        'signature': base64Encode(sig),
        'signedAt': nowMs,
        'nonce': nonce,
      },
      'auth': {'token': token},
      'locale': 'zh-CN',
      'userAgent': 'xiahub-probe/1.0.0',
    },
  };

  print('── 发送 connect 请求 ──');
  ws.add(jsonEncode(connectRequest));
  print('Sent connect (id=probe-connect)');

  // ── 等待 connect 响应 ──────────────────────────────────
  Map<String, dynamic> connectResponse;
  try {
    connectResponse = await newCompleter(
      'probe-connect',
    ).future.timeout(const Duration(seconds: 15));
  } catch (e) {
    stderr.writeln('ERROR: connect response timed out: $e');
    exit(1);
  }

  print('');
  print('── Connect 响应 ──');
  _verify(
    'Handshake',
    connectResponse['ok'] == true,
    'connect ok=${connectResponse['ok']}',
  );

  if (connectResponse['ok'] != true) {
    final error = connectResponse['error'] as Map<String, dynamic>?;
    print('ERROR: connect failed');
    print('  code: ${error?['code']}');
    print('  message: ${error?['message']}');

    if (error?['code'] == 'NOT_PAIRED') {
      final details = error?['details'] as Map<String, dynamic>?;
      print('');
      print('⚠️  PAIRING_REQUIRED — 新设备需要审批');
      print('   requestId: ${details?['requestId']}');
      print('   请在服务器执行:');
      print('   \$ openclaw devices approve ${details?['requestId']}');
      print('   然后重新运行本脚本。');
    }
    await ws.close();
    exit(1);
  }

  print('Connected! Protocol v${connectResponse['payload']?['protocol']}');
  print(
    'Methods: ${(connectResponse['payload']?['features']?['methods'] as List?)?.length ?? 0} available',
  );

  // ── 1. 获取 Agent 列表 ──────────────────────────────────
  print('');
  print('── 获取 Agent 列表 ──');
  final agentsRequest = {
    'type': 'req',
    'id': 'probe-agents',
    'method': 'agents.list',
    'params': {},
  };
  ws.add(jsonEncode(agentsRequest));
  print('Sent agents.list (id=probe-agents)');

  Map<String, dynamic> agentsResponse;
  try {
    agentsResponse = await newCompleter(
      'probe-agents',
    ).future.timeout(const Duration(seconds: 15));
  } catch (e) {
    stderr.writeln('ERROR: agents.list timed out: $e');
    await ws.close();
    exit(1);
  }

  if (agentsResponse['ok'] != true) {
    final error = agentsResponse['error'] as Map<String, dynamic>?;
    stderr.writeln(
      'ERROR: agents.list failed: ${error?['code']} ${error?['message']}',
    );
    await ws.close();
    exit(1);
  }

  final agents = (agentsResponse['payload']?['agents'] as List<dynamic>?) ?? [];
  print('Found ${agents.length} agent(s):');
  String? firstAgentId;
  for (final a in agents) {
    final agent = a as Map<String, dynamic>;
    final agentId = agent['id'] as String? ?? '';
    final name = agent['name'] as String?;
    final model = agent['model'] as Map<String, dynamic>?;
    print(
      '  - id: $agentId${name != null ? '  name: $name' : ''}'
      '${model != null ? '  model: ${model['primary']}' : ''}',
    );
    // ── 诊断模式：dump 完整原始 JSON，验证 bio 字段名 ──
    print('    raw: ${jsonEncode(agent)}');
    firstAgentId ??= agentId;
  }

  // 诊断模式：dump agents.list 响应 payload 的顶层 keys（确认 bio 在哪个嵌套层）
  final payloadKeys = (agentsResponse['payload'] as Map<String, dynamic>? ?? {})
      .keys
      .toList();
  print('agents.list payload top-level keys: $payloadKeys');

  if (firstAgentId == null) {
    stderr.writeln('ERROR: No agents available on this Gateway');
    await ws.close();
    exit(1);
  }

  if (agentsOnly) {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('  --agents-only: 跳过 chat.send 验证');
    print('═══════════════════════════════════════════════════════');
    await ws.close();
    exit(0);
  }

  // ── 2. 发送 chat.send 请求 ──────────────────────────────
  print('');
  print('═══════════════════════════════════════════════════════');
  print('  发送 chat.send 并观察流式事件');
  print('═══════════════════════════════════════════════════════');

  // Try both 'sessionKey' + 'message' (real Gateway from error message)
  // Session key format: agent:{agentId}:{scope} (see doc §7.2)
  final sessionKey = 'agent:$firstAgentId:main';
  final chatRequest = {
    'type': 'req',
    'id': 'probe-chat-001',
    'method': 'chat.send',
    'params': {
      'sessionKey': sessionKey,
      'message': 'Hi',
      'idempotencyKey': 'probe-idem-${DateTime.now().millisecondsSinceEpoch}',
    },
  };

  final preEvents = events.length;
  ws.add(jsonEncode(chatRequest));
  print(
    'Sent chat.send (id=probe-chat-001, sessionKey="$sessionKey", message="Hi")',
  );

  // 等待 40 秒收集所有事件
  print('Waiting for streaming events (40s max)...');
  await Future.delayed(const Duration(seconds: 40));
  print('');

  // ── 分析收集到的事件 ───────────────────────────────────
  final chatEvents = events.skip(preEvents).toList();

  print('── 收到的事件 (chat.send 之后) ──');
  if (chatEvents.isEmpty) {
    print('  (无)');
    print('');
    print('⚠️  未收到任何事件。可能原因:');
    print('  1. Agent "main" 不存在或未配置');
    print('  2. Gateway 版本不支持 chat.send');
    print('  3. 网络问题');
  }

  for (final e in chatEvents) {
    final evt = e['event'] as String? ?? 'unknown';
    print('  $evt');
  }
  print('');

  // ── 协议验证 ────────────────────────────────────────────
  print('═══════════════════════════════════════════════════════');
  print('  协议验证结果');
  print('═══════════════════════════════════════════════════════');

  final eventNames = chatEvents.map((e) => e['event'] as String?).toSet();

  // 核心验证
  _verify(
    'chat.typing 事件存在',
    eventNames.contains('chat.typing'),
    'events found: $eventNames',
  );

  _verify(
    'chat.delta 事件存在',
    eventNames.contains('chat.delta'),
    'events found: $eventNames',
  );

  _verify(
    'chat.done 事件存在',
    eventNames.contains('chat.done'),
    'events found: $eventNames',
  );

  // 事件顺序验证
  final orderedEvents = chatEvents
      .map((e) => e['event'] as String?)
      .where((e) => e != null)
      .toList();

  final typingIdx = orderedEvents.indexOf('chat.typing');
  final deltaIdx = orderedEvents.indexOf('chat.delta');
  final doneIdx = orderedEvents.indexOf('chat.done');

  _verify(
    'chat.typing 在 chat.delta 之前',
    typingIdx < deltaIdx || (typingIdx == -1 && deltaIdx != -1),
    'typing@$typingIdx, delta@$deltaIdx',
  );

  _verify(
    'chat.delta 在 chat.done 之前',
    deltaIdx < doneIdx || (deltaIdx == -1 && doneIdx != -1),
    'delta@$deltaIdx, done@$doneIdx',
  );

  // Delta 内容验证
  final deltaEvents = chatEvents
      .where((e) => e['event'] == 'chat.delta')
      .toList();

  if (deltaEvents.isNotEmpty) {
    final firstDelta = deltaEvents.first['payload'] as Map<String, dynamic>?;
    _verify(
      'chat.delta 携带 delta 字段',
      firstDelta?.containsKey('delta') ?? false,
      'payload keys: ${firstDelta?.keys}',
    );

    _verify(
      'chat.delta 携带 agentId',
      firstDelta?.containsKey('agentId') ?? false,
      'payload keys: ${firstDelta?.keys}',
    );

    // 拼接所有 delta
    final allDeltas = deltaEvents
        .map(
          (e) =>
              (e['payload'] as Map<String, dynamic>?)?['delta'] as String? ??
              '',
        )
        .join();
    print('');
    print('  拼接后的完整文本: "$allDeltas"');
  }

  // 工具调用
  final toolEvents = eventNames.where(
    (e) => e?.startsWith('chat.tool_') ?? false,
  );
  if (toolEvents.isNotEmpty) {
    print('');
    print('  工具调用事件: $toolEvents');
  }

  // 打印其他事件
  final otherEvents = eventNames
      .where(
        (e) =>
            e != null &&
            !e.startsWith('chat.') &&
            e != 'connect.challenge' &&
            e != 'health' &&
            e != 'tick',
      )
      .toList();
  if (otherEvents.isNotEmpty) {
    print('');
    print('  其他事件: $otherEvents');
  }

  print('');
  print('───────────────────────────────────────────────────────');
  for (final entry in _verification.entries) {
    print('  ${entry.value}  ${entry.key}');
  }
  print('───────────────────────────────────────────────────────');

  await ws.close();
}

String _truncate(String s, int maxLen) =>
    s.length <= maxLen ? s : '${s.substring(0, maxLen)}...';
