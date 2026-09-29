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
  bool _saving = false;
  String? _error;
  ProfilePreferences? _preferences;
  ThemeMode _themeMode = ThemeMode.system;
  bool _budgetAlertsEnabled = true;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt tài khoản')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AppCallout(
            icon: Icons.cloud_sync_outlined,
            message: user == null
                ? 'Đăng nhập để đồng bộ lựa chọn giao diện và cảnh báo giữa các thiết bị.'
                : 'Cài đặt được lưu theo tài khoản ${user.email ?? ''}. '
                      'Lịch sử cài đặt cũ trên thiết bị không được tải lên.',
          ),
          const SizedBox(height: 16),
          if (user == null || store == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.person_outline, size: 32),
                    const SizedBox(height: 8),
                    const Text('Cần đăng nhập để đọc cài đặt cloud.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => context.push('/settings/account'),
                      child: const Text('Đến tài khoản'),
                    ),
                  ],
                ),
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_preferences == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('Không tải được cài đặt'),
                subtitle: Text(_error ?? 'Hãy kiểm tra kết nối rồi thử lại.'),
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
                  const ListTile(
                    leading: Icon(Icons.brightness_6_outlined),
                    title: Text('Giao diện'),
                    subtitle: Text('Được lưu trên hồ sơ cloud của bạn.'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('Hệ thống'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Sáng'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Tối'),
                          ),
                        ],
                        selected: {_themeMode},
                        onSelectionChanged: _saving
                            ? null
                            : (selection) =>
                                  setState(() => _themeMode = selection.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Cảnh báo ngân sách'),
                subtitle: const Text(
                  'Lựa chọn này đồng bộ theo tài khoản; quyền thông báo vẫn do thiết bị kiểm soát.',
                ),
                value: _budgetAlertsEnabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _budgetAlertsEnabled = value),
              ),
            ),
            if (_preferences!.preferredBankAppId case final bankId?) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Ngân hàng QR gần nhất'),
                  subtitle: Text(
                    bankId.isEmpty
                        ? 'Chưa có app ngân hàng nào được đồng bộ.'
                        : 'Đã có lựa chọn được đồng bộ; app sẽ nhớ lựa chọn mới nhất từ QR.',
                  ),
                ),
              ),
            ],
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
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_saving ? 'Đang lưu…' : 'Lưu và áp dụng'),
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
        _themeMode = _themeFromName(preferences.themeMode);
        _budgetAlertsEnabled = preferences.budgetAlertsEnabled;
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

  Future<void> _save() async {
    final store = ref.read(profilePreferencesStoreProvider);
    if (store == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.save(
        themeMode: _themeMode.name,
        budgetAlertsEnabled: _budgetAlertsEnabled,
      );
      await ref.read(themeModeProvider.notifier).set(_themeMode);
      await ref
          .read(budgetAlertPreferencesProvider)
          .setEnabled(_budgetAlertsEnabled);
      ref.invalidate(budgetAlertsEnabledProvider);
      if (!mounted) return;
      setState(() {
        _preferences = ProfilePreferences(
          themeMode: _themeMode.name,
          budgetAlertsEnabled: _budgetAlertsEnabled,
          preferredBankAppId: _preferences?.preferredBankAppId,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu và áp dụng cài đặt cloud.')),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ThemeMode _themeFromName(String name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
