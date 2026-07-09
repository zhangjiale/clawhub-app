# 计划：启动页跨层零跳变（拆资产 + mascot Flutter-only）

- **日期**：2026-07-08
- **类型**：实施计划（基于已确认的根因分析）
- **关联 spec**：`docs/superpowers/specs/2026-07-07-splash-page-design.md`（v2）
- **关联 plan**：`docs/superpowers/plans/2026-07-07-splash-page.md`（首版实施，已落地）
- **根因**：见本会话 systematic-debugging Phase 1-2 结论

---

## 0. 背景与根因（一句话）

启动时"小页面->大页面"跳变 = 4 层 splash（Android legacy / Android 12+ / iOS / Flutter）渲染同一张全屏合成海报 `xiahub-splash-v3.png`（1024×1792），但**缩放方式互相矛盾**：native 用 `center`（固定 256dp 居中，小图）、Flutter 用 `BoxFit.cover`/`contain`（满屏，大图）。native 移除的瞬间 Flutter 第一帧接管，图从小变大 = 跳变。

**海报背景非纯色**（mascot-锚定的暖色径向 glow，边缘 `#1a1410`≠`#08090D`），所以 letterbox（contain）会有 glow 截断 seam；cover 会让 mascot 随屏幕宽高比位置漂移；fill 会变形。**跨平台不存在单一缩放方式能同时满足"同图+同位置+同尺寸+同背景"四个无缝条件。**

---

## 1. 方案核心思想

**放弃"单张合成海报"模型，改为"纯色背景 + mascot"分层模型：**

- **native 阶段**（Android legacy / Android 12+ / iOS）：只显示纯色 `#08090D` 背景，**不含 mascot、不含文字**。
- **Flutter 第一帧**（`SplashScreen`）：在屏中央画出 mascot（透明 PNG logo），同一帧/下一帧淡入。
- **handoff**：native 移除时背景色 = `#08090D` = Flutter `Material(color: XiaColors.bg)` 兜底色 = mascot 透明 PNG 的透明区。**native->Flutter 唯一视觉变化 = mascot 出现**，零尺寸/位置/背景跳变。

mascot 只在 Flutter 显示，跨平台同尺寸/同位置的硬约束被绕开（Flutter 单层自由控制）。native 纯色铺满所有平台都支持（`fill`/`cover`/纯色 drawable 无差异）。

### 用户已确认的决策

| 决策点 | 选定 | 来源 |
|---|---|---|
| 修复方向 | native 全对齐 cover（已试，Android 12+ 受 icon 槽限制不完美）→ 改为 Option C 居中 → 再升级为完美方案 | 本会话 |
| native 阶段 mascot 处理 | **纯色背景**（mascot 只在 Flutter 显示） | AskUserQuestion 答复 |

---

## 2. 为什么这是"完美"解（诚实论证）

### 2.1 满足全部 5 个无缝条件

| 条件 | 如何满足 |
|---|---|
| ① 同图 | native 无图（纯色），Flutter 显示 mascot。两侧"图"不同，但 native 的"无图"=纯色 = Flutter mascot 周围的背景，视觉等价 |
| ② 同位置 | mascot 只在 Flutter 一层，位置唯一，无"跨层对齐"问题 |
| ③ 同尺寸 | 同上，单层无尺寸矛盾 |
| ④ 同背景 | native 纯色 `#08090D` = Flutter `XiaColors.bg` = mascot PNG 透明区。海报的暖色 glow **被完全丢弃**（不再用海报背景），无 seam |
| ⑤ 同时长 | `precacheImage` 已解决（`startup_gate.dart:43`），第一帧 mascot decode 完成就绪 |

### 2.2 代价（诚实列出）

- **冷启动 pre-runApp 窗口（~200-500ms）是纯深色屏，无品牌 mascot**。用户看到的是 `#08090D` 深色屏 -> mascot 淡入 -> 主页。品牌露出推迟到 Flutter 接管后。
  - 缓解：`precacheImage` 把 mascot decode 提前到 `initState` postFrame，与 init 并行，mascot 出现延迟 ≤ Flutter 第一帧时间（通常 <100ms）。
  - 这是用"pre-runApp 无 logo"换"零跳变"。用户已确认接受。
- **海报的"虾Hub"文字 + tagline 不再出现在 splash**。mascot 单独成为品牌元素。
  - 备选：文字可烘焙进一张 Flutter 层的合成图（mascot+文字），但会重新引入跨层问题（见 §2.3）。本 plan 默认 mascot-only，文字交给 app 主页 header。
- **需要一张透明背景的 mascot PNG**（`xiahub-logo.png`），项目目前只有白底 `xiahub-icon-v4.png`，需抠图或重新导出（见 §3.1）。

### 2.3 为什么不把文字也放进来（被否决的备选）

若 Flutter 层显示"mascot + 烘焙文字"合成图，native 阶段要显示同样的文字才能无缝 -> 回到"跨平台同尺寸同位置文字"硬约束。**文字一旦跨层，宽高比漂移问题复发**。所以文字不进 splash，mascot 单独承担品牌。这是架构上的有意取舍。

### 2.4 Android 12+ 的特殊处理

Android 12+ SplashScreen API **结构性强制 icon-based**（圆形遮罩 + ≤240dp）。三个选项：

| 选项 | 结果 | 采纳 |
|---|---|---|
| 不设 `android_12.image`，回退 launcher icon | 显示 adaptive icon foreground（圆形遮罩），与 Flutter mascot 不同图、不同尺寸 -> 小跳变 | ❌ |
| `android_12.image` = 透明 mascot | 圆形遮罩裁剪 mascot，与 Flutter 完整 mascot 不同 -> 跳变 | ❌ |
| **不设 `android_12.image` + `android_12.color=#08090D`，纯色** | Android 12+ native 阶段也是纯色（与其他平台一致），mascot 仍只 Flutter 显示 | ✅ |

选第三项：Android 12+ 也走纯色，与 Android legacy / iOS 完全统一。**这是关键**--Android 12+ 不再是特例，4 层全部纯色 native + Flutter mascot，跨平台行为一致。

> 注：Android 12+ 不设 `windowSplashScreenAnimatedIcon` 时系统会回退 launcher icon（`flutter_native_splash` 源码 `android.dart:113` 注释确认）。要真正做到纯色无 icon，需在 `styles-v31` 手动移除该属性并在 activity 用 `postSplashScreenTheme` 抑制，或接受"极短暂的 launcher icon 圆形闪现 -> 纯色"。本 plan 采用**接受 launcher icon 短暂闪现**的折中（Android 12+ 用户看到：圆形 launcher icon ~100ms -> 纯色 -> Flutter mascot），详见 §5 风险。

---

## 3. 资产准备

### 3.1 透明 mascot PNG

**文件**：`docs/design/assets/xiahub-logo.png`（新增）

**来源**：从 `xiahub-icon-v4.png`（白底、mascot 居中带 padding）抠图去白底，或从设计源重新导出。项目无 SVG/Figma 源（已确认 `docs/design/assets/` 只有 PNG），故**抠图是唯一路径**。

**规格**：
- 尺寸：1024×1024（方形，与 icon 一致；mascot 居中）
- 通道：RGBA，背景全透明（alpha=0）
- 内容：mascot only（不含"虾Hub"文字、不含 tagline）
- 抠图需保留 mascot 的 soft glow aura（半透明边缘），不能硬切

**执行**：用户/设计侧完成（AI 不直接改 PNG 二进制）。交付物：透明 PNG 放入 `docs/design/assets/xiahub-logo.png`。**这是本 plan 的唯一外部依赖**。

**降级**：若抠图质量不达标，备选"用 `xiahub-icon-v4.png` 原样 + 在 Flutter 用 `ColorFiltered` 去白底"--但 `ColorFiltered` 去白底效果差（mascot 边缘有白边残留），不推荐。抠图是正路。

### 3.2 资产路径决策（保留 docs/design/assets/ carve-out）

沿用 spec §8 deferred 的"docs/design/assets/ 作为品牌资产 carve-out"，不迁移到 `assets/splash/`。新增 `xiahub-logo.png` 放同目录。`pubspec.yaml` 的 `flutter.assets` 块加该文件。

---

## 4. 实施步骤

### Step 1: 准备透明 mascot 资产（外部依赖）

- [ ] 用户/设计侧从 `xiahub-icon-v4.png` 抠图，产出 `docs/design/assets/xiahub-logo.png`（1024×1024 RGBA 透明背景）
- [ ] 视觉验证：mascot 居中、glow aura 保留、无白边

**阻塞**：后续所有 step 依赖此资产。若用户暂无法抠图，可先用 `xiahub-icon-v4.png` 占位跑通管线，视觉验证后再换正式透明版。

### Step 2: 修改 `pubspec.yaml` native splash 配置

目标：所有 native 层纯色 `#08090D`，无图。

```yaml
flutter_native_splash:
  color: "#08090D"
  color_dark: "#08090D"
  # 移除 image：native 阶段不再显示海报/mascot，纯色铺满。
  # mascot 交给 Flutter SplashScreen 层（见 splash_screen.dart 改动）。
  # image: "docs/design/assets/xiahub-splash-v3.png"  # 已移除

  android_12:
    color: "#08090D"
    # 不设 image/icon_background_color：纯色，回退 launcher icon（Android 12 结构性，
    # 见 plan §2.4）。接受 ~100ms 圆形 icon 闪现 -> 纯色 -> Flutter mascot。

  ios_content_mode: scaleAspectFill  # 纯色下 contentMode 无视觉影响，保持 scaleAspectFill 避免任何 letterbox
  fullscreen: true

  android: true
  ios: true
  web: false
  # 移除 android_gravity：无 image 时此字段无效（插件 showImage=false 不写 splash item）。
  # android_gravity: center  # 已移除
```

**同时**：`flutter.assets` 块加 `- docs/design/assets/xiahub-logo.png`（Flutter `Image.asset` 引用需此条目）。`xiahub-splash-v3.png` 条目可保留（无害）或移除（不再被引用）--本 plan 选择**移除**，避免混淆。

### Step 3: 重新生成 native splash

```bash
dart run flutter_native_splash:create
```

验证生成结果：
- `launch_background.xml`（4 变体）：只剩 `<bitmap gravity="fill" src="@drawable/background"/>`，无 splash item（`showImage=false`）
- `values-v31/styles.xml`：`windowSplashScreenBackground=#08090D`，无 `windowSplashScreenAnimatedIcon`/`IconBackgroundColor`
- `LaunchScreen.storyboard`：imageView 仍存在但 `LaunchImage` 是 1×1 透明占位（插件 `imagePath=null` 时生成 1×1），视觉上只有 `LaunchBackground` 纯色
- `splash.png` / `android12splash.png`：应被删除（无 image 源）

### Step 4: 修改 Flutter `SplashScreen`（`lib/app/splash/splash_screen.dart`）

从"全屏海报 cover/contain"改为"纯色背景 + 居中 mascot logo"。

```dart
const String kSplashImagePath = 'docs/design/assets/xiahub-logo.png';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.canvas,
      color: XiaColors.bg,  // #08090D = native splash 纯色 = 零背景跳变
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // mascot 居中。BoxFit.contain 保证完整显示不裁剪。
            // 尺寸由 mascot PNG intrinsic 决定，受 Stack 约束居中。
            // native 阶段无 mascot -> Flutter 第一帧 mascot 出现 = 唯一变化。
            Center(
              child: Image.asset(
                kSplashImagePath,
                fit: BoxFit.contain,
                // 可选：限制最大尺寸避免在大屏上 mascot 过大。
                // 暂不限制，视觉验证后调整。
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: XiaSpacing.s8,
              child: Center(
                child: Text(
                  version,
                  style: AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
                    color: XiaColors.text3,
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
```

**关键变化**：
- `Image.asset` 从全屏 `BoxFit.cover`/`contain`（海报）-> `Center` + `BoxFit.contain`（mascot logo）
- 背景从海报图 -> `XiaColors.bg` 纯色（Material 兜底）
- mascot 尺寸：暂用 intrinsic（受 `Center` 约束居中，不强制 dp）。视觉验证后若过大可加 `ConstrainedBox(maxWidth: 200dp)`。

### Step 5: 更新测试（`test/app/splash/splash_screen_test.dart`）

现有测试断言"渲染品牌图 + 版本号"。改动后：
- `find.byType(Image)` 仍 findsOneWidget（mascot PNG）
- assetName 从 `xiahub-splash-v3.png` -> `xiahub-logo.png`
- 版本号测试不变

更新断言匹配新资产路径。Law 14（≥2 tests）保持。

### Step 6: 视觉验证（真机，不进 CI）

- [ ] Android <12 冷启动：纯深色屏 -> mascot 居中淡入 -> 主页。**无尺寸跳变**
- [ ] Android 12+ 冷启动：~100ms launcher icon（圆形）-> 纯深色 -> mascot -> 主页。icon->mascot 仍有小过渡（结构性，§2.4）
- [ ] iOS 冷启动：纯深色 -> mascot -> 主页。**无跳变**
- [ ] mascot 尺寸合适（不过大/过小）
- [ ] 版本号仍显示在底部
- [ ] 连续冷启动 5 次，行为一致

### Step 7: 更新 spec & 文档

- `docs/superpowers/specs/2026-07-07-splash-page-design.md`：加 §10 修订记录，说明 v3 改动（单张海报 -> 纯色+mascot 分层）及理由
- `CLAUDE.md` 的 splash 相关描述若需同步则更新

### Step 8: 提交（Conventional Commits）

```
fix(splash): cross-layer zero-jump via mascot-Flutter-only + solid native bg

Root cause: 4 splash layers rendered the same poster with conflicting
scales (native center=small, Flutter cover=large) -> size pop at handoff.
Poster bg is non-solid (mascot-anchored warm glow) so letterbox/crop/fill
all leak seams.

Fix: native (Android legacy/12+/iOS) all render solid #08090D, no image.
mascot rendered only by Flutter SplashScreen (Center + BoxFit.contain).
native->Flutter only visual change = mascot appears, zero size/pos/bg jump.

- pubspec: remove flutter_native_splash.image, drop android_12.image,
  add xiahub-logo.png to flutter.assets
- splash_screen.dart: cover poster -> Center mascot logo on XiaColors.bg
- regenerate native splash (dart run flutter_native_splash:create)
- update splash_screen_test asset assertion
```

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 透明 mascot 抠图质量差（白边/锯齿） | mascot 边缘难看 | 用专业抠图工具（rembg/photoshop）；视觉验证不通过则重新抠。阻塞 Step 4-6 |
| Android 12+ launcher icon 闪现（~100ms） | 极短过渡，非完全无缝 | 结构性限制（§2.4）。若不可接受，需在 activity 加 `setTheme(postSplashScreenTheme)` + Custom SplashScreen 抑制 launcher icon--代价大，本 plan 不做，列为 future work |
| mascot intrinsic 尺寸过大（大屏上撑满） | mascot 过大不协调 | Step 4 可选加 `ConstrainedBox(maxWidth: 240dp)`，视觉验证后定 |
| pre-runApp 纯黑屏被误判为"卡死" | 用户感知差 | pre-runApp 窗口 ~200-500ms，远短于原 splash 800ms 最短展示。且 Flutter 接管后 mascot 即出现，不会真的卡死 |
| 移除 `xiahub-splash-v3.png` 的 assets 条目后其他代码引用断裂 | 编译错误 | grep 确认无其他引用（spec §3.1 已知只有 SplashScreen 引用） |
| `flutter_native_splash` 不设 image 时 iOS storyboard 行为 | 可能残留 1×1 占位 imageView | Step 3 验证 storyboard 只剩 LaunchBackground 纯色，LaunchImage 占位不可见 |

---

## 6. 与首版 plan 的差异

| 维度 | 首版（2026-07-07） | 本版（2026-07-08） |
|---|---|---|
| native splash 内容 | 海报（center，小图） | 纯色 `#08090D`（无图） |
| Flutter splash 内容 | 全屏海报 cover | 居中 mascot logo（透明 PNG） |
| 资产 | 单张 `xiahub-splash-v3.png` | 新增 `xiahub-logo.png`（透明） |
| 跳变 | 有（小图->大图） | 无（纯色->纯色+mascot） |
| Android 12+ | 海报塞 icon 槽（裁坏） | 纯色 + launcher icon 闪现 |
| spec §3.1 全屏海报意图 | 符合 | **有意变更**（§2.2 代价，用户已确认） |

---

## 7. 执行顺序与依赖

```
Step 1 (资产，外部) ──阻塞──> Step 2 (pubspec)
                                 │
                                 v
                              Step 3 (regenerate native) ──> Step 4 (SplashScreen)
                                                            │
                                                            v
                                                         Step 5 (test)
                                                            │
                                                            v
                                                         Step 6 (视觉验证，真机)
                                                            │
                                                            v
                                                         Step 7 (doc) + Step 8 (commit)
```

**Step 1 是唯一外部依赖**。若用户暂无法抠图，可用 `xiahub-icon-v4.png`（白底）占位跑通 Step 2-5 管线验证，Step 6 视觉验证前必须换成透明 `xiahub-logo.png`。

---

## 8. 不做的事（明确排除）

- 不改 `StartupGate` 状态机 / `MinDisplayTimer` / `FatalScreen`（与跳变无关）
- 不改 `bootstrap.dart` 启动链
- 不引入新的 Flutter 依赖
- 不做 Android 12+ 的 `postSplashScreenTheme` 抑制（列为 future work）
- 不迁移资产目录（保留 `docs/design/assets/` carve-out，spec §8 决策）
- 不把"虾Hub"文字加回 splash（§2.3 否决理由）
