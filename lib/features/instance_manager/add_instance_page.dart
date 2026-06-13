import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';

/// 添加/编辑实例页 (P0 MVP)
///
/// 支持三种模式:
/// - 新建 (instanceId == null, scanResult == null): 手动输入
/// - 扫码预填 (instanceId == null, scanResult != null): US-001 扫码后自动填充
/// - 编辑 (instanceId != null): 修改已有实例
class AddInstancePage extends ConsumerStatefulWidget {
  final String? instanceId;
  final QrScanResult? scanResult; // US-001: pre-filled from QR scan

  const AddInstancePage({super.key, this.instanceId, this.scanResult});

  @override
  ConsumerState<AddInstancePage> createState() => _AddInstancePageState();
}

class _AddInstancePageState extends ConsumerState<AddInstancePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _isSaving = false;

  bool get isEditing => widget.instanceId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _tokenController = TextEditingController();

    // US-001: Pre-fill from QR scan result
    if (widget.scanResult != null) {
      final scan = widget.scanResult!;
      _nameController.text = scan.name ?? '';
      _urlController.text = scan.gatewayUrl;
      _tokenController.text = scan.token ?? '';
    }

    if (isEditing) {
      _loadExistingInstance();
    }
  }

  Future<void> _loadExistingInstance() async {
    final repo = ref.read(instanceRepoProvider);
    final instance = await repo.getById(widget.instanceId!);
    if (instance != null && mounted) {
      _nameController.text = instance.name;
      _urlController.text = instance.gatewayUrl;
    }
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
      final useCase = ref.read(saveInstanceUseCaseProvider);
      await useCase.execute(
        name: _nameController.text.trim(),
        gatewayUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
        instanceId: widget.instanceId,
      );
      if (mounted) {
        context.pop();
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Validation error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Instance' : 'Add Instance')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // US-001: QR scan pre-fill indicator
            if (widget.scanResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.qr_code, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Info pre-filled from QR code',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 13,
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Auth Token',
                hintText: 'OpenClaw Gateway token',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isSaving ? null : _onSave,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
