import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// 全屏开屏页面。
///
/// 渲染在 `MaterialApp.router` 之外（由 `StartupGate` 在 splash 阶段挂载），
/// 自带 `Material` + `Directionality` 兜底，避免 Icon/Text 默认样式泄漏。
///
/// 元素：
/// - 全屏背景图 `docs/design/assets/xiahub-splash-v3.png`（与平台开屏共用）
/// - 底部居中版本号（`XiaColors.text3` 弱化）
///
/// 首帧 decode 防御由 `StartupGate` 在 `initState` 的 postFrameCallback
/// 里调 `precacheImage` 完成 —— 本 widget 不做首帧 decode 处理。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: XiaColors.bg, // 背景图加载未完成时显示深色兜底
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'docs/design/assets/xiahub-splash-v3.png',
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: XiaSpacing.s8, // V2: 32px
              child: Center(
                child: Text(
                  version,
                  style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
                    color: XiaColors.text3, // 30% alpha —— V2 弱化文案
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
