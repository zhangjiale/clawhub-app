import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/features/chat_room/widgets/attachment_sheet.dart';

void main() {
  group('AttachmentSheet', () {
    Future<void> openSheet(
      WidgetTester tester,
      ValueChanged<AttachmentKind> onPick,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => AttachmentSheet.show(context, onPick: onPick),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows three options: 相册 / 拍照 / 文件', (tester) async {
      await openSheet(tester, (_) {});
      expect(find.text('相册'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
    });

    testWidgets('tapping 相册 invokes onPick with gallery kind and pops', (
      tester,
    ) async {
      final picked = <AttachmentKind>[];
      await openSheet(tester, picked.add);

      await tester.tap(find.text('相册'));
      await tester.pumpAndSettle();

      expect(picked, [AttachmentKind.gallery]);
      // sheet 已 pop,选项文本消失
      expect(find.text('相册'), findsNothing);
    });

    testWidgets('tapping 文件 invokes onPick with file kind', (tester) async {
      final picked = <AttachmentKind>[];
      await openSheet(tester, picked.add);

      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();

      expect(picked, [AttachmentKind.file]);
    });
  });
}
