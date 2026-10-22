import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/finmi_theme.dart';

/// Reference subpage chrome, shared by primary and secondary routes.
class FinmiPageHeader extends AppBar {
  FinmiPageHeader({
    required String title,
    List<Widget> actions = const [],
    super.bottom,
    super.key,
  }) : super(
         centerTitle: true,
         leading: const FinmiBackButton(),
         title: Text(
           title,
           maxLines: 3,
           softWrap: true,
           overflow: TextOverflow.visible,
           style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
         ),
         actions: [
           ...actions,
           if (actions.isNotEmpty) const SizedBox(width: 16),
         ],
       );
}

class FinmiSliverHeader extends StatelessWidget {
  const FinmiSliverHeader({
    required this.title,
    this.actions = const [],
    super.key,
  });
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => SliverAppBar(
    pinned: true,
    toolbarHeight:
        64 * (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1, 2.5),
    centerTitle: true,
    leading: const FinmiBackButton(),
    title: Text(
      title,
      maxLines: 3,
      softWrap: true,
      overflow: TextOverflow.visible,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 16)],
  );
}

class FinmiBackButton extends StatelessWidget {
  const FinmiBackButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Quay lại',
    icon: const Icon(Icons.chevron_left_rounded),
    onPressed: () {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        GoRouter.maybeOf(context)?.go('/');
      }
    },
  );
}

class FinmiHeaderAction extends StatelessWidget {
  const FinmiHeaderAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badge = false,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Center(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          fixedSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          side: BorderSide(color: context.finmi.border, width: 1.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Badge(
          isLabelVisible: badge,
          smallSize: 6,
          child: Icon(icon, size: 19),
        ),
      ),
    ),
  );
}

class FinmiSectionLabel extends StatelessWidget {
  const FinmiSectionLabel(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final label = Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    if (trailing == null) return label;
    return context.needsStackedLayout
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label, const SizedBox(height: 4), trailing!],
          )
        : Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: 8),
              Flexible(child: trailing!),
            ],
          );
  }
}
