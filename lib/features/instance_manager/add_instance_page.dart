import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/domain/usecases/gateway_change_exceptions.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';
import 'package:claw_hub/features/instance_manager/widgets/gateway_change_dialog.dart';

/// 添加/编辑实例页 (P0 MVP)
///
/// 支持三种**互斥**模式（构造函数 [assert] 保护）:
/// - 新建 (instanceId == null, scanResult == null): 手动输入
/// - 扫码预填 (instanceId == null, scanResult != null): US-001 扫码后自动填充
/// - 编辑 (instanceId != null, scanResult == null): 修改已有实例
///
/// 编辑模式下 Gateway host 变化处理：
/// - UseCase 内部检测 host 变化 + 本地非空 → 抛 [GatewayChangeRequiredException]
/// - 本页捕获异常 → 弹 [GatewayChangeDialog] → 用户选择后**单次**重试 UseCase
/// - 不递归 `_onSave`，避免 `_isSaving` 状态嵌套混乱
class AddInstancePage extends ConsumerStatefulWidget {
  final String? instanceId;
  final QrScanResult? scanResult; // US-001: pre-filled from QR scan

  const AddInstancePage({super.key, this.instanceId, this.scanResult})
    : assert(
        instanceId == null || scanResult == null,
        'instanceId 与 scanResult 互斥：编辑场景不应同时携带扫码预填值，'
        '否则用户会以为在新建却实际改写了已有实例（见 Issue #5）。',
      );

  @override
  ConsumerState<AddInstancePage> createState() => _AddInstancePageState();
}

class _AddInstancePageState extends ConsumerState<AddInstancePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _isSaving = false;

  /// 表单字段加载就绪 — 编辑模式下需等 [_loadExistingInstance] 完成。
  ///
  /// 在此之前 Save 按钮 disabled，避免用户在 URL 字段尚未填入旧值时
  /// 输入新 URL 并保存，导致 UseCase 把"未加载"误认为"未变化"，
  /// 跳过 host 变化检测分支。
  ///
  /// **加载失败处理**：getById 返回 null（实例已被其它会话删除）或抛异常时，
  /// 必须把 `_isLoaded` 翻为 true 并提示用户，否则 Save 按钮永久 disabled。
  bool _isLoaded = false;

  bool get isEditing => widget.instanceId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _tokenController = TextEditingController();

    // US-001: Pre-fill from QR scan result（同步可用）
    if (widget.scanResult != null) {
      final scan = widget.scanResult!;
      _nameController.text = scan.name ?? '';
      _urlController.text = scan.gatewayUrl;
      _tokenController.text = scan.token ?? '';
      _isLoaded = true;
    } else if (isEditing) {
      _loadExistingInstance();
    } else {
      // 新建：无加载需求
      _isLoaded = true;
    }
  }

  Future<void> _loadExistingInstance() async {
    String? errorText;
    try {
      final repo = ref.read(instanceRepoProvider);
      final instance = await repo.getById(widget.instanceId!);
      if (!mounted) return;
      if (instance == null) {
        errorText = '实例不存在或已被删除';
      } else {
        setState(() {
          _nameController.text = instance.name;
          _urlController.text = instance.gatewayUrl;
          _tokenController.text = instance.tokenRef;
          _isLoaded = true;
        });
        return;
      }
    } catch (error) {
      if (!mounted) return;
      errorText = '加载实例失败: $error';
    }
    // 失败路径：仍翻 _isLoaded，让用户能操作（重试 / 返回）。
    // 不然按钮永久 disabled 会把用户卡死在页面上（见 Issue #1）。
    setState(() => _isLoaded = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(errorText)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Instance name is required';
    }
    return null;
  }

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return 'Gateway URL is required';
    if (!Instance.isValidGatewayUrl(value.trim())) {
      return 'Invalid Gateway URL (e.g. wss://host:18789)';
    }
    return null;
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      // 1) 首次尝试 — UseCase 内部会做 host 变化检测，本地非空时抛
      //    GatewayChangeRequiredException。
      try {
        await _executeSave(null);
        return;
      } on GatewayChangeRequiredException catch (e) {
        if (!mounted) return;
        final choice = await GatewayChangeDialog.show(
          context,
          localAgentCount: e.localAgentCount,
        );
        if (choice == null) return; // 用户取消
        if (!mounted) return;
        // 2) 带着 resolution 重试 — 单次，不递归
        await _executeSave(choice);
      }
    } on PurgeFailedException catch (e) {
      _showSnack(e.message);
    } on GatewayUnreachableException catch (e) {
      _showSnack(e.message);
    } on ArgumentError catch (e) {
      _showSnack(e.message?.toString() ?? 'Validation error');
    } on Exception catch (e) {
      // 兜底：testConnection 在 WS 握手 / DNS 解析失败时抛 SocketException 等
      // 运行时异常。不能让它静默成为 unhandled Future error（见 Issue #3）。
      _showSnack('保存失败: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _executeSave(GatewayChangeResolution? resolution) async {
    final useCase = ref.read(saveInstanceUseCaseProvider);
    await useCase.execute(
      name: _nameController.text.trim(),
      gatewayUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
      instanceId: widget.instanceId,
      onGatewayChange: resolution,
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Issue #9：PrimaryButton 内部已根据 isLoading 自动 disable，无需再 `&& !_isSaving`
    return Scaffold(
      appBar: AppBar(
        leading: XiaBackButton(onPressed: () => context.pop()),
        title: Text(isEditing ? 'Edit Instance' : 'Add Instance'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(XiaSpacing.s4),
          children: [
            // US-001: QR scan pre-fill indicator
            if (widget.scanResult != null) ...[
              Container(
                padding: const EdgeInsets.all(XiaSpacing.s3),
                margin: const EdgeInsets.only(bottom: XiaSpacing.s4),
                decoration: BoxDecoration(
                  color: XiaColors.greenMuted,
                  borderRadius: BorderRadius.circular(XiaRadius.sm),
                  border: Border.all(color: XiaColors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code, color: XiaColors.green, size: 20),
                    const SizedBox(width: XiaSpacing.s2),
                    Expanded(
                      child: Text(
                        'Info pre-filled from QR code',
                        style: const TextStyle(
                          color: XiaColors.green,
                          fontSize: XiaTypography.aux,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Instance Name',
                hintText: 'e.g. My MacBook',
              ),
              validator: _validateName,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: XiaSpacing.s4),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Gateway URL',
                hintText: 'wss://host:18789',
              ),
              validator: _validateUrl,
              keyboardType: TextInputType.url,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: XiaSpacing.s4),
            TextFormField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Auth Token',
                hintText: 'OpenClaw Gateway token',
              ),
              obscureText: true,
            ),
            const SizedBox(height: XiaSpacing.s7),
            PrimaryButton(
              label: 'Save',
              isLoading: _isSaving,
              onPressed: _isLoaded ? _onSave : null,
            ),
          ],
        ),
      ),
    );
  }
}
