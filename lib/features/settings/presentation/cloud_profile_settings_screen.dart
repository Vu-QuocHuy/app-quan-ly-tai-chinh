import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme_mode_provider.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../data/supabase_profile_preferences_store.dart';

class CloudProfileSettingsScreen extends ConsumerStatefulWidget {
  const CloudProfileSettingsScreen({super.key});

  @override
  ConsumerState<CloudProfileSettingsScreen> createState() =>
      _CloudProfileSettingsScreenState();
}

class _CloudProfileSettingsScreenState
    extends ConsumerState<CloudProfileSettingsScreen> {
  bool _loading = true;
  bool _applying = false;
  String? _error;
  ProfilePreferences? _preferences;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authUserProvider, (previous, next) {
      if (next.valueOrNull != null && _preferences == null && !_loading) {
        unawaited(_load());
      }
    });
    final user = ref.watch(authUserProvider).value;
    final store = ref.watch(profilePreferencesStoreProvider);
    final preferences = _preferences;

    return Scaffold(
      appBar: AppBar(title: const Text('Khôi phục tùy chỉnh', maxLines: 3)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const AppCallout(
            icon: Icons.cloud_download_outlined,
            message:
                'Giao diện và cảnh báo được chỉnh tại Cài đặt và tự lưu lên tài khoản. Khi đổi thiết bị, áp dụng bản đã lưu tại đây.',
          ),
          const SizedBox(height: 16),
          if (user == null || store == null)
            Card(
              child: ListTile(
                title: const Text(
                  'Cần đăng nhập để khôi phục tùy chỉnh.',
                  maxLines: 3,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/account'),
              ),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (preferences == null)
            Card(
              child: ListTile(
                title: const Text(
                  'Không tải được tùy chỉnh đã lưu',
                  maxLines: 3,
                ),
                subtitle: Text(_error ?? 'Kiểm tra kết nối rồi thử lại.'),
                trailing: IconButton(
                  tooltip: 'Thử lại',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: const Text('Giao diện đã lưu', maxLines: 3),
                    subtitle: Text(switch (_themeFromName(
                      preferences.themeMode,
                    )) {
                      ThemeMode.light => 'Sáng',
                      ThemeMode.dark => 'Tối',
                      ThemeMode.system => 'Theo hệ thống',
                    }),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Cảnh báo ngân sách đã lưu', maxLines: 3),
                    subtitle: Text(
                      preferences.budgetAlertsEnabled ? 'Bật' : 'Tắt',
                    ),
                  ),
                ],
              ),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(
                _applying ? 'Đang áp dụng…' : 'Áp dụng trên thiết bị',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _load() async {
    final store = ref.read(profilePreferencesStoreProvider);
    if (store == null || !store.canSync) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preferences = await store.load();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _apply() async {
    final preferences = _preferences;
    if (preferences == null) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref
          .read(themeModeProvider.notifier)
          .set(_themeFromName(preferences.themeMode));
      await ref
          .read(budgetAlertPreferencesProvider)
          .setEnabled(preferences.budgetAlertsEnabled);
      ref.invalidate(budgetAlertsEnabledProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã áp dụng tùy chỉnh trên thiết bị.')),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  ThemeMode _themeFromName(String name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
