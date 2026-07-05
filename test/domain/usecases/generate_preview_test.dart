import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/usecases/generate_preview.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('GeneratePreview', () {
    late GeneratePreview useCase;

    setUp(() {
      useCase = GeneratePreview();
    });

    test('用户文本消息 + "你: " 前缀', () {
      final preview = useCase.execute(
        role: MessageRole.user,
        type: MessageType.text,
        content: '帮我分析一下这个需求的优先级',
      );
      expect(preview, '你: 帮我分析一下这个需求的优先级');
    });

    test('Agent 文本消息不加前缀', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.text,
        content: '好的，我来帮你分析...',
      );
      expect(preview, '好的，我来帮你分析...');
    });

    test('超长文本截断到40字', () {
      final longText = '这是一条非常非常长的消息用于测试消息预览生成引擎的截断功能确保不会超过四十个字符的限制';
      final preview = useCase.execute(
        role: MessageRole.user,
        type: MessageType.text,
        content: longText,
      );
      expect(preview.length, lessThanOrEqualTo(43)); // "你: " (3) + 40 chars
      expect(preview.startsWith('你: '), isTrue);
    });

    test('图片消息显示 [图片]', () {
      final preview = useCase.execute(
        role: MessageRole.user,
        type: MessageType.image,
        content: '/path/to/image.png',
      );
      expect(preview, '你: [图片]');
    });

    test('文件消息显示 [文件]', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.file,
        content: '/path/to/report.pdf',
      );
      expect(preview, '[文件]');
    });

    test('工具调用消息显示 [工具调用]', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.toolCall,
        content: '正在执行数据查询...',
      );
      expect(preview, '[工具调用]');
    });

    test('Markdown 标记在预览中被移除', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.text,
        content: '**加粗文本** 和 `代码` [链接](url)',
      );
      expect(preview, contains('加粗文本'));
      expect(preview, contains('代码'));
      expect(preview, contains('链接'));
      expect(preview, isNot(contains('**')));
      expect(preview, isNot(contains('`')));
      expect(preview, isNot(contains('[')));
    });

    test('空文本消息保留用户前缀', () {
      final preview = useCase.execute(
        role: MessageRole.user,
        type: MessageType.text,
        content: '',
      );
      expect(preview, '你: ');
    });

    test('null 文本内容返回空字符串', () {
      final preview = useCase.execute(
        role: MessageRole.system,
        type: MessageType.text,
        content: null,
      );
      expect(preview, '');
    });

    test('空图片内容按类型返回占位（用户）', () {
      final preview = useCase.execute(
        role: MessageRole.user,
        type: MessageType.image,
        content: '',
      );
      expect(preview, '你: [图片]');
    });

    test('空图片内容按类型返回占位（Agent）', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.image,
        content: null,
      );
      expect(preview, '[图片]');
    });

    test('空文件内容按类型返回占位（Agent）', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.file,
        content: '',
      );
      expect(preview, '[文件]');
    });

    test('空工具调用内容按类型返回占位', () {
      final preview = useCase.execute(
        role: MessageRole.agent,
        type: MessageType.toolCall,
        content: null,
      );
      expect(preview, '[工具调用]');
    });
  });
}
