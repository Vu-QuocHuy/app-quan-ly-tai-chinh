import 'package:flutter/material.dart';

class FinmiBrand extends StatelessWidget {
  const FinmiBrand({this.width = 114, this.showTagline = false, super.key});
  final double width;
  final bool showTagline;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Crop only the transparent margin, using the reference HTML's viewport.
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRect(
          child: SizedBox(
            width: width,
            height: width * 42 / 112,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: width * 1.4318,
              maxHeight: width * 1.4318 / 3,
              child: Transform.translate(
                offset: Offset(
                  -width * 1.4318 * .1542,
                  -width * 1.4318 / 3 * .1685,
                ),
                child: Image.asset(
                  'assets/branding/finmi/logo.png',
                  width: width * 1.4318,
                  semanticLabel: 'Finmi',
                ),
              ),
            ),
          ),
        ),
      ),
      if (showTagline) ...[
        const SizedBox(height: 8),
        Text(
          'Theo dõi chi tiêu mỗi ngày',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}
