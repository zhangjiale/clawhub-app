import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/features/agent_profile/viewmodels/agent_profile_view_model.dart';
import 'package:claw_hub/ui_kit/async_state.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';
import 'package:claw_hub/ui_kit/loading_skeleton.dart';
import 'package:claw_hub/ui_kit/load_error_view.dart';

/// 主题色选项，由 [AppColors.agentColors] 生成（唯一真相源），
/// 中文标签来自 [_colorLabels]。
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
      label: _colorLabels[i],
    ),
  );
}();

// 为每个颜色选项补充中文标签（顺序与 AppColors.agentColors 一一对应）
const _colorLabels = [
  '紫罗兰',
  '海洋蓝',
  '樱花粉',
  '薄荷绿',
  '活力橙',
  '湖蓝',
  '柠檬黄',
  '玫瑰红',
  '石墨灰',
  '深灰',
  '草绿',
  '靛蓝',
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
    ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
        .saveProfile(nickname, _themeColor);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));
    final theme = Theme.of(context);

    // ---- Side effects via ref.listen (not in build body) ----
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
        ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
            .clearSaveResult();
        if (mounted) context.pop();
      }

      // 3) Save error → SnackBar
      if (next.saveError != null && next.saveError != prev?.saveError) {
        final msg = next.saveError!;
        ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
            .clearSaveResult();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
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
      return Scaffold(
        appBar: appBar,
        body: const LoadingSkeleton(count: 3),
      );
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: state.isSaving ? null : () => context.pop(),
          ),
          title: Text('${agent.displayName} · 个性化配置'),
        ),
        body: ListView(
          children: [
            // Section: 基本信息
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '🦐 基本信息',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Current avatar (read-only)
                  Row(
                    children: [
                      EmojiAvatar(
                        displayName: agent.displayName,
                        themeColor: _themeColor,
                        radius: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              agent.displayName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '头像暂不支持更换',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '🎨 主题色',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: state.isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: state.isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '💾 保存配置',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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
