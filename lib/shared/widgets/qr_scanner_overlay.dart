import 'package:flutter/material.dart';

/// Lớp phủ camera quét mã: nền xung quanh tối đen, ở giữa có khung trong suốt viền trắng
/// để người dùng tập trung quét mã QR hoặc chụp hóa đơn.
class QrScannerOverlay extends StatelessWidget {
  const QrScannerOverlay({
    super.key,
    this.windowSize = const Size(264, 264),
    this.borderRadius = 28.0,
    this.borderWidth = 3.0,
    this.overlayColor = const Color(0xDD000000),
    this.borderColor = Colors.white,
    this.hintText,
  });

  final Size windowSize;
  final double borderRadius;
  final double borderWidth;
  final Color overlayColor;
  final Color borderColor;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final left = (screenWidth - windowSize.width) / 2;
        final top = (screenHeight - windowSize.height) / 2;
        final scanWindow = Rect.fromLTWH(
          left,
          top,
          windowSize.width,
          windowSize.height,
        );

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
                top: top + windowSize.height + 20,
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
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          scanWindow,
          Radius.circular(borderRadius),
        ),
      );

    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final overlayPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(overlayPath, overlayPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        scanWindow,
        Radius.circular(borderRadius),
      ),
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
