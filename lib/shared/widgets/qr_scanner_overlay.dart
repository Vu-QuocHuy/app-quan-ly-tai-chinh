import 'package:flutter/material.dart';

/// Lớp phủ camera quét mã: nền xung quanh tối mờ, ở giữa có khung trong suốt viền trắng
/// để người dùng tập trung quét mã QR hoặc chụp hóa đơn.
class QrScannerOverlay extends StatelessWidget {
  const QrScannerOverlay({
    super.key,
    this.windowSize = const Size(264, 264),
    this.borderRadius = 24.0,
    this.borderWidth = 3.0,
    this.overlayColor = const Color(0x99000000),
    this.borderColor = Colors.white,
    this.hintText,
    this.verticalOffset = 0.0,
    this.hintSpacing = 16.0,
  });

  final Size windowSize;
  final double borderRadius;
  final double borderWidth;
  final Color overlayColor;
  final Color borderColor;
  final String? hintText;
  final double verticalOffset;
  final double hintSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        final actualWidth = windowSize.width.clamp(100.0, screenWidth - 32.0);
        final actualHeight = windowSize.height.clamp(
          100.0,
          screenHeight - 64.0,
        );

        final left = (screenWidth - actualWidth) / 2;
        final top = ((screenHeight - actualHeight) / 2 + verticalOffset).clamp(
          12.0,
          screenHeight - actualHeight - 12.0,
        );

        final scanWindow = Rect.fromLTWH(left, top, actualWidth, actualHeight);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _QrScannerOverlayPainter(
                scanWindow: scanWindow,
                borderRadius: borderRadius,
                borderWidth: borderWidth,
                overlayColor: overlayColor,
                borderColor: borderColor,
              ),
            ),
            if (hintText != null)
              Positioned(
                top: top + actualHeight + hintSpacing,
                left: 20,
                right: 20,
                child: Text(
                  hintText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QrScannerOverlayPainter extends CustomPainter {
  const _QrScannerOverlayPainter({
    required this.scanWindow,
    required this.borderRadius,
    required this.borderWidth,
    required this.overlayColor,
    required this.borderColor,
  });

  final Rect scanWindow;
  final double borderRadius;
  final double borderWidth;
  final Color overlayColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    // Use PathFillType.evenOdd to cut out the scanWindow cleanly from the overlay.
    // Unlike Path.combine (which fails on Flutter Web HTML renderer and falls back
    // to drawing over the whole screen), evenOdd fill rule works natively across all
    // platforms (CanvasKit, HTML5 Canvas 2D, and native engines), leaving the center 100% clear.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)),
      );

    canvas.drawPath(path, overlayPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QrScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanWindow != scanWindow ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.borderColor != borderColor;
}
