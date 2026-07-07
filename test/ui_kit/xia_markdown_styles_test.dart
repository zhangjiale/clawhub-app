import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/ui_kit/xia_markdown_styles.dart';

void main() {
  group('XiaMarkdownStyles table rendering', () {
    // 宽表格:列多 + 长表头,确保触发横向滚动分支。
    const tableMarkdown = '''
| 字段名 | 类型 | 是否必填 | 默认值 | 说明 |
|---|---|---|---|---|
| clientId | string | 是 | — | 本地 UUID 用于去重 |
| serverId | string | 否 | null | Gateway 分配的全局去重 ID |
| logicalClock | int | 是 | 0 | 同时间戳消息的排序依据 |
''';

    Widget pumpTable(double width) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MarkdownBody(
              data: tableMarkdown,
              selectable: true,
              styleSheet: XiaMarkdownStyles.message,
            ),
          ),
        ),
      );
    }

    testWidgets('table is wrapped in Scrollbar + horizontal scroll view', (
      tester,
    ) async {
      await tester.pumpWidget(pumpTable(300));

      // selectable + 横向滚动不应抛异常(待验证风险)。
      expect(tester.takeException(), isNull);

      // IntrinsicColumnWidth → flutter_markdown 原生包裹
      // Scrollbar > SingleChildScrollView(horizontal) > Table。
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
    });

    testWidgets('table scrollbar thumb is always visible', (tester) async {
      await tester.pumpWidget(pumpTable(300));
      expect(tester.takeException(), isNull);

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.thumbVisibility, isTrue);
    });

    test(
      'message stylesheet uses IntrinsicColumnWidth + visible scrollbar',
      () {
        expect(
          XiaMarkdownStyles.message.tableColumnWidth,
          isA<IntrinsicColumnWidth>(),
        );
        expect(XiaMarkdownStyles.message.tableScrollbarThumbVisibility, isTrue);
      },
    );

    test('streaming stylesheet mirrors table settings', () {
      expect(
        XiaMarkdownStyles.streaming.tableColumnWidth,
        isA<IntrinsicColumnWidth>(),
      );
      expect(XiaMarkdownStyles.streaming.tableScrollbarThumbVisibility, isTrue);
    });
  });
}
