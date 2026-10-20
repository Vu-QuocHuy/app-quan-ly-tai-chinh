import 'package:flutter/material.dart';

/// App bars grow with system text settings instead of clipping their titles.
class FinmiResponsiveTheme extends StatelessWidget {
  const FinmiResponsiveTheme({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(20) / 20;
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          toolbarHeight: scale > 1.2 ? 64 * scale : 64,
        ),
      ),
      child: child,
    );
  }
}
