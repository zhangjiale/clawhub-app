import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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

/// 主题色选项，由 [AppColors.agentColors] + [XiaColors.agentColorLabels] 生成（唯一真相源）。
///
/// 中文标签来自 [XiaColors.agentColorLabels]（`lib/app/theme/tokens.dart`），
/// 不再在本地维护重复的 [_colorLabels] 列表。
/// 如果标签条目不足，超出部分用 "颜色 N" 兜底，避免索引越界崩溃。
final _themeColorOptions = () {
  assert(
    () {
      final colorCount = AppColors.agentColors.length;
      final labels = XiaColors.agentColorLabels;
      return colorCount <= labels.length &&
          List.generate(
            colorCount,
            (i) => i,
          ).every((i) => labels.containsKey(i));
    }(),
    'XiaColors.agentColorLabels 缺少索引 0..${AppColors.agentColors.length - 1} 的条目',
  );
  return List.generate(
    AppColors.agentColors.length,
    (i) => ColorOption(
      hex: AppColors.agentColors[i].toHex(),
      label: XiaColors.agentColorLabels[i] ?? '颜色 $i',
    ),
  );
}();

/// 个性化配置页
///
/// 允许用户修改 Agent 的昵称、主题色和头像。
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
  String _themeColor = '#007AFF'; // Agent 默认主题色，始终为有效 hex
  bool _formReady = false;

  @override
  void initState() {
    super.initState();
    // 当前状态可能已经包含已加载的数据（例如从 AgentProfilePage 导航而来，
    // 两者共享同一个 agentProfileViewModelProvider）。
    // ref.listen 只在状态转移时触发，不会对当前值触发，因此需要在 initState
    // 中同步检查并初始化表单，覆盖「数据已就绪」的路径。
    _tryInitForm();
  }

  void _tryInitForm() {
    final state = ref.read(agentProfileViewModelProvider(widget.agentId));
    final detail = switch (state.detailLoadState) {
      LoadData<AgentDetailData>(:final value) => value,
      _ => null,
    };
    if (detail != null) {
      _formReady = true;
      _nicknameController.text = detail.agent.nickname ?? '';
      _themeColor = detail.agent.themeColor;
    }
  }

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
        .saveProfile(nickname: nickname, themeColor: _themeColor);
  }

  // ── Avatar picker ──────────────────────────────────────────

  void _showAvatarPicker() {
    final vm = ref.read(agentProfileViewModelProvider(widget.agentId).notifier);
    final state = ref.read(agentProfileViewModelProvider(widget.agentId));

    // Extract current agent to check whether avatar is set
    final detail = switch (state.detailLoadState) {
      LoadData<AgentDetailData>(:final value) => value,
      _ => null,
    };
    final hasAvatar = detail?.agent.avatarUrl != null;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: XiaColors.red),
                title: const Text(
                  '移除头像',
                  style: TextStyle(color: XiaColors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  // removeAvatar() 内部已 try/catch 所有错误并写入 saveError；
                  // .catchError 仅兜底防止未来重构后异常逃逸被 zone 静默吞掉。
                  vm.removeAvatar().catchError((_) {
                    /* handled internally */
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final isCamera = source == ImageSource.camera;

    // Phase 1: pick image (permission / picker errors)
    final XFile? xfile;
    try {
      xfile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('ImagePicker failed for $source: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCamera ? '无法访问相机，请检查权限设置' : '无法访问相册，请检查权限设置'),
          ),
        );
      }
      return;
    }

    if (xfile == null) return; // user cancelled

    // Phase 2: read bytes + update avatar (I/O / DB errors)
    try {
      final bytes = await xfile.readAsBytes();
      await ref
          .read(agentProfileViewModelProvider(widget.agentId).notifier)
          .updateAvatar(bytes);
      // updateAvatar errors are surfaced via ref.listen → saveError SnackBar
    } catch (e) {
      debugPrint('Avatar processing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像处理失败，请重试')));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────

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
                  // Avatar — tappable for change
                  GestureDetector(
                    onTap: state.isSaving ? null : _showAvatarPicker,
                    child: Stack(
                      children: [
                        EmojiAvatar(
                          displayName: agent.displayName,
                          themeColor: _themeColor,
                          avatarImage: agent.avatarUrl != null
                              ? FileImage(File(agent.avatarUrl!))
                              : null,
                          radius: 32,
                        ),
                        if (state.isSaving)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(
                                  XiaRadius.md,
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agent.avatarUrl != null ? '点击更换头像' : '点击设置头像',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: XiaColors.text4,
                    ),
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
