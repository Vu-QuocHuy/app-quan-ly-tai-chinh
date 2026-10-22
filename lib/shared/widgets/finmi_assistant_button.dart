import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_strings.dart';
import '../../features/chat/presentation/chat_screen.dart';

final hideFloatingAssistantProvider = StateProvider<bool>((ref) => false);

/// Quản lý việc phát hiện cửa sổ pop-up / bottom sheet / dialog đang mở
/// để tự động ẩn nút Trợ lý AI, tránh che khuất nội dung hoặc nút bấm của pop-up.
class ModalRouteTracker extends ChangeNotifier {
  ModalRouteTracker();

  int _modalCount = 0;
  bool get hasModal => _modalCount > 0;

  void onRoutePushed(Route<dynamic> route) {
    if (_isModal(route)) {
      _modalCount++;
      notifyListeners();
    }
  }

  void onRoutePopped(Route<dynamic> route) {
    if (_isModal(route)) {
      _modalCount = (_modalCount - 1).clamp(0, 999);
      notifyListeners();
    }
  }

  bool _isModal(Route<dynamic> route) {
    if (route is PopupRoute) return true;
    if (route is ModalRoute && route.opaque == false) return true;
    final name = route.runtimeType.toString().toLowerCase();
    return name.contains('modalbottomsheet') ||
        name.contains('dialog') ||
        name.contains('popup') ||
        name.contains('bottomsheet') ||
        name.contains('sheet');
  }
}

class FinmiModalObserver extends NavigatorObserver {
  ModalRouteTracker? get _tracker {
    final context = navigator?.context;
    return context == null
        ? null
        : ProviderScope.containerOf(
            context,
            listen: false,
          ).read(hasActiveModalProvider);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _tracker?.onRoutePushed(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _tracker?.onRoutePopped(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _tracker?.onRoutePopped(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) _tracker?.onRoutePopped(oldRoute);
    if (newRoute != null) _tracker?.onRoutePushed(newRoute);
  }
}

final hasActiveModalProvider = ChangeNotifierProvider<ModalRouteTracker>(
  (ref) => ModalRouteTracker(),
);

class FinmiAssistantButton extends ConsumerWidget {
  const FinmiAssistantButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasModal = ref.watch(hasActiveModalProvider).hasModal;
    final explicitlyHidden = ref.watch(hideFloatingAssistantProvider);
    final route = ModalRoute.of(context);
    final isCurrent = route?.isCurrent ?? true;

    // Ẩn hoàn toàn nút khi có bất kỳ modal/dialog/bottom sheet nào đang mở hoặc route này bị che
    if (hasModal || explicitlyHidden || !isCurrent) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: () => showFinmiAssistant(context),
      style: OutlinedButton.styleFrom(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(color: theme.colorScheme.primary, width: 1.25),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
      icon: const Icon(CupertinoIcons.chat_bubble, size: 16),
      label: Text(context.tr.aiAssistant),
    );
  }
}
