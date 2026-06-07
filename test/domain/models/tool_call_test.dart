import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/tool_call.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('ToolCall', () {
    test('创建待执行的工具调用', () {
      final tc = ToolCall(
        id: 'tc-001',
        messageId: 'msg-001',
        toolName: '数据查询',
      );

      expect(tc.id, 'tc-001');
      expect(tc.messageId, 'msg-001');
      expect(tc.toolName, '数据查询');
      expect(tc.status, ToolCallStatus.pending);
      expect(tc.inputArgs, isNull);
      expect(tc.outputResult, isNull);
      expect(tc.startedAt, isNull);
      expect(tc.endedAt, isNull);
    });

    test('开始执行', () {
      final tc = ToolCall(
        id: 'tc-002',
        messageId: 'msg-002',
        toolName: '代码生成器',
      );

      final running = tc.start();
      expect(running.status, ToolCallStatus.running);
      expect(running.startedAt, isNotNull);
    });

    test('执行成功', () {
      final tc = ToolCall(
        id: 'tc-003',
        messageId: 'msg-003',
        toolName: '代码生成器',
        status: ToolCallStatus.running,
        startedAt: 1717766400000,
      );

      final success = tc.complete(
        success: true,
        output: '{"result": "ok"}',
      );

      expect(success.status, ToolCallStatus.success);
      expect(success.outputResult, '{"result": "ok"}');
      expect(success.endedAt, isNotNull);
    });

    test('执行失败', () {
      final tc = ToolCall(
        id: 'tc-004',
        messageId: 'msg-004',
        toolName: '文件读取',
        status: ToolCallStatus.running,
        startedAt: 1717766400000,
      );

      final failed = tc.complete(
        success: false,
        output: '{"error": "file not found"}',
      );

      expect(failed.status, ToolCallStatus.failed);
      expect(failed.outputResult, '{"error": "file not found"}');
    });

    test('非 RUNNING 状态不能 complete', () {
      final tc = ToolCall(
        id: 'tc-005',
        messageId: 'msg-005',
        toolName: '测试工具',
      );

      expect(
        () => tc.complete(success: true),
        throwsA(isA<StateError>()),
      );
    });

    test('isRunning 判断', () {
      final pending = ToolCall(id: 't1', messageId: 'm1', toolName: '工具1');
      final running = pending.start();
      final completed = running.complete(success: true);

      expect(pending.isRunning, isFalse);
      expect(running.isRunning, isTrue);
      expect(completed.isRunning, isFalse);
    });
  });
}
