import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';
import 'package:claw_hub/features/instance_manager/widgets/gateway_change_dialog.dart';

void main() {
  testWidgets('显示本地 agent 数量', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  GatewayChangeDialog.show(context, localAgentCount: 5),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 个 Agent'), findsOneWidget);
    expect(find.text('Gateway 地址已变更'), findsOneWidget);
  });

  testWidgets('"取消"按钮关闭弹窗并返回 null', (tester) async {
    GatewayChangeResolution? result =
        GatewayChangeResolution.keepLocal; // sentinel
    bool resolved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await GatewayChangeDialog.show(
                  context,
                  localAgentCount: 1,
                );
                resolved = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result, isNull);
  });

  testWidgets('"保留旧数据"按钮返回 keepLocal', (tester) async {
    GatewayChangeResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await GatewayChangeDialog.show(
                  context,
                  localAgentCount: 1,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留旧数据'));
    await tester.pumpAndSettle();

    expect(result, GatewayChangeResolution.keepLocal);
  });

  testWidgets('"清除并切换"按钮返回 purgeLocal', (tester) async {
    GatewayChangeResolution? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await GatewayChangeDialog.show(
                  context,
                  localAgentCount: 1,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除并切换'));
    await tester.pumpAndSettle();

    expect(result, GatewayChangeResolution.purgeLocal);
  });
}
