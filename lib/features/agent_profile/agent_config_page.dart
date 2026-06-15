import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';

/// 主题色选项，由 [AppColors.agentColors] 生成（唯一真相源），
/// 中文标签来自 [_colorLabels]。
///
/// 如果 _colorLabels 条目不足（颜色数 > 标签数），超出部分用 "颜色 N" 兜底，
/// 避免 release 模式下因 assert 被移除而导致索引越界崩溃。
final _themeColorOptions = () {
  assert(
    _colorLabels.length >= AppColors.agentColors.length,
    '_colorLabels (${_colorLabels.length}) 条目不足，'
    'AppColors.agentColors 有 ${AppColors.agentColors.length} 个颜色',
  );
  return List.generate(
    AppColors.agentColors.length,
    (i) => ColorOption(
      hex: AppColors.agentColors[i].toHex(),
      label: i < _colorLabels.length ? _colorLabels[i] : '颜色 $i',
    ),
  );
}();

// 为每个颜色选项补充中文标签（顺序与 AppColors.agentColors 一一对应）
// 标签名称与 design-tokens.md Section 1.5 的 Per-Agent 主题色一致
const _colorLabels = [
  '珊瑚',
  '雾蓝',
  '薄荷',
  '暖橙',
  '烟粉',
  '湖蓝',
  '暖黄',
  '玫瑰',
  '石墨',
  '翡翠',
  '靛蓝',
  '焦糖',
];

/// 个性化配置页
///
/// 允许用户修改 Agent 的昵称和主题色。
/// 与 AgentProfilePage 共享同一个 AgentProfileViewModel。
///
/// 表单初始化通过 [ref.listen] 在数据就绪后执行，
/// 保存成功/失败的导航效果也通过 [ref.listen] 处理——build 方法不再包含副作用。
class AgentConfigPage extends ConsumerStatefulWidget {
  final String agentId;

  const AgentConfigPage({super.key, required this.agentId});

  @override
  ConsumerState<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  final _nicknameController = TextEditingController();
  String _themeColor = '';
  bool _formReady = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  /// 转发到 ViewModel，Widget 不做决策 (Law 2)
  void _save() {
    final text = _nicknameController.text.trim();
    final nickname = text.isEmpty ? null : text;
    ref
        .read(agentProfileViewModelProvider(widget.agentId).notifier)
        .saveProfile(nickname, _themeColor);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    final theme = Theme.of(context);

    // ---- Side effects via ref.listen (not in build body) ----
    //
    // ref.listen is intentionally called inside build() rather than initState
    // because it needs access to `state` (the Riverpod-provided value from
    // ref.watch on the line above). Riverpod deduplicates listeners by
    // identity, so calling it here does not create duplicate subscriptions.
    ref.listen(agentProfileViewModelProvider(widget.agentId), (prev, next) {
      // 1) Form initialization: when detail data first arrives,
      //    and re-init after every refresh (e.g. saveProfile → refresh).
      if (next.detailLoadState is LoadInProgress<AgentDetailData>) {
        _formReady = false;
      }
      if (!_formReady) {
        final detail = switch (next.detailLoadState) {
          LoadData<AgentDetailData>(:final value) => value,
          _ => null,
        };
        if (detail != null) {
          setState(() {
            _formReady = true;
            _nicknameController.text = detail.agent.nickname ?? '';
            _themeColor = detail.agent.themeColor;
          });
        }
      }

      // 2) Save success → pop back
      if (next.saveSuccess && !(prev?.saveSuccess ?? false)) {
        ref
            .read(agentProfileViewModelProvider(widget.agentId).notifier)
            .clearSaveResult();
        if (mounted) context.pop();
      }

      // 3) Save error → SnackBar
      if (next.saveError != null && next.saveError != prev?.saveError) {
        final msg = next.saveError!;
        ref
            .read(agentProfileViewModelProvider(widget.agentId).notifier)
            .clearSaveResult();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    });

    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);

    // Extract agent from state — no force-unwrap, no vm.agent getter
    final detail = switch (state.detailLoadState) {
      LoadData<AgentDetailData>(:final value) => value,
      _ => null,
    };

    final appBar = AppBar(title: const Text('个性化配置'));

    // 1) 加载中：骨架屏
    if (state.detailLoadState is LoadInProgress<AgentDetailData>) {
      return Scaffold(appBar: appBar, body: const LoadingSkeleton(count: 3));
    }

    // 2) 加载失败：错误 UI + 重试
    if (state.detailLoadState case LoadError<AgentDetailData>(:final error)) {
      return Scaffold(
        appBar: appBar,
        body: LoadErrorView(
          error: error,
          title: '无法加载虾信息',
          onRetry: () => vm.refresh(),
        ),
      );
    }

    // 3) 数据就绪但表单尚未初始化（首次进入时短暂窗口）
    if (detail == null || !_formReady) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final agent = detail.agent;

    return PopScope(
      canPop: !state.isSaving,
      // onPopInvokedWithResult intentionally omitted —
      // ref.listen already handles save-success → pop.
      // Adding a manual context.pop() here would defeat canPop (see #1).
      child: Scaffold(
        appBar: AppBar(
          leading: XiaBackButton(
            onPressed: state.isSaving ? null : () => context.pop(),
          ),
          title: Text('${agent.displayName} · 个性化配置'),
        ),
        body: ListView(
          children: [
            // Section: 基本信息
            Padding(
              padding: const EdgeInsets.fromLTRB(
                XiaSpacing.s5,
                XiaSpacing.s4,
                XiaSpacing.s5,
                XiaSpacing.s1,
              ),
              child: Text(
                '🦐 基本信息',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: XiaColors.text3,
                  fontWeight: FontWeight.w600,
                  fontSize: XiaTypography.sectionLabel,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: XiaSpacing.s6,
                vertical: XiaSpacing.s2,
              ),
              padding: const EdgeInsets.all(XiaSpacing.s5),
              decoration: BoxDecoration(
                color: XiaColors.surface,
                borderRadius: BorderRadius.circular(XiaRadius.lg),
              ),
              child: Column(
                children: [
                  // Current avatar (read-only)
                  Row(
                    children: [
                      EmojiAvatar(
                        displayName: agent.displayName,
                        themeColor: _themeColor,
                        radius: 32,
                      ),
                      const SizedBox(width: XiaSpacing.s5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              agent.displayName,
                              style: const TextStyle(
                                fontSize: XiaTypography.configAvatarName,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '头像暂不支持更换',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: XiaColors.text4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: XiaSpacing.s4),
                  // Nickname field
                  TextFormField(
                    controller: _nicknameController,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      hintText: '给你的虾取个名字',
                    ),
                    enabled: !state.isSaving,
                  ),
                ],
              ),
            ),

            // Section: 主题色
            Padding(
              padding: const EdgeInsets.fromLTRB(
                XiaSpacing.s5,
                XiaSpacing.s4,
                XiaSpacing.s5,
                XiaSpacing.s1,
              ),
              child: Text(
                '🎨 主题色',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: XiaColors.text3,
                  fontWeight: FontWeight.w600,
                  fontSize: XiaTypography.sectionLabel,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: XiaSpacing.s6,
                vertical: XiaSpacing.s2,
              ),
              padding: const EdgeInsets.all(XiaSpacing.s5),
              decoration: BoxDecoration(
                color: XiaColors.surface,
                borderRadius: BorderRadius.circular(XiaRadius.lg),
              ),
              child: ColorGrid(
                colors: _themeColorOptions,
                selectedColor: _themeColor,
                onColorSelected: state.isSaving
                    ? (_) {}
                    : (color) => setState(() => _themeColor = color),
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(XiaSpacing.s6),
              child: PrimaryButton(
                label: '💾 保存配置',
                isLoading: state.isSaving,
                onPressed: state.isSaving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
