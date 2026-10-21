import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../features/chat/presentation/chat_screen.dart';

class FinmiAssistantButton extends StatelessWidget {
  const FinmiAssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: () => showFinmiAssistant(context),
      style: OutlinedButton.styleFrom(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(color: theme.colorScheme.primary, width: 1.25),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: theme.textTheme.bodySmall,
      ),
      icon: const Icon(CupertinoIcons.chat_bubble, size: 15),
      label: const Text('Trợ lý AI'),
    );
  }
}
