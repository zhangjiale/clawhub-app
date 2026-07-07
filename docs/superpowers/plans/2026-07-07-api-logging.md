# API 请求/响应日志（App 内诊断页） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured Gateway req/res + connection-lifecycle logging surfaced via an in-app diagnostics page, to troubleshoot protocol/connection issues on-device.

**Architecture:** Inject an `IApiLogger?` into `ConnectionManager` (Approach A) at 15 pure-observation sites (3 req/res choke points + 12 lifecycle handlers). A pure-Dart `ApiLogStore` ring buffer (500 entries) implements `IApiLogger` and is exposed to UI via a Riverpod `StreamProvider`. Payloads are truncate-then-parse redacted (≤2KB) to protect the send hot path. Diagnostics page is release-visible with payload collapsed by default + a one-time warning.

**Tech Stack:** Flutter, Riverpod (manual providers, NOT riverpod_generator), Drift/SQLite (unchanged), `web_socket_channel`, `uuid`, `shared_preferences` (existing dep). Pure-Dart core types (no Flutter) for `IApiLogger`/`ApiLogStore`/`redactAndTruncate`.

## Global Constraints

(Spec: `docs/superpowers/specs/2026-07-07-api-logging-design.md`, commit `59471dd`.)

- **Iron Law 1**: `lib/domain/` zero Flutter/Riverpod/drift imports. All new types live in `lib/core/` (pure Dart) or `lib/features/`.
- **Iron Law 3**: ACL depends on `IApiLogger` (core abstraction), never on `ApiLogStore` concrete impl.
- **Iron Law 8**: No empty catch — `logXxx` catch emits `ILogger.error` breadcrumb.
- **Iron Law 11**: Diagnostics list uses `ListView.builder`.
- **Iron Law 14**: New diagnostics widget needs ≥2 tests.
- **Iron Law 17**: TDD per-file — test FIRST, run red, implement, run green, commit.
- **“采集日志绝不能影响协议路径” invariant**: (1) `redactAndTruncate` truncate-then-parse → O(threshold) not O(payloadSize); (2) `logResponse` called AFTER `completer.complete(frame)`; (3) `logXxx` fully try/catch-wrapped + throwing-logger contract test.
- **DI**: manual `Provider` (non-`.autoDispose`) for `apiLogStoreProvider` — app-lifetime singleton.
- **Background isolate**: `callbackDispatcher`'s `buildGatewayClient` call passes `apiLogger: null` (no logging in background; `ApiLogStore` lives in main isolate only).
- **Conventional Commits**: `feat(api-logging):`, `test(api-logging):`, etc.
- **No auto-commit by the worker** unless the plan step explicitly says to commit (each task ends with a commit step).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `lib/core/i_api_logger.dart` | Create | `IApiLogger` interface + `ApiLogEntry` + `ApiLogDirection`/`ApiLogKind`. Pure Dart. |
| `lib/core/api_log_redactor.dart` | Create | Pure fn `redactAndTruncate(rawJson, maxBytes, payloadSize)` — truncate-then-parse redaction. Pure Dart. |
| `lib/core/api_log_store.dart` | Create | `ApiLogStore implements IApiLogger` — ring buffer + stream + duration matching + orphan sweep. Pure Dart. |
| `lib/core/acl/connection_manager.dart` | Modify | Add `IApiLogger?` ctor param + 15 observation calls + `String? method` param on `sendRawRequest`. |
| `lib/core/acl/ws_gateway_client.dart` | Modify | Add `IApiLogger?` param, forward to both `ConnectionManager` constructions; pass `Methods.chatSend` to `sendRawRequest`. |
| `lib/app/background_sync/callback_dispatcher.dart` | Modify | `buildGatewayClient` gains `IApiLogger? apiLogger` param (background passes null). |
| `lib/app/di/providers.dart` | Modify | Add `apiLogStoreProvider` + `apiLoggerProvider`; wire into `wsGatewayClientProvider`. |
| `lib/features/diagnostics/providers/diagnostics_providers.dart` | Create | `diagnosticsEntriesProvider` (StreamProvider, newest-first) + warning-flag provider. |
| `lib/features/diagnostics/diagnostics_page.dart` | Create | Diagnostics page UI (flat reverse list, tap-to-expand, clear, first-entry warning). |
| `lib/app/router/router.dart` | Modify | Add `AppRoutes.settingsDiagnostics` + `_settingsSubRoute('diagnostics', ...)`. |
| `lib/features/settings/settings_page.dart` | Modify | Add 「诊断」`SettingsRow`. |
| `test/core/i_api_logger_test.dart` | Create | Entry construction test (TDD). |
| `test/core/api_log_redactor_test.dart` | Create | Redactor unit tests (TDD). |
| `test/core/api_log_store_test.dart` | Create | Store unit tests (TDD). |
| `test/core/acl/connection_manager_logging_test.dart` | Create | Instrumentation + throwing-logger contract tests (TDD). |
| `test/core/acl/ws_gateway_client_test.dart` | Modify | Add forwarding assertions. |
| `test/features/diagnostics/diagnostics_page_test.dart` | Create | Widget tests (Law 14). |

---

## Task 1: `IApiLogger` interface + `ApiLogEntry`

**Files:**
- Create: `lib/core/i_api_logger.dart`
- Test: `test/core/i_api_logger_test.dart`

**Interfaces:**
- Produces: `abstract interface class IApiLogger` with `logRequest`, `logResponse`, `logStateChange`; `enum ApiLogDirection { outgoing, incoming }`; `enum ApiLogKind { req, res, state }`; `class ApiLogEntry` (plain immutable, NOT freezed). `ApiLogEntry.direction` is **nullable** (state entries have null direction — refinement over spec §3.1; `in` is a Dart reserved word so the enum uses `outgoing`/`incoming`).

- [ ] **Step 1: Write the failing test**

Create `test/core/i_api_logger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/i_api_logger.dart';

void main() {
  group('ApiLogEntry', () {
    test('constructs with required fields; nullables default to null', () {
      final entry = ApiLogEntry(
        id: 'e1',
        timestampMs: 1000,
        instanceId: 'inst-1',
        direction: ApiLogDirection.outgoing,
        kind: ApiLogKind.req,
        methodOrEvent: 'chat.send',
        requestId: 'r1',
        byteSize: 42,
      );
      expect(entry.id, 'e1');
      expect(entry.direction, ApiLogDirection.outgoing);
      expect(entry.kind, ApiLogKind.req);
      expect(entry.byteSize, 42);
      expect(entry.ok, isNull);
      expect(entry.durationMs, isNull);
      expect(entry.payloadPreview, isNull);
      expect(entry.state, isNull);
      expect(entry.message, isNull);
    });

    test('state entry has null direction and payload', () {
      final entry = ApiLogEntry(
        id: 'e2',
        timestampMs: 2000,
        instanceId: 'inst-1',
        kind: ApiLogKind.state,
        state: 'authFailed',
        message: 'Auth failed: bad token',
      );
      expect(entry.direction, isNull);
      expect(entry.kind, ApiLogKind.state);
      expect(entry.state, 'authFailed');
      expect(entry.payloadPreview, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/i_api_logger_test.dart`
Expected: FAIL — `Failed to import 'package:claw_hub/core/i_api_logger.dart'` / target of URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/i_api_logger.dart`:

```dart
/// API 请求/响应日志接口 — ACL 采集点依赖此抽象，不依赖具体环形缓冲实现。
///
/// 与 [ILogger]（console/dev 路径）补充共存：本接口服务 App 内结构化诊断路径
/// （带 req↔res 链接 / durationMs / instanceId）。spec §2.3 决策 5。
abstract interface class IApiLogger {
  /// 记录一条出站请求帧（req）。rawJson 由实现内部 redactAndTruncate 脱敏截断。
  /// 永不抛（spec §4.2 不变量）。
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  });

  /// 记录一条入站响应帧（res）。**必须在 completer.complete(frame) 之后调**
  /// （spec §5.1），确保日志路径失败不阻塞响应交付。永不抛。
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  });

  /// 记录一条连接生命周期/诊断事件。[state] 可为 null（纯 message 诊断条目，
  /// 如 buffer overflow / payload too large）。永不抛。
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  });
}

/// 日志方向。state 条目方向为 null（见 [ApiLogEntry.direction]）。
enum ApiLogDirection { outgoing, incoming }

/// 日志类别。
enum ApiLogKind { req, res, state }

/// 一条 API/生命周期日志。普通不可变类（非 freezed，spec §2.3 决策 1）。
class ApiLogEntry {
  final String id;
  final int timestampMs;
  final String instanceId;
  final ApiLogDirection? direction; // null for state entries
  final ApiLogKind kind;
  final String? methodOrEvent; // "chat.send" / "connect"；state 为 null
  final String? requestId; // 帧 id，链接 req↔res（state 为 null）
  final bool? ok; // res 用
  final String? errorCode; // res 错误码，如 "NOT_PAIRED"
  final String? state; // state 用，如 "authFailed"；纯 message 诊断可为 null
  final int? byteSize; // req/res 帧字节数
  final int? durationMs; // res 用，由 store 匹配 req 算出
  final String? payloadPreview; // 截断+脱敏后的 JSON（≤2KB）；state 为 null
  final String? message; // state 用的人类可读说明

  const ApiLogEntry({
    required this.id,
    required this.timestampMs,
    required this.instanceId,
    this.direction,
    required this.kind,
    this.methodOrEvent,
    this.requestId,
    this.ok,
    this.errorCode,
    this.state,
    this.byteSize,
    this.durationMs,
    this.payloadPreview,
    this.message,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/i_api_logger_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i_api_logger.dart test/core/i_api_logger_test.dart
git commit -m "feat(api-logging): add IApiLogger interface + ApiLogEntry"
```

---

## Task 2: `redactAndTruncate` (truncate-then-parse)

**Files:**
- Create: `lib/core/api_log_redactor.dart`
- Test: `test/core/api_log_redactor_test.dart`

**Interfaces:**
- Produces: `String redactAndTruncate(String rawJson, {int maxBytes, int? payloadSize})`; constants `redactedKeys`, `defaultMaxPayloadPreviewBytes`, `largeFrameThresholdBytes`, `regexFallbackScanBytes`. Pure Dart (`dart:convert` only).

- [ ] **Step 1: Write the failing test**

Create `test/core/api_log_redactor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_redactor.dart';

void main() {
  group('redactAndTruncate', () {
    test('redacts top-level token', () {
      final raw = '{"method":"connect","params":{"auth":{"token":"secret-abc"}}}';
      final out = redactAndTruncate(raw);
      expect(out, contains('"token":"<redacted>"'));
      expect(out, isNot(contains('secret-abc')));
    });

    test('redacts nested auth.token (structured path)', () {
      final raw = '{"params":{"auth":{"token":"t1"}},"device":{"signature":"sig","nonce":"n1","publicKey":"pk"}}';
      final out = redactAndTruncate(raw);
      expect(out, contains('"token":"<redacted>"'));
      expect(out, contains('"signature":"<redacted>"'));
      expect(out, contains('"nonce":"<redacted>"'));
      expect(out, contains('"publicKey":"pk"')); // publicKey NOT redacted
      expect(out, isNot(contains('t1')));
      expect(out, isNot(contains('"sig"')));
    });

    test('redacts authToken / sessionToken / bearerToken', () {
      final raw = '{"authToken":"a","sessionToken":"b","bearerToken":"c"}';
      final out = redactAndTruncate(raw);
      expect(out, isNot(contains('"a"')));
      expect(out, isNot(contains('"b"')));
      expect(out, isNot(contains('"c"')));
      expect(out, contains('<redacted>'));
    });

    test('preserves payload ≤ maxBytes intact', () {
      final raw = '{"method":"agents.list","params":{}}';
      final out = redactAndTruncate(raw, maxBytes: 2048);
      expect(out, raw);
    });

    test('truncates > maxBytes with marker including original byte count', () {
      final big = '{"x":"${'a' * 5000}"}';
      final out = redactAndTruncate(big, maxBytes: 100);
      expect(out, contains('…(truncated,'));
      expect(out, contains('bytes total)'));
      // original byte count ~5000+ overhead
      expect(out.length, lessThan(200));
    });

    test('large frame (payloadSize > 64KB) skips jsonDecode — does not parse full body', () {
      // A 70KB frame whose tail is malformed JSON; if jsonDecode ran on the whole
      // thing it would throw and fall to regex anyway. The point: large-frame path
      // only scans the first 8KB.
      final head = '{"method":"chat.send","params":{"message":"hi","auth":{"token":"t-big"}}}';
      final padding = ' ' * 70000;
      final raw = head + padding + '}'; // overall > 64KB
      final out = redactAndTruncate(raw, payloadSize: 70050);
      expect(out, contains('"token":"<redacted>"')); // head scanned by regex
      expect(out, contains('truncated'));
    });

    test('malformed JSON with nested auth.token → regex fallback still redacts', () {
      // Broken JSON (unterminated) that jsonDecode rejects; regex must still catch token.
      final raw = '{"params":{"auth":{"token":"leak-me"';
      final out = redactAndTruncate(raw);
      expect(out, contains('"token":"<redacted>"'));
      expect(out, isNot(contains('leak-me')));
    });

    test('never throws on garbage input', () {
      expect(() => redactAndTruncate(''), returnsNormally);
      expect(() => redactAndTruncate('not json at all {{{'), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/api_log_redactor_test.dart`
Expected: FAIL — import target doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/api_log_redactor.dart`:

```dart
import 'dart:convert';

/// RE-AUDIT WHEN: gateway_protocol.dart 加新方法/凭据字段 → 审计 [redactedKeys]
/// 是否覆盖（spec §3.2 协议升级审计）。
const Set<String> redactedKeys = {
  'token',
  'deviceToken',
  'signature',
  'signPayload',
  'nonce',
  'secret',
  'password',
  'accessToken',
  'refreshToken',
  // 防御性：协议若新增这些字段名也覆盖
  'authToken',
  'sessionToken',
  'bearerToken',
};

const int defaultMaxPayloadPreviewBytes = 2048; // 最终 preview 截断
const int largeFrameThresholdBytes = 65536; // >此值跳过 jsonDecode 走 regex
const int regexFallbackScanBytes = 8192; // regex 兜底只扫前 N 字节

/// 脱敏 + 截断（truncate-then-parse，保护热路径，spec §3.2）。
///
/// 解析成本 O(阈值) 而非 O(payloadSize)：大帧（payloadSize > [largeFrameThresholdBytes]）
/// 跳过 jsonDecode，在前 [regexFallbackScanBytes] 子串上跑 regex 脱敏；小帧结构化脱敏。
/// 最终按 [maxBytes] 截断并附 `…(truncated, N bytes total)` marker。永不抛。
String redactAndTruncate(
  String rawJson, {
  int maxBytes = defaultMaxPayloadPreviewBytes,
  int? payloadSize,
}) {
  final int originalBytes;
  final bool largeFrame;
  if (payloadSize != null) {
    originalBytes = payloadSize;
    largeFrame = payloadSize > largeFrameThresholdBytes;
  } else {
    // 无 payloadSize 时用字符数近似（避免对大帧 utf8.encode 造成 jank）
    originalBytes = rawJson.length;
    largeFrame = rawJson.length > largeFrameThresholdBytes;
  }

  try {
    if (largeFrame) {
      return _truncate(_regexRedact(_head(rawJson)), maxBytes, originalBytes);
    }
    final decoded = jsonDecode(rawJson);
    _redactInPlace(decoded);
    return _truncate(jsonEncode(decoded), maxBytes, originalBytes);
  } catch (_) {
    // iron-law-allow: Law8 -- redactor 永不抛；畸形 JSON 走 regex 兜底
    return _truncate(_regexRedact(_head(rawJson)), maxBytes, originalBytes);
  }
}

String _head(String s) =>
    s.length > regexFallbackScanBytes ? s.substring(0, regexFallbackScanBytes) : s;

void _redactInPlace(Object? node) {
  if (node is Map) {
    for (final key in node.keys.toList()) {
      if (redactedKeys.contains(key)) {
        node[key] = '<redacted>';
      } else {
        _redactInPlace(node[key]);
      }
    }
  } else if (node is List) {
    for (final i = 0; i < node.length; i++) {
      _redactInPlace(node[i]);
    }
  }
}

String _regexRedact(String s) {
  var result = s;
  for (final key in redactedKeys) {
    result = result.replaceAll(
      RegExp('"$key"\\s*:\\s*"[^"]*"'),
      '"$key":"<redacted>"',
    );
  }
  return result;
}

String _truncate(String s, int maxBytes, int originalBytes) {
  final bytes = utf8.encode(s);
  if (bytes.length <= maxBytes) return s;
  // 回退到 UTF-8 字符边界，避免切到多字节字符中间
  var cut = maxBytes;
  while (cut > 0 && (bytes[cut] & 0xC0) == 0x80) {
    cut--;
  }
  final truncated = utf8.decode(bytes.sublist(0, cut), allowMalformed: true);
  return '$truncated…(truncated, $originalBytes bytes total)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/api_log_redactor_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/api_log_redactor.dart test/core/api_log_redactor_test.dart
git commit -m "feat(api-logging): add truncate-then-parse redactor"
```

---

## Task 3: `ApiLogStore` ring buffer

**Files:**
- Create: `lib/core/api_log_store.dart`
- Test: `test/core/api_log_store_test.dart`

**Interfaces:**
- Consumes: `IApiLogger`/`ApiLogEntry` (Task 1), `redactAndTruncate` (Task 2), `ILogger` (existing `lib/core/i_logger.dart`).
- Produces: `class ApiLogStore implements IApiLogger` with ctor `ApiLogStore({int maxEntries, ILogger? logger})`, `List<ApiLogEntry> snapshot()`, `Stream<ApiLogEntry> get onEntry`, `void clear()`, `void dispose()`; constants `defaultMaxEntries`, `pendingReqSweepThreshold`, `pendingReqTtlMs`.

- [ ] **Step 1: Write the failing test**

Create `test/core/api_log_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';

void main() {
  late ApiLogStore store;

  setUp(() => store = ApiLogStore(maxEntries: 3));

  tearDown(() => store.dispose());

  group('ApiLogStore', () {
    test('snapshot returns unmodifiable view', () {
      store.logStateChange(instanceId: 'i', state: 'connected', message: 'ok');
      final snap = store.snapshot();
      expect(snap.length, 1);
      expect(() => snap.add(ApiLogEntry(
            id: 'x',
            timestampMs: 0,
            instanceId: 'i',
            kind: ApiLogKind.state,
            message: 'x',
          )), throwsUnsupportedError);
    });

    test('FIFO eviction at capacity', () {
      for (var i = 0; i < 5; i++) {
        store.logStateChange(instanceId: 'i', state: 's$i', message: 'm$i');
      }
      final snap = store.snapshot();
      expect(snap.length, 3); // capped
      // oldest evicted → first kept is s2
      expect(snap.first.state, 's2');
      expect(snap.last.state, 's4');
    });

    test('res matches req → durationMs computed and non-negative', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'chat.send',
        byteSize: 10,
        rawJson: '{"method":"chat.send","params":{"message":"hi"}}',
      );
      store.logResponse(
        instanceId: 'i',
        requestId: 'r1',
        ok: true,
        byteSize: 20,
        rawJson: '{"ok":true,"payload":{}}',
      );
      final snap = store.snapshot();
      final res = snap.lastWhere((e) => e.kind == ApiLogKind.res);
      expect(res.durationMs, isNotNull);
      expect(res.durationMs! >= 0, isTrue);
    });

    test('res with no matching req → durationMs null (does not throw)', () {
      store.logResponse(
        instanceId: 'i',
        requestId: 'orphan',
        ok: false,
        errorCode: 'CONNECTION_LOST',
        byteSize: 5,
        rawJson: '{"ok":false}',
      );
      final res = store.snapshot().single;
      expect(res.durationMs, isNull);
      expect(res.ok, isFalse);
      expect(res.errorCode, 'CONNECTION_LOST');
    });

    test('request payload is redacted', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'connect',
        byteSize: 40,
        rawJson: '{"method":"connect","params":{"auth":{"token":"secret"}}}',
      );
      final req = store.snapshot().single;
      expect(req.payloadPreview, contains('<redacted>'));
      expect(req.payloadPreview, isNot(contains('secret')));
    });

    test('onEntry stream emits on each add', () async {
      final received = <ApiLogKind>[];
      final sub = store.onEntry.listen((e) => received.add(e.kind));
      store.logStateChange(instanceId: 'i', state: 'connected', message: 'ok');
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'm',
        byteSize: 1,
        rawJson: '{}',
      );
      await Future.delayed(Duration.zero);
      expect(received, [ApiLogKind.state, ApiLogKind.req]);
      await sub.cancel();
    });

    test('clear wipes entries and pending map', () {
      store.logRequest(
        instanceId: 'i',
        requestId: 'r1',
        method: 'm',
        byteSize: 1,
        rawJson: '{}',
      );
      store.clear();
      expect(store.snapshot(), isEmpty);
      // after clear, a res for r1 has no durationMs
      store.logResponse(
          instanceId: 'i', requestId: 'r1', ok: true, byteSize: 1, rawJson: '{}');
      expect(store.snapshot().single.durationMs, isNull);
    });

    test('orphan sweep evicts stale pending reqs and emits a state log', () {
      // Force sweep: exceed pendingReqSweepThreshold (200) with orphan reqs.
      for (var i = 0; i < 205; i++) {
        store.logRequest(
          instanceId: 'i',
          requestId: 'req-$i',
          method: 'm',
          byteSize: 1,
          rawJson: '{}',
        );
      }
      // The last logRequest triggers a sweep; a state entry about eviction should exist.
      final hasEvictLog = store.snapshot().any(
            (e) =>
                e.kind == ApiLogKind.state &&
                (e.message?.contains('evicted') ?? false),
          );
      expect(hasEvictLog, isTrue);
    });

    test('throwing redactor input does not propagate', () {
      // redactAndTruncate never throws, but guard the contract anyway.
      expect(
        () => store.logRequest(
          instanceId: 'i',
          requestId: 'r1',
          method: 'm',
          byteSize: 1,
          rawJson: 'not json {{{',
        ),
        returnsNormally,
      );
      expect(store.snapshot().length, 1);
    });
  });
}
```

Note on the sweep test: `logRequest` calls `_maybeSweep` only when `_pendingReqTs.length > 200`. Each `logRequest` adds one pending entry, so the 201st `logRequest` triggers the sweep. 205 calls guarantees the sweep fires and emits the eviction state log.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/api_log_store_test.dart`
Expected: FAIL — import doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/api_log_store.dart`:

```dart
import 'dart:async';
import 'dart:collection';

import 'package:claw_hub/core/api_log_redactor.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:uuid/uuid.dart';

/// 环形缓冲实现 [IApiLogger]（spec §4）。纯 Dart，不碰 Flutter/Riverpod。
///
/// 同一实例既被 [ConnectionManager] 当 logger 用、又被 UI provider 当数据源读
/// （SSOT，spec §2.3 决策 2）。永不抛（spec §4.2 不变量）。
class ApiLogStore implements IApiLogger {
  ApiLogStore({this.maxEntries = defaultMaxEntries, ILogger? logger})
      : _logger = logger;

  static const int defaultMaxEntries = 500;
  static const int pendingReqSweepThreshold = 200;
  static const int pendingReqTtlMs = 30000;

  final int maxEntries;
  final ILogger? _logger;
  final Uuid _uuid = const Uuid();

  final List<ApiLogEntry> _entries = [];
  final Map<String, int> _pendingReqTs = {}; // requestId → sentAt ms
  final StreamController<ApiLogEntry> _ctrl =
      StreamController<ApiLogEntry>.broadcast();

  List<ApiLogEntry> snapshot() => UnmodifiableListView(_entries);
  Stream<ApiLogEntry> get onEntry => _ctrl.stream;

  void clear() {
    _entries.clear();
    _pendingReqTs.clear();
  }

  void dispose() => _ctrl.close();

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _pendingReqTs[requestId] = now;
      _maybeSweep(now);
      _add(ApiLogEntry(
        id: _uuid.v4(),
        timestampMs: now,
        instanceId: instanceId,
        direction: ApiLogDirection.outgoing,
        kind: ApiLogKind.req,
        methodOrEvent: method,
        requestId: requestId,
        byteSize: byteSize,
        payloadPreview: redactAndTruncate(rawJson, payloadSize: byteSize),
      ));
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logRequest failed: $e', st);
    }
  }

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sentAt = _pendingReqTs.remove(requestId);
      final durationMs = sentAt == null ? null : now - sentAt;
      _maybeSweep(now);
      _add(ApiLogEntry(
        id: _uuid.v4(),
        timestampMs: now,
        instanceId: instanceId,
        direction: ApiLogDirection.incoming,
        kind: ApiLogKind.res,
        requestId: requestId,
        ok: ok,
        errorCode: errorCode,
        byteSize: byteSize,
        durationMs: durationMs,
        payloadPreview: rawJson == null
            ? null
            : redactAndTruncate(rawJson, payloadSize: byteSize),
      ));
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logResponse failed: $e', st);
    }
  }

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) {
    try {
      _add(ApiLogEntry(
        id: _uuid.v4(),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        instanceId: instanceId,
        kind: ApiLogKind.state,
        state: state,
        message: message,
      ));
    } catch (e, st) {
      _logger?.error('[ApiLogStore] logStateChange failed: $e', st);
    }
  }

  void _add(ApiLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0); // FIFO
    }
    if (!_ctrl.isClosed) _ctrl.add(entry);
  }

  /// 惰性清理超时未匹配 res 的 pending req（spec §4.2）。清理不静默——发一条
  /// state 诊断条目。直接走 [_add] 避免再入 [logStateChange] 的 try/catch。
  void _maybeSweep(int nowMs) {
    if (_pendingReqTs.length <= pendingReqSweepThreshold) return;
    final stale = <String>[];
    _pendingReqTs.forEach((id, ts) {
      if (nowMs - ts > pendingReqTtlMs) stale.add(id);
    });
    for (final id in stale) {
      _pendingReqTs.remove(id);
    }
    if (stale.isNotEmpty) {
      _add(ApiLogEntry(
        id: _uuid.v4(),
        timestampMs: nowMs,
        instanceId: 'system',
        kind: ApiLogKind.state,
        state: null,
        message: 'evicted ${stale.length} pending req entries older than '
            '${pendingReqTtlMs ~/ 1000}s',
      ));
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/api_log_store_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/api_log_store.dart test/core/api_log_store_test.dart
git commit -m "feat(api-logging): add ApiLogStore ring buffer"
```

---

## Task 4: `ConnectionManager` instrumentation

**Files:**
- Modify: `lib/core/acl/connection_manager.dart`
- Test: `test/core/acl/connection_manager_logging_test.dart`

**Interfaces:**
- Consumes: `IApiLogger` (Task 1). The `ConnectionManager` constructor gains `IApiLogger? apiLogger`. `sendRawRequest` gains `String? method` named param.
- Produces: a `ConnectionManager` that emits 15 observation calls (no control-flow change). Downstream `WsGatewayClient` (Task 5) will forward the logger and the `method` param.

This is the largest task. All 15 insertions are **observation-only** — each is a single `_apiLogger?.logXxx(...)` line (or `// observation-only — do not add control flow`-commented). They never `await`, never branch control flow, never throw out.

- [ ] **Step 1: Write the failing test**

Create `test/core/acl/connection_manager_logging_test.dart`:

```dart
import 'dart:async';

import 'package:claw_hub/core/acl/connection_manager.dart';
import 'package:claw_hub/core/acl/gateway_protocol.dart';
import 'package:claw_hub/core/acl/i_gateway_client.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

ConnectionConfig testConfig() => ConnectionConfig();

/// Records every logXxx call as a map for assertions.
class RecordingApiLogger implements IApiLogger {
  final List<({String method, String requestId, int byteSize})> requests = [];
  final List<({String requestId, bool ok, String? errorCode, int? durationMs})>
      responses = [];
  final List<({String? state, String message})> states = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) {
    requests.add((method: method, requestId: requestId, byteSize: byteSize));
  }

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {
    responses.add(
        (requestId: requestId, ok: ok, errorCode: errorCode, durationMs: null));
  }

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) {
    states.add((state: state, message: message));
  }
}

/// Every logXxx throws — for the “logging must not break the protocol path” contract.
class ThrowingApiLogger implements IApiLogger {
  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) =>
      throw StateError('boom');

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) =>
      throw StateError('boom');

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) =>
      throw StateError('boom');
}

void main() {
  late ControllableWebSocket ws;
  late ConnectionManager cm;
  late RecordingApiLogger logger;

  ConnectionManager buildCm({IApiLogger? apiLogger}) => ConnectionManager(
        instanceId: 'test-instance',
        gatewayUrl: 'ws://localhost:9999/ws',
        token: 'test-token',
        deviceId: 'test-device',
        config: testConfig(),
        webSocketFactory: (uri) => ws.channel,
        apiLogger: apiLogger,
      );

  Future<void> connectToHelloOk(ConnectionManager cm) async {
    // ws is ControllableWebSocket.ready() — channel.ready already resolved,
    // so (unlike the .create() variant) we do NOT call completeHandshake().
    cm.connect();
    await pumpMicrotasks();
    ws.simulateServerFrame(challengeJson());
    await pumpMicrotasks();
    final connectId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame(helloOkJson(connectId));
    await pumpMicrotasks();
  }

  setUp(() {
    ws = ControllableWebSocket.ready();
    logger = RecordingApiLogger();
    cm = buildCm(apiLogger: logger);
  });

  test('sendRequest logs req with threaded method + res with duration', () async {
    await connectToHelloOk(cm);

    final resFuture = cm.sendRequest(Methods.chatHistory, {'sessionKey': 'agent:1:main'});
    await pumpMicrotasks();
    final reqId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame(chatHistoryResponseJson(id: reqId));
    await resFuture;

    expect(logger.requests.any((r) => r.method == Methods.chatHistory), isTrue);
    expect(logger.responses.any((r) => r.requestId == reqId && r.ok), isTrue);
  });

  test('logResponse is called AFTER completer.complete — throwing logger does not stall sendRequest', () async {
    final throwingCm = buildCm(apiLogger: ThrowingApiLogger());
    await connectToHelloOk(throwingCm);

    final resFuture = throwingCm
        .sendRequest(Methods.agentsList, {})
        .timeout(const Duration(seconds: 2));
    await pumpMicrotasks();
    final reqId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame('{"type":"res","id":"$reqId","ok":true,"payload":{}}');
    // Must complete, not time out — proves logResponse (which throws) ran after complete.
    final res = await resFuture;
    expect(res.ok, isTrue);
  });

  test('handshake: connect req logged (method=connect) + hello-ok → state connected', () async {
    await connectToHelloOk(cm);
    expect(logger.requests.any((r) => r.method == Methods.connect), isTrue);
    expect(logger.states.any((s) => s.state == 'connected'), isTrue);
  });

  test('tick timeout → state recovering + "Tick timeout" message', () async {
    await connectToHelloOk(cm);
    // Arm the tick watchdog by simulating a tick, then fire the FakeTimer.
    ws.simulateServerFrame(tickJson);
    await pumpMicrotasks();
    // The tick watchdog timer is the latest timer; fire it to simulate timeout.
    // (ConnectionManager uses Timer.new by default — we can't easily fire it.
    //  Instead, inject a FakeTimerFactory so we control it.)
  }, skip: 'wire FakeTimerFactory variant in follow-up; see note below');

  test('_immediateReconnect (graceful shutdown) → state disconnected logged', () async {
    await connectToHelloOk(cm);
    ws.simulateServerFrame(shutdownJson);
    await pumpMicrotasks();
    await pumpMicrotasks();
    expect(
      logger.states.any((s) => s.state == 'disconnected'),
      isTrue,
    );
  });

  test('buffer overflow → state-null "Buffer overflow" log', () async {
    // hello-ok with tiny maxBufferedBytes so a small request overflows.
    cm.connect();
    await pumpMicrotasks();
    ws.simulateServerFrame(challengeJson());
    await pumpMicrotasks();
    final connectId = extractReqId(ws.sentFrames.last);
    ws.simulateServerFrame(
      '{"type":"res","id":"$connectId","ok":true,'
      '"payload":{"type":"hello-ok","protocol":4,'
      '"policy":{"tickIntervalMs":15000,"maxPayload":26214400,"maxBufferedBytes":50}}}',
    );
    await pumpMicrotasks();

    // A request whose payloadSize > 50 → BufferOverflowException.
    await expectLater(
      cm.sendRequest(Methods.agentsList, {}),
      throwsA(isA<BufferOverflowException>()),
    );
    expect(
      logger.states.any((s) => s.message.contains('Buffer overflow')),
      isTrue,
    );
  });

  test('EventFrame (chat delta) → no log call (filtering)', () async {
    await connectToHelloOk(cm);
    final beforeReq = logger.requests.length;
    final beforeRes = logger.responses.length;
    final beforeState = logger.states.length;
    ws.simulateServerFrame(chatDeltaJson());
    await pumpMicrotasks();
    expect(logger.requests.length, beforeReq);
    expect(logger.responses.length, beforeRes);
    // chat delta may emit a state? No — only _handleEvent routes it; no state log.
    expect(logger.states.length, beforeState);
  });

  test('throwing-logger contract: connect succeeds when every logXxx throws', () async {
    final throwingCm = buildCm(apiLogger: ThrowingApiLogger());
    await connectToHelloOk(throwingCm); // must not throw despite logger throwing
    expect(
      throwingCm.state,
      GatewayConnectionState.connected,
    );
  });
}
```

> **Note on the tick-timeout test (skipped):** `ConnectionManager` defaults to `Timer.new`. To deterministically fire the tick watchdog, construct the CM with `timerFactory: fakeTimerFactory.call` (see `FakeTimerFactory` in `test_helpers.dart`), simulate a tick, then `fakeTimerFactory.fireLast()`. Fill the skipped test body with that variant as a follow-up step if the FakeTimer path is preferred; the non-skipped tests already cover the req/res + lifecycle contracts. Do **not** leave the skip in the final PR without a tracking note — either implement the FakeTimer variant or delete the skipped test with a comment.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/acl/connection_manager_logging_test.dart`
Expected: FAIL — `apiLogger` named param doesn't exist on `ConnectionManager`; `method` param doesn't exist on `sendRawRequest`.

- [ ] **Step 3: Implement — constructor + field + class docstring**

In `lib/core/acl/connection_manager.dart`:

3a. Add import at top:
```dart
import '../i_api_logger.dart';
```

3b. Add a field and constructor param. In the class, near the other `final` fields (after `_deviceTokenStore`):
```dart
  /// API/生命周期日志采集器（spec §5）。纯观察——所有调用点不改控制流。
  /// null = 不采集（如后台 isolate）。
  final IApiLogger? _apiLogger;
```

3c. In the `ConnectionManager({...})` constructor parameter list, add (after `this._deviceTokenStore,`):
```dart
    this.apiLogger,
```
and in the initializer list add `_apiLogger = apiLogger,`. (Add `IApiLogger? apiLogger,` to the constructor params.)

3d. Add a class-level docstring note at the top of the `class ConnectionManager` doc comment:
```dart
/// 日志采集（spec §5）：通过 [_apiLogger] 在 15 个 observation-only 站点采集
/// req/res + 生命周期事件。**每个采集点附 `// observation-only` 注释，禁止
/// 加控制流。** 详见 docs/superpowers/specs/2026-07-07-api-logging-design.md §5.2。
```

- [ ] **Step 4: Implement — req/res choke points (3 sites)**

4a. `sendRawRequest` — add `String? method` param and a log call before the socket write. Change the signature:
```dart
  Future<ResponseFrame> sendRawRequest({
    required String id,
    required String requestJson,
    required int payloadSize,
    String? method, // observation-only — threaded from callers (spec §5.1 #1)
  }) async {
```
Then, immediately before `_channel!.sink.add(requestJson);` inside the `try` block:
```dart
      // observation-only — do not add control flow
      _apiLogger?.logRequest(
        instanceId: _instanceId,
        requestId: id,
        method: method ?? '',
        byteSize: payloadSize,
        rawJson: requestJson,
      );
      _channel!.sink.add(requestJson);
```

4b. `sendRequest` — thread `method` into `sendRawRequest`. In `sendRequest` (the method that calls `sendRawRequest`), change the call:
```dart
    return sendRawRequest(
      id: id,
      requestJson: requestJson,
      payloadSize: payloadSize,
      method: method,
    );
```

4c. `onConnectChallenge` — log the connect req before its socket write. Immediately before `_channel!.sink.add(requestJson);` in `onConnectChallenge`:
```dart
    // observation-only — do not add control flow
    _apiLogger?.logRequest(
      instanceId: _instanceId,
      requestId: id,
      method: Methods.connect,
      byteSize: utf8.encode(requestJson).length,
      rawJson: requestJson,
    );
    _channel!.sink.add(requestJson);
```
(`utf8` is already imported in this file via `dart:convert`.)

4d. `_onIncomingData` — log res AFTER `completer.complete(frame)`. In the `ResponseFrame` case, after `completer.complete(frame);` (which is the last statement of the non-early-return path):
```dart
          completer.complete(frame);
          // observation-only — do not add control flow; AFTER complete so a
          // logging failure can never block response delivery (spec §5.1 #3).
          _apiLogger?.logResponse(
            instanceId: _instanceId,
            requestId: id,
            ok: ok,
            errorCode: frame.error?.code,
            byteSize: raw.length,
            rawJson: raw,
          );
```
(The `EventFrame` case stays unchanged — no logging. This enforces the “no streaming deltas” rule.)

- [ ] **Step 5: Implement — 9 lifecycle sites**

Each is a single `_apiLogger?.logStateChange(...)` line inserted at the anchor. All carry `// observation-only — do not add control flow`.

| # | Method | Anchor (existing line) | Insertion (add immediately after the anchor) |
|---|---|---|---|
| 1 | `_doConnect` | `_setState(GatewayConnectionState.connecting);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'connecting', message: 'Connecting to $_gatewayUrl');` |
| 2 | `_handleConnectResponse` (hello-ok success) | `_setState(GatewayConnectionState.connected);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'connected', message: 'Connected (protocol: ${payload['protocol']}, maxPayload: $_maxPayloadBytes, tick: ${_tickIntervalMs}ms)');` |
| 3 | `_handleAuthFailure` | `_setState(GatewayConnectionState.authFailed);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'authFailed', message: 'Auth failed: $reason${errorCode != null ? ' (code: $errorCode)' : ''}');` |
| 4 | `_handlePairingRequired` | `_setState(GatewayConnectionState.pairingRequired);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'pairingRequired', message: 'Pairing required — waiting for approval');` |
| 5 | `_handleDeviceIdMismatch` | `_setState(GatewayConnectionState.recovering);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'recovering', message: 'Device ID mismatch — transient race, retry 2s');` |
| 6 | `_immediateReconnect` | `_setState(GatewayConnectionState.disconnected);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'disconnected', message: pendingFailReason);` |
| 7 | `_resetTickTimeout` tick-timeout callback | `debugPrint('[CM] Tick timeout for $_instanceId — connection lost');` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'recovering', message: 'Tick timeout — connection lost');` |
| 8 | `_onConnectionError` | `_setState(GatewayConnectionState.recovering);` (the one inside `if (!_state.isTerminal)`) | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'recovering', message: 'WebSocket error: $error');` |
| 9 | `_scheduleReconnect` (exhausted branch) | `_setState(GatewayConnectionState.reconnectExhausted);` | `_apiLogger?.logStateChange(instanceId: _instanceId, state: 'reconnectExhausted', message: 'Reconnect exhausted after $_reconnectAttempt consecutive failures');` |

For `_onConnectionDone`: add a message-only log after the `if (!_intentionalDisconnect && !_state.isTerminal)` block:
```dart
    // observation-only — do not add control flow
    _apiLogger?.logStateChange(
        instanceId: _instanceId, state: _state.name, message: 'WebSocket closed');
```
(`GatewayConnectionState` is an enum; `.name` yields `'recovering'`/`'disconnected'` etc.)

For the 2 diagnostic-event sites in `sendRawRequest` (before each `throw`):

- Before `throw PayloadTooLargeException(...)`:
```dart
      // observation-only — do not add control flow
      _apiLogger?.logStateChange(
          instanceId: _instanceId,
          state: null,
          message: 'Payload too large: $payloadSize > maxPayload $maxPayload');
```
- Before `throw BufferOverflowException(...)`:
```dart
      // observation-only — do not add control flow
      _apiLogger?.logStateChange(
          instanceId: _instanceId,
          state: null,
          message:
              'Buffer overflow: buffered=$_bufferedBytes, attempted=$payloadSize, max=$maxBuffered');
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/core/acl/connection_manager_logging_test.dart`
Expected: PASS (all non-skipped tests). The skipped tick-timeout test remains skipped.

- [ ] **Step 7: Run the full existing ConnectionManager suite to confirm no regression**

Run: `flutter test test/core/acl/`
Expected: PASS — no existing test breaks (the new param is optional, observation-only).

- [ ] **Step 8: Commit**

```bash
git add lib/core/acl/connection_manager.dart test/core/acl/connection_manager_logging_test.dart
git commit -m "feat(api-logging): instrument ConnectionManager with IApiLogger (15 sites)"
```

---

## Task 5: `WsGatewayClient` forwarding + `buildGatewayClient` + DI wiring

**Files:**
- Modify: `lib/core/acl/ws_gateway_client.dart`
- Modify: `lib/app/background_sync/callback_dispatcher.dart`
- Modify: `lib/app/di/providers.dart`
- Modify: `test/core/acl/ws_gateway_client_test.dart`

**Interfaces:**
- Consumes: `IApiLogger` (Task 1), `ApiLogStore` (Task 3).
- Produces: `WsGatewayClient` accepts `IApiLogger? apiLogger` and forwards it to each `ConnectionManager`; `buildGatewayClient` accepts `IApiLogger? apiLogger`; providers expose `apiLogStoreProvider` + `apiLoggerProvider` and wire into `wsGatewayClientProvider`.

- [ ] **Step 1: Write the failing test (forwarding assertion)**

In `test/core/acl/ws_gateway_client_test.dart`, add the import at the top:
```dart
import 'package:claw_hub/core/i_api_logger.dart';
```
Then add a local recording logger (near the other fakes, e.g. after `FakeLogger`) and a test inside `main()`:

```dart
class _RecordingApiLogger implements IApiLogger {
  final List<String> requestMethods = [];
  final List<String> stateNames = [];

  @override
  void logRequest({
    required String instanceId,
    required String requestId,
    required String method,
    required int byteSize,
    required String rawJson,
  }) =>
      requestMethods.add(method);

  @override
  void logResponse({
    required String instanceId,
    required String requestId,
    required bool ok,
    String? errorCode,
    required int byteSize,
    String? rawJson,
  }) {}

  @override
  void logStateChange({
    required String instanceId,
    String? state,
    required String message,
  }) =>
      stateNames.add(state ?? '');
}
```

```dart
  group('apiLogger forwarding', () {
    test('WsGatewayClient forwards apiLogger to ConnectionManager — handshake is logged', () async {
      final logger = _RecordingApiLogger();
      final ws = ControllableWebSocket.ready();
      final client = WsGatewayClient(
        identityProvider: FakeDeviceIdentityProvider(),
        webSocketFactory: (_) => ws.channel,
        apiLogger: logger,
      );

      unawaited(client.connect(testInstance()));
      await pumpMicrotasks();
      ws.simulateServerFrame(challengeJson());
      await pumpMicrotasks();
      final reqId = extractReqId(ws.sentFrames.first);
      ws.simulateServerFrame(helloOkJson(reqId));
      await pumpMicrotasks();

      // The connect handshake req must have been logged (method = connect) and
      // the hello-ok must have produced a 'connected' state log. This proves the
      // logger flowed WsGatewayClient → ConnectionManager → IApiLogger.
      expect(logger.requestMethods, contains(Methods.connect));
      expect(logger.stateNames, contains('connected'));

      await client.dispose();
    });
  });
```

This exercises the full forwarding path through the handshake (no `sendMessage` worker-isolate dependency) and asserts both the `connect` req log and the `connected` state log.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/acl/ws_gateway_client_test.dart`
Expected: FAIL — `apiLogger` ctor param doesn't exist on `WsGatewayClient`.

- [ ] **Step 3: Implement — `WsGatewayClient`**

In `lib/core/acl/ws_gateway_client.dart`:

3a. Add import:
```dart
import '../i_api_logger.dart';
```

3b. Add a field + constructor param (mirror the existing `_logger` pattern). Add field:
```dart
  final IApiLogger? _apiLogger;
```
Add `this.apiLogger,` to the `WsGatewayClient({...})` constructor params and `_apiLogger = apiLogger,` to the initializer. (Param name `IApiLogger? apiLogger`.)

3c. In `connect()`, pass it to the `ConnectionManager` ctor (the `final manager = ConnectionManager(...)` block, ~L195):
```dart
        apiLogger: _apiLogger,
```

3d. In `testConnection()`, pass it to the test `ConnectionManager` ctor (~L447):
```dart
        apiLogger: _apiLogger,
```

3e. In `sendMessage`, pass `method` to `sendRawRequest`:
```dart
      res = await manager.sendRawRequest(
        id: requestId,
        requestJson: outbound.requestJson,
        payloadSize: outbound.payloadSize,
        method: Methods.chatSend,
      );
```

- [ ] **Step 4: Implement — `buildGatewayClient`**

In `lib/app/background_sync/callback_dispatcher.dart`, add the param to `buildGatewayClient` and forward it:

```dart
WsGatewayClient buildGatewayClient({
  required ILogger logger,
  IDeviceIdentityProvider? identityProvider,
  IDeviceTokenStore? deviceTokenStore,
  Future<String?> Function()? modelIdentifierLoader,
  IApiLogger? apiLogger, // NEW — main isolate injects; background passes null
}) {
```
Add the import `import 'package:claw_hub/core/i_api_logger.dart';` at the top.

In the `return WsGatewayClient(...)` call inside `buildGatewayClient`, add:
```dart
    apiLogger: apiLogger,
```

- [ ] **Step 5: Implement — DI wiring**

In `lib/app/di/providers.dart`:

5a. Add imports near the top:
```dart
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';
```

5b. Add the two providers near `loggerProvider` (after it):
```dart
/// API/生命周期日志环形缓冲 — App 生命周期单例（普通 Provider，非 autoDispose）。
/// 同一实例既注入 [WsGatewayClient] 当采集 sink，又供诊断页 provider 读取（SSOT）。
/// spec §6。
final apiLogStoreProvider = Provider<ApiLogStore>(
  (ref) => ApiLogStore(
    maxEntries: ApiLogStore.defaultMaxEntries,
    logger: ref.watch(loggerProvider),
  ),
);

/// 面向 ACL 的日志抽象 —— 指向 [apiLogStoreProvider] 同一实例。
final apiLoggerProvider = Provider<IApiLogger>(
  (ref) => ref.watch(apiLogStoreProvider),
);
```

5c. In `wsGatewayClientProvider`, add `apiLogger` to the `buildGatewayClient(...)` call:
```dart
  final client = buildGatewayClient(
    logger: ref.watch(loggerProvider),
    identityProvider: ref.watch(deviceIdentityProvider),
    deviceTokenStore: ref.watch(deviceTokenStoreProvider),
    modelIdentifierLoader: () => ref.read(deviceModelIdentifierProvider.future),
    apiLogger: ref.watch(apiLoggerProvider),
  );
```

5d. **Do NOT change `callbackDispatcher`'s `buildGatewayClient(...)` call** — it omits `apiLogger`, which defaults to null (no logging in the background isolate). Verify this by grepping `buildGatewayClient` in `callback_dispatcher.dart` and confirming no `apiLogger:` arg is passed there.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/acl/ws_gateway_client_test.dart`
Expected: PASS (including the new forwarding test).

Run: `flutter test test/core/acl/`
Expected: PASS (full ACL suite green).

- [ ] **Step 7: Commit**

```bash
git add lib/core/acl/ws_gateway_client.dart lib/app/background_sync/callback_dispatcher.dart lib/app/di/providers.dart test/core/acl/ws_gateway_client_test.dart
git commit -m "feat(api-logging): wire IApiLogger through WsGatewayClient + DI"
```

---

## Task 6: Diagnostics providers

**Files:**
- Create: `lib/features/diagnostics/providers/diagnostics_providers.dart`
- Test: `test/features/diagnostics/diagnostics_providers_test.dart`

**Interfaces:**
- Consumes: `apiLogStoreProvider` (Task 5), `ApiLogEntry` (Task 1).
- Produces: `diagnosticsEntriesProvider` (StreamProvider<List<ApiLogEntry>>, newest-first, seeded with snapshot); `diagnosticsWarningShownProvider` (FutureProvider<bool>).

- [ ] **Step 1: Write the failing test**

Create `test/features/diagnostics/diagnostics_providers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/features/diagnostics/providers/diagnostics_providers.dart';

void main() {
  test('diagnosticsEntriesProvider seeds with snapshot and emits newest-first', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(apiLogStoreProvider);
    store.logStateChange(instanceId: 'i1', state: 'connected', message: 'first');
    store.logStateChange(instanceId: 'i1', state: 'disconnected', message: 'second');

    final sub = container.listen(diagnosticsEntriesProvider, (_, __) {});
    // First emission = seed snapshot, reversed (newest first)
    final first = await container.read(diagnosticsEntriesProvider.future);
    expect(first.first.message, 'second'); // newest first
    expect(first.last.message, 'first');

    // A new entry triggers a re-emission
    store.logStateChange(instanceId: 'i1', state: 'connected', message: 'third');
    final updated = await container.read(diagnosticsEntriesProvider.future);
    expect(updated.first.message, 'third');

    sub.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/diagnostics/diagnostics_providers_test.dart`
Expected: FAIL — import doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/diagnostics/providers/diagnostics_providers.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';

/// 诊断页条目流（v1 无过滤，spec §7.2）。seed = 当前 snapshot 逆序（最新在最上），
/// 之后每次 store 新增条目重新发逆序列表。O(500) per emission，可接受。
final diagnosticsEntriesProvider = StreamProvider<List<ApiLogEntry>>((ref) {
  final store = ref.watch(apiLogStoreProvider);
  final controller = StreamController<List<ApiLogEntry>>();
  controller.add(store.snapshot().toList().reversed.toList());
  final sub = store.onEntry.listen(
    (_) => controller.add(store.snapshot().toList().reversed.toList()),
  );
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

/// 首次进入诊断页的警告是否已确认（spec §7.1）。SharedPreferences 持久化。
/// 诊断页在确认警告时直接写 SharedPreferences 并 invalidate 本 provider。
final diagnosticsWarningShownProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('diagnostics_warning_shown') ?? false;
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/diagnostics/diagnostics_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/diagnostics/providers/diagnostics_providers.dart test/features/diagnostics/diagnostics_providers_test.dart
git commit -m "feat(api-logging): add diagnostics entries + warning-flag providers"
```

---

## Task 7: Diagnostics page + route + settings entry

**Files:**
- Create: `lib/features/diagnostics/diagnostics_page.dart`
- Modify: `lib/app/router/router.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Test: `test/features/diagnostics/diagnostics_page_test.dart`

**Interfaces:**
- Consumes: `diagnosticsEntriesProvider` + `diagnosticsWarningShownProvider` (Task 6), `apiLogStoreProvider` (Task 5), `AppRoutes` (router).
- Produces: `DiagnosticsPage` widget; route `/claws/settings/diagnostics`; settings 「诊断」 row.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/diagnostics/diagnostics_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/core/api_log_store.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/features/diagnostics/diagnostics_page.dart';

void main() {
  late ApiLogStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({'diagnostics_warning_shown': true});
    store = ApiLogStore();
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        apiLogStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(home: DiagnosticsPage()),
    );
  }

  testWidgets('renders entries from the store (newest first)', (tester) async {
    store.logStateChange(instanceId: 'i1', state: 'connected', message: 'first');
    store.logRequest(
        instanceId: 'i1', requestId: 'r1', method: 'chat.send', byteSize: 10, rawJson: '{}');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('chat.send'), findsOneWidget);
    expect(find.textContaining('first'), findsOneWidget);
  });

  testWidgets('tap a row expands payload preview', (tester) async {
    store.logRequest(
      instanceId: 'i1',
      requestId: 'r1',
      method: 'connect',
      byteSize: 40,
      rawJson: '{"method":"connect","params":{"auth":{"token":"secret"}}}',
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    // Payload collapsed by default — secret not visible.
    expect(find.textContaining('secret'), findsNothing);
    // Tap the row to reveal.
    await tester.tap(find.textContaining('connect'));
    await tester.pumpAndSettle();
    // Redacted preview now visible.
    expect(find.textContaining('<redacted>'), findsOneWidget);
  });

  testWidgets('clear button wipes the list', (tester) async {
    store.logStateChange(instanceId: 'i1', state: 'connected', message: 'hello');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    // Confirm dialog
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('hello'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/diagnostics/diagnostics_page_test.dart`
Expected: FAIL — `DiagnosticsPage` doesn't exist.

- [ ] **Step 3: Write the DiagnosticsPage widget**

Create `lib/features/diagnostics/diagnostics_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/i_api_logger.dart';
import 'package:claw_hub/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 诊断页（spec §7）。v1 扁平逆序列表，payload 默认折叠（tap-to-reveal）。
/// release 可见；首次进入弹一次性警告（SharedPreferences 标志）。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  final Set<String> _expanded = {}; // entry.id → expanded

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWarning());
  }

  Future<void> _maybeShowWarning() async {
    final shown = ref.read(diagnosticsWarningShownProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true, // while loading, don't block
        );
    if (shown || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('诊断页'),
        content: const Text('本页含消息原文与协议细节，请勿在他人旁观看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已了解'),
          ),
        ],
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('diagnostics_warning_shown', true);
    ref.invalidate(diagnosticsWarningShownProvider);
  }

  String _formatTs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}.${(dt.millisecond ~/ 100)}';
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(diagnosticsEntriesProvider);
    final store = ref.watch(apiLogStoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: const Text(
          '诊断',
          style: TextStyle(fontSize: XiaTypography.sectionTitle, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: () => _confirmClear(store),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Text('还没有日志 — 连接 Gateway 并发条消息试试',
                  style: TextStyle(color: XiaColors.text4)),
            );
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => _entryTile(entries[i]),
          );
        },
      ),
    );
  }

  Widget _entryTile(ApiLogEntry e) {
    final expanded = _expanded.contains(e.id);
    final icon = e.direction == ApiLogDirection.outgoing
        ? Icons.north
        : e.direction == ApiLogDirection.incoming
            ? Icons.south
            : Icons.radio_button_unchecked;
    final iconColor = e.direction == ApiLogDirection.outgoing
        ? XiaColors.accent
        : e.direction == ApiLogDirection.incoming
            ? Colors.green
            : XiaColors.text3;
    final title = e.kind == ApiLogKind.state
        ? (e.state ?? 'event')
        : (e.methodOrEvent ?? e.kind.name);
    final sub = <String>[
      _formatTs(e.timestampMs),
      if (e.kind == ApiLogKind.res)
        e.ok == true ? 'ok' : 'ERR:${e.errorCode ?? "?"}'
      else if (e.kind == ApiLogKind.state && e.message != null)
        e.message!
      else if (e.durationMs != null)
        '+${e.durationMs}ms',
      if (e.byteSize != null) '${e.byteSize}B',
    ].join(' · ');

    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: iconColor, size: 18),
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: XiaColors.text4)),
          trailing: e.payloadPreview == null
              ? null
              : Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
          onTap: e.payloadPreview == null
              ? null
              : () => setState(() {
                    if (expanded) {
                      _expanded.remove(e.id);
                    } else {
                      _expanded.add(e.id);
                    }
                  }),
        ),
        if (expanded && e.payloadPreview != null)
          Container(
            width: double.infinity,
            color: XiaColors.surface2,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              e.payloadPreview!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _confirmClear(ApiLogStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('将清除所有已记录的诊断日志，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok == true) store.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/diagnostics/diagnostics_page_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the route**

In `lib/app/router/router.dart`:

5a. Add the import (alphabetical, near the other settings page imports):
```dart
import 'package:claw_hub/features/diagnostics/diagnostics_page.dart';
```

5b. Add the route constant in `AppRoutes` (after `settingsAbout`):
```dart
  static const String settingsDiagnostics = '/claws/settings/diagnostics';
```

5c. Add the sub-route in the settings `routes: [...]` list (after the `about` sub-route):
```dart
                        _settingsSubRoute(
                          'diagnostics',
                          const DiagnosticsPage(),
                        ),
```

- [ ] **Step 6: Add the settings entry**

In `lib/features/settings/settings_page.dart`, add a row in the 「关于」 `SettingsSection` (or a new 「开发者」 section — prefer adding to the existing 「关于」 section to avoid a new section header). After the `版本` row:

```dart
              SettingsRow(
                label: '诊断',
                value: 'API 日志',
                onTap: () => context.push(AppRoutes.settingsDiagnostics),
              ),
```

- [ ] **Step 7: Run the full feature + router tests**

Run: `flutter test test/features/diagnostics/ test/features/settings/settings_page_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/diagnostics/diagnostics_page.dart lib/app/router/router.dart lib/features/settings/settings_page.dart test/features/diagnostics/diagnostics_page_test.dart
git commit -m "feat(api-logging): add diagnostics page, route, settings entry"
```

---

## Task 8: Full-suite verification + perf regression test

**Files:**
- Create: `test/core/api_log_store_perf_test.dart`
- No production code changes.

**Interfaces:**
- Consumes: `ApiLogStore` (Task 3) + `redactAndTruncate` (Task 2).

- [ ] **Step 1: Write the perf regression test**

Create `test/core/api_log_store_perf_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_store.dart';

void main() {
  test('logRequest on a 5MB frame completes in < 5ms (truncate-then-parse holds)', () {
    final store = ApiLogStore();
    addTearDown(store.dispose);

    // 5MB JSON: a chat.send with a huge base64-ish attachment payload.
    final big = '{"method":"chat.send","params":{"message":"hi","attachments":[{"content":"${'A' * 5_000_000}"}]}}';
    final payloadSize = big.length;

    final sw = Stopwatch()..start();
    store.logRequest(
      instanceId: 'i',
      requestId: 'r1',
      method: 'chat.send',
      byteSize: payloadSize,
      rawJson: big,
    );
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(5),
        reason: 'logRequest must stay O(threshold) via truncate-then-parse; '
            'full jsonDecode of a 5MB frame would blow this budget.');
  });
}
```

- [ ] **Step 2: Run the perf test**

Run: `flutter test test/core/api_log_store_perf_test.dart`
Expected: PASS. If it fails (elapsed ≥ 5ms), the redactor regressed to full-parse — re-check Task 2's `largeFrame` branch.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: no new issues in the added/modified files.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests green, including existing ACL/feature suites — no regressions).

- [ ] **Step 5: Run the pre-commit hook check on staged files**

Run: `./scripts/pre-commit --install` (if not already installed), then verify the hook passes on a sample commit. Or manually confirm Law 1/6/8/11 grep checks pass for the new `lib/core/` and `lib/features/diagnostics/` files.

- [ ] **Step 6: Commit**

```bash
git add test/core/api_log_store_perf_test.dart
git commit -m "test(api-logging): perf regression test for truncate-then-parse"
```

---

## Self-Review Notes

- **Spec coverage**: §2 (files/layers) → Tasks 1–7; §3 (entry + redactor) → Tasks 1–2; §4 (store) → Task 3; §5 (CM instrumentation, 15 sites) → Task 4; §5.3 + §6 (forwarding + DI) → Task 5; §7 (UI/providers/route) → Tasks 6–7; §8 (tests) → embedded in each task + Task 8 perf; §9 (constants) → Tasks 2–3; §10 (invariants) → Task 4 throwing-logger + Task 8 perf.
- **Refinements over spec** (called out inline): `ApiLogDirection { outgoing, incoming }` (not `out, in` — `in` reserved); `ApiLogEntry.direction` nullable for state entries; biometric gating replaced with tap-to-reveal + warning (spec commit `59471dd`).
- **Known follow-up**: the tick-timeout test in Task 4 is `skip:`ed — either implement the `FakeTimerFactory` variant or delete with a tracking comment before merge.
