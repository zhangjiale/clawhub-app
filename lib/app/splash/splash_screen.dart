import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// mascot logo 资产路径（透明 PNG = `xiahub-icon-v6` 字节）。
/// 集中常量避免 [StartupGate] 的 `precacheImage` 与 [SplashScreen] 的
/// `Image.asset` 漂移到不同资产（precache 暖一张、渲染另一张 = 首帧 jank，
/// 正是 precache 要防的）。
///
/// 资源约束：v6 透明 PNG（1024×1024 RGBA），但右下角带"豆包AI生成"水印。
/// 已知限制：用户已接受可见水印作为临时方案；后续干净抠图版替换为单独 PR。
/// 此处不要"自动换图"：splash 资源必须经设计 review 才能动。
const String kSplashImagePath = 'docs/design/assets/xiahub-logo.png';

/// 开屏页面。
///
/// 渲染在 `MaterialApp.router` 之外（由 `StartupGate` 在 splash 阶段挂载），
/// 自带 `Material` + `Directionality` 兜底，避免 Icon/Text 默认样式泄漏。
///
/// 元素：
/// - 纯色背景 `XiaColors.bg`（#08090D = native splash 纯色 = 零背景跳变）
/// - 居中圆形 mascot logo（ClipOval 320dp × 320dp）
/// - mascot 下方"虾Hub"品牌名（XiaColors.text1, w600, 20px）—— native splash
///   阶段不显示 logo，Flutter splash 是冷启动唯一带 logo + 品牌名的页面
/// - 底部居中版本号（XiaColors.text3 弱化）
/// - 200ms `TweenAnimationBuilder` 淡入让 native → Flutter handoff 更顺滑
///
/// 跨层零重复 logo 原理（plan 2026-07-09 rev4）：
/// - pre-v31 native splash: `windowBackground=@color/splash_bg` 纯色，无 logo
/// - Android 12+ native splash: `windowSplashScreenAnimatedIcon` 指向透明
///   drawable，windowSplashScreenBackground 纯色，无 logo
/// - Flutter SplashScreen: 唯一显示 mascot + "虾Hub" + version 的页面
///
/// 历史方案回溯（已废弃）：
/// - rev1: 三层都显示 logo → "两次虾" 重复感
/// - rev2: 三层统一圆形 v6 + 200ms 淡入掩盖 → OEM 虾尾裁切
/// - rev3: InsetDrawable 给 native 加 24dp padding → 虾尾修复，但仍有
///   "两次虾"重复感
/// - rev4 (当前): native 不显示 logo，Flutter 唯一渲染
///
/// 已知 OPPO/ColorOS gotcha：
/// - ColorOS 自有 splash 系统可能覆盖 AOSP SplashScreen API
/// - 部分 ColorOS 版本用 launcher icon 而非 windowSplashScreenAnimatedIcon
/// - viewport 在不同 ColorOS 版本波动（240-320dp）
///
/// 终极方案（不在本次 scope）：用 platform channel 让 Flutter runtime 读
/// Android 实际 `dimen.starting_window_icon_size`，动态同步 ClipOval 大小，
/// 严格匹配任何设备。
///
/// 首帧 decode 防御由 `StartupGate` 在 `initState` 的 postFrameCallback
/// 里调 `precacheImage` 完成 -- 本 widget 不做首帧 decode 处理。
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: XiaColors.bg, // 纯色背景 = native splash 色，handoff 零背景跳变
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 圆形 v6 mascot 320dp + "虾Hub" 品牌名纵向堆叠在屏中央。native splash
            // 阶段无 logo，Flutter splash 是冷启动唯一带 logo 的页面
            // = 跨层零重复 logo。ClipOval 把方形 PNG 裁成圆形。
            // 200ms TweenAnimationBuilder 让整组（mascot + 品牌名）一起淡入，
            // native → Flutter handoff 更顺滑。
            // BoxFit.contain 保证完整不裁剪 logo 内部细节。
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 320,
                        height: 320,
                        child: Image.asset(
                          kSplashImagePath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: XiaSpacing.s4,
                    ), // 16dp mascot→brand gap
                    const Text(
                      '虾Hub',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: XiaColors.text1,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: XiaSpacing.s8, // V2: 32px
              child: Center(
                child: Text(
                  version,
                  style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
                    color: XiaColors.text3, // 30% alpha -- V2 弱化文案
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
