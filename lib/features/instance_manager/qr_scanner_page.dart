import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/features/instance_manager/qr_scan_result.dart';

/// 二维码扫码页面 (US-001)
///
/// 全屏摄像头扫描 OpenClaw Gateway 配置二维码。
/// 扫描成功 → 返回 [QrScanResult] 到调用方。
/// 扫描失败/格式不正确 → 顶部提示错误，继续扫描。
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  late final MobileScannerController _controller;
  bool _hasTorch = false;
  bool _resolved = false;

  String? _errorMessage;
  bool _isProcessing = false;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_resolved || _isProcessing) {
      return;
    }

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) {
      return;
    }

    final raw = barcode.rawValue!;

    try {
      _isProcessing = true;

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        _showError('无法识别的二维码，请确认这是 OpenClaw 配置二维码');
        _isProcessing = false;
        return;
      }

      final result = QrScanResult.fromMap(json);

      _resolved = true;
      if (mounted) {
        Navigator.of(context).pop<QrScanResult>(result);
      }
    } on FormatException catch (e) {
      _showError(e.message);
      _isProcessing = false;
    } catch (error, stackTrace) {
      debugPrint('QR scan parse error: $error\n$stackTrace');
      _showError('无法识别的二维码，请确认这是 OpenClaw 配置二维码');
      _isProcessing = false;
    }
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = message);
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _errorMessage = null);
      }
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) {
        setState(() => _hasTorch = !_hasTorch);
      }
    } catch (_) {
      // Torch not available on this device
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: XiaColors.bg,
      appBar: AppBar(
        backgroundColor: XiaColors.bg,
        foregroundColor: XiaColors.text1,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: Icon(_hasTorch ? Icons.flash_off : Icons.flash_on),
            onPressed: _toggleTorch,
            tooltip: _hasTorch ? 'Turn off flashlight' : 'Turn on flashlight',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera viewfinder
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onBarcode,
              errorBuilder: (context, error) {
                String message;
                if (error.errorCode ==
                    MobileScannerErrorCode.permissionDenied) {
                  message = '相机权限被拒绝，请在系统设置中开启相机权限';
                } else {
                  message =
                      'Camera error: ${error.errorDetails?.message ?? "unknown"}';
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(XiaSpacing.s7),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: XiaColors.text2,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),

          // Scan guide overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: XiaColors.text3, width: 2),
                borderRadius: BorderRadius.circular(XiaRadius.lg),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -1,
                    left: -1,
                    child: _CornerAccent(corner: Corner.topLeft),
                  ),
                  Positioned(
                    top: -1,
                    right: -1,
                    child: _CornerAccent(corner: Corner.topRight),
                  ),
                  Positioned(
                    bottom: -1,
                    left: -1,
                    child: _CornerAccent(corner: Corner.bottomLeft),
                  ),
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: _CornerAccent(corner: Corner.bottomRight),
                  ),
                ],
              ),
            ),
          ),

          // Guide text
          Positioned(
            left: 32,
            right: 32,
            bottom: 120,
            child: Text(
              '将 OpenClaw Gateway 配置二维码置于框内',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: XiaColors.text1,
                shadows: [
                  const Shadow(color: Color(0x8A000000), blurRadius: 8),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Error banner
          if (_errorMessage != null)
            Positioned(
              left: 16,
              right: 16,
              top: 0,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(XiaRadius.sm),
                color: XiaColors.red,
                child: Padding(
                  padding: const EdgeInsets.all(XiaSpacing.s3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: XiaColors.text1,
                        size: 20,
                      ),
                      const SizedBox(width: XiaSpacing.s2),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: XiaColors.text1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerAccent extends StatelessWidget {
  final Corner corner;
  const _CornerAccent({required this.corner});

  @override
  Widget build(BuildContext context) {
    final rotations = switch (corner) {
      Corner.topLeft => 0,
      Corner.topRight => 1,
      Corner.bottomRight => 2,
      Corner.bottomLeft => 3,
    };

    return RotatedBox(
      quarterTurns: rotations,
      child: CustomPaint(size: const Size(24, 24), painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = XiaColors.accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height), const Offset(0, 8), paint);
    canvas.drawLine(const Offset(8, 0), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
