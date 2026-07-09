import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/app/splash/splash_screen.dart';
import 'package:claw_hub/app/theme/tokens.dart';

void main() {
  testWidgets('renders mascot logo asset', (tester) async {
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName,
      'docs/design/assets/xiahub-logo.png',
    );
  });

  testWidgets(
    'centers mascot logo at fixed 320dp (covers OPPO ColorOS 16 viewport)',
    (tester) async {
      // mascot 必须居中：native 阶段无 mascot，Flutter 第一帧 mascot 在屏中央
      // 出现 = 唯一视觉变化。Center widget 是跨层零跳变方案的结构保证。
      await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
      expect(
        find.ancestor(of: find.byType(Image), matching: find.byType(Center)),
        findsOneWidget,
      );
      // 圆形 320dp — 覆盖 OPPO ColorOS 16 splash icon viewport 常见值。
      // 标准 AOSP 240dp vs Flutter 320dp = +33%，由 200ms TweenAnimationBuilder
      // 淡入掩盖感知。严格匹配特定设备 viewport 需要 runtime 读
      // dimen.starting_window_icon_size（platform channel，超出本次 splash scope）。
      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(of: find.byType(Image), matching: find.byType(SizedBox)),
      );
      expect(sizedBox.width, 320);
      expect(sizedBox.height, 320);
    },
  );

  testWidgets('clips mascot to circle (matches Android 12+ system mask)', (
    tester,
  ) async {
    // ClipOval 把方形 PNG 裁成圆形，与 Android 12+ 系统 splash mask 形状
    // 一致 → handoff 零形状跳变。
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.byType(ClipOval), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(Image), matching: find.byType(ClipOval)),
      findsOneWidget,
    );
  });

  testWidgets('fades mascot in over 200ms (native handoff smoothing)', (
    tester,
  ) async {
    // 200ms TweenAnimationBuilder 淡入让 native → Flutter handoff 更顺滑，
    // 掩盖 pre-v31 方形 → 圆形 的边缘微跳变。
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    final tween = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(tween.duration, const Duration(milliseconds: 200));
  });

  testWidgets('renders version text at bottom center', (tester) async {
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.text('v0.1.0+1'), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.text('v0.1.0+1'),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.bottom, XiaSpacing.s8);
  });

  testWidgets('renders brand text "虾Hub" below mascot', (tester) async {
    // rev4 改动：native splash 不再带 logo，Flutter SplashScreen 是冷启动
    // 唯一渲染品牌名 + logo 的页面。"虾Hub" 文字必须存在 + 在 mascot
    // 下方 (Column 顺序：ClipOval 在前，Text 在后) + 与 mascot 同一个
    // TweenAnimationBuilder 内（一起淡入）。
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    expect(find.text('虾Hub'), findsOneWidget);

    // brand Text 必须在 mascot 下方（即 Column 内 ClipOval 之后）。
    // 通过 Y 坐标验证：brand Text 的 centerY > mascot ClipOval 的 centerY。
    final brandCenter = tester.getCenter(find.text('虾Hub'));
    final mascotCenter = tester.getCenter(find.byType(ClipOval));
    expect(
      brandCenter.dy,
      greaterThan(mascotCenter.dy),
      reason: '品牌名应在 mascot 下方',
    );

    // brand Text 与 mascot 在同一个 TweenAnimationBuilder 内（一起淡入）。
    expect(
      find.ancestor(
        of: find.text('虾Hub'),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byType(ClipOval),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsOneWidget,
    );
  });

  testWidgets('brand text + mascot + version are vertically stacked', (
    tester,
  ) async {
    // rev4 视觉布局验证：brand 在 mascot 下、version 在最底。
    // 三者按 Y 坐标严格升序：mascot < brand < version。
    await tester.pumpWidget(const SplashScreen(version: 'v0.1.0+1'));
    final mascotY = tester.getCenter(find.byType(ClipOval)).dy;
    final brandY = tester.getCenter(find.text('虾Hub')).dy;
    final versionY = tester.getCenter(find.text('v0.1.0+1')).dy;
    expect(brandY, greaterThan(mascotY));
    expect(versionY, greaterThan(brandY));
  });
}
