import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_strings.dart';
import '../utils/camera_permission_helper.dart';
import 'qr_scanner_overlay.dart';

/// Màn quét QR dùng chung. Trả về chuỗi đã quét khi [validate] trả `null`;
/// ngược lại hiện lỗi và quét tiếp. Không gọi server.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({required this.title, required this.validate, super.key});

  final String title;
  final String? Function(String raw) validate;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    facing: kIsWeb ? CameraFacing.front : CameraFacing.back,
  );
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_initWebCamera());
    }
  }

  Future<void> _initWebCamera() async {
    await requestBrowserCameraPermission();
    if (mounted) {
      try {
        await _controller.start();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final error = widget.validate(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _done = true;
    Navigator.pop(context, raw);
  }

  Future<void> _pickQrImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final capture = await _controller.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (capture != null) {
        _onDetect(capture);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: theme.colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_outlined,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr.isEn
                            ? 'Could not open camera. Please grant camera permissions to scan, '
                                  'or go back and enter invite code.'
                            : 'Không mở được camera. Hãy cấp quyền truy cập camera để quét, '
                                  'hoặc quay lại và chọn "Nhập mã mời".',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr.isEn
                            ? 'Tip: Check site permissions next to URL bar to Allow Camera.'
                            : 'Mẹo: Bấm biểu tượng cài đặt cạnh thanh URL để Cho phép (Allow) Camera.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              if (kIsWeb) {
                                await requestBrowserCameraPermission();
                              }
                              try {
                                await _controller.stop();
                              } catch (_) {}
                              try {
                                await _controller.start();
                              } catch (_) {}
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              context.tr.isEn
                                  ? 'Retry Camera'
                                  : 'Thử lại camera',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickQrImage,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              context.tr.isEn ? 'Choose Image' : 'Chọn ảnh QR',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          QrScannerOverlay(
            hintText: context.tr.isEn
                ? 'Place QR code inside frame to scan'
                : 'Đặt mã QR vào khung để quét',
          ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
