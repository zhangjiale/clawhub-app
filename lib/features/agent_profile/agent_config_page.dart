import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/features/agent_profile/providers/agent_profile_providers.dart';
import 'package:claw_hub/ui_kit/color_grid.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';

/// 12 色主题色选项（与 AppColors.agentColors 一致）
const _themeColorOptions = [
  ColorOption(hex: '#6C5CE7', label: '紫罗兰'),
  ColorOption(hex: '#0984E3', label: '海洋蓝'),
  ColorOption(hex: '#FD79A8', label: '樱花粉'),
  ColorOption(hex: '#00B894', label: '薄荷绿'),
  ColorOption(hex: '#E17055', label: '活力橙'),
  ColorOption(hex: '#00CEC9', label: '湖蓝'),
  ColorOption(hex: '#FDCB6E', label: '柠檬黄'),
  ColorOption(hex: '#E84393', label: '玫瑰红'),
  ColorOption(hex: '#636E72', label: '石墨灰'),
  ColorOption(hex: '#2D3436', label: '深灰'),
  ColorOption(hex: '#6AB04C', label: '草绿'),
  ColorOption(hex: '#5352ED', label: '靛蓝'),
];

/// 个性化配置页
///
/// 允许用户修改 Agent 的昵称和主题色。
/// 与 AgentProfilePage 共享同一个 AgentProfileViewModel。
class AgentConfigPage extends ConsumerStatefulWidget {
  final String agentId;

  const AgentConfigPage({super.key, required this.agentId});

  @override
  ConsumerState<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends ConsumerState<AgentConfigPage> {
  bool _initialized = false;
  late String _nickname;
  late String _themeColor;
  final _nicknameController = TextEditingController();

  void _initFormState() {
    if (_initialized) return;
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final agent = vm.agent;
    if (agent == null) return;
    _initialized = true;
    _nickname = agent.nickname ?? '';
    _themeColor = agent.themeColor;
    _nicknameController.text = _nickname;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  /// 转发到 ViewModel，Widget 不做决策 (Law 2)
  void _save() {
    final nickname = _nickname.trim().isEmpty ? null : _nickname.trim();
    ref.read(agentProfileViewModelProvider(widget.agentId).notifier)
        .saveProfile(widget.agentId, nickname, _themeColor);
  }

  @override
  Widget build(BuildContext context) {
    // 必须在 build 中 watch state 以注册 Riverpod 依赖，
    // 确保 agent 异步加载完成后 Widget 自动 rebuild。
    final state = ref.watch(agentProfileViewModelProvider(widget.agentId));

    _initFormState();
    if (!_initialized) {
      return const SizedBox.shrink();
    }
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final agent = vm.agent!;
    final theme = Theme.of(context);

    // 响应 saveSuccess → pop
    if (state.saveSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          vm.clearSaveResult();
          context.pop();
        }
      });
    }

    // 响应 saveError → SnackBar
    if (state.saveError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.saveError!)),
          );
          vm.clearSaveResult();
        }
      });
    }

    return PopScope(
      canPop: !state.isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    onChanged: (value) => _nickname = value,
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
