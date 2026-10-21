import 'package:flutter/material.dart';
import '../../features/ingestion/presentation/import_source_sheet.dart';

/// Reuses the shell's durable import and review workflow from the overview.
class FinmiActions extends InheritedWidget {
  const FinmiActions({
    required this.openSource,
    required this.scanReceipt,
    required super.child,
    super.key,
  });
  final ValueChanged<ImportSource> openSource;
  final VoidCallback scanReceipt;
  static FinmiActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FinmiActions>();
  @override
  bool updateShouldNotify(FinmiActions oldWidget) =>
      oldWidget.openSource != openSource ||
      oldWidget.scanReceipt != scanReceipt;
}
