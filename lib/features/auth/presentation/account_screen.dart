import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/local_database_scope.dart';
import '../../../core/providers/app_providers.dart';
import '../../chat/data/chat_history_store.dart';
import '../../export/data/backup_catalog_store.dart';
import '../../ingestion/data/drift_import_job_store.dart';
import '../../ingestion/data/pending_import_store.dart';
import '../../insights/data/anomaly_feedback_store.dart';
import '../../invoices/data/drift_invoice_repository.dart';
import '../../notifications/data/budget_alert_preferences.dart';
import '../domain/auth_validators.dart';
import '../../notifications/data/budget_notification_service.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_skeleton.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _verificationEmail;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    final user = ref.watch(authUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản và đồng bộ')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.xl,
                AppSpacing.gutter,
                AppSpacing.xxl,
              ),
              children: [
                if (client == null)
                  const _ConfigurationMissingCard()
                else
                  user.when(
                    data: (currentUser) => currentUser == null
                        ? _buildAuthForm(context)
                        : _buildSignedIn(context, currentUser),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _StatusCard(
                      icon: Icons.cloud_off_outlined,
                      title: 'Không đọc được phiên đăng nhập',
                      message: friendlyMessage(error),
                      isError: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.primaryContainer,
                shape: AppShapes.card,
              ),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Icon(
                  Icons.cloud_sync_outlined,
                  size: 36,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Đồng bộ chi tiêu an toàn',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Dữ liệu vẫn được lưu trên thiết bị và sẽ đồng bộ với cloud khi bạn đăng nhập.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _registering
                        ? 'Tạo tài khoản mới'
                        : 'Chào mừng bạn trở lại',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _registering
                        ? 'Dùng email để lưu và đồng bộ dữ liệu của riêng bạn.'
                        : 'Đăng nhập để tiếp tục quản lý chi tiêu của bạn.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    container: true,
                    label: 'Chọn đăng nhập hoặc đăng ký',
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.login),
                          label: Text('Đăng nhập'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.person_add_alt_1_outlined),
                          label: Text('Đăng ký'),
                        ),
                      ],
                      selected: {_registering},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) {
                              setState(() {
                                _registering = selection.first;
                                _verificationEmail = null;
                                _message = null;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_message != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: _StatusCard(
                        icon: _messageIsError
                            ? Icons.error_outline
                            : Icons.mark_email_read_outlined,
                        title: _messageIsError ? 'Có lỗi xảy ra' : 'Đã xử lý',
                        message: _message!,
                        isError: _messageIsError,
                        actionLabel: _verificationEmail == null
                            ? null
                            : 'Gửi lại email xác nhận',
                        onAction: _verificationEmail == null
                            ? null
                            : _resendSignupConfirmation,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  TextFormField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'ban@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: AuthValidators.email,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    textInputAction: _registering
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      _registering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onFieldSubmitted: _registering || _busy
                        ? null
                        : (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      helperText: _registering
                          ? 'Tối thiểu 8 ký tự. Bạn có thể dùng trình quản lý mật khẩu.'
                          : null,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Hiện mật khẩu'
                            : 'Ẩn mật khẩu',
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Hãy nhập mật khẩu.';
                      }
                      if (_registering && value.length < 8) {
                        return 'Mật khẩu cần ít nhất 8 ký tự.';
                      }
                      return null;
                    },
                  ),
                  if (!_registering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _sendPasswordReset,
                        child: const Text('Quên mật khẩu?'),
                      ),
                    ),
                  if (_registering) ...[
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _confirmationController,
                      enabled: !_busy,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: _busy ? null : (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Hãy nhập lại mật khẩu.';
                        }
                        return value != _passwordController.text
                            ? 'Hai mật khẩu chưa khớp.'
                            : null;
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const ButtonSpinner()
                        : Icon(
                            _registering
                                ? Icons.person_add_alt_1_outlined
                                : Icons.login,
                          ),
                    label: Text(_registering ? 'Tạo tài khoản' : 'Đăng nhập'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signInWithGoogle,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Tiếp tục với Google'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppCallout(
            tone: CalloutTone.neutral,
            icon: Icons.security_outlined,
            title: 'Lưu trên máy, đồng bộ cloud',
            message:
                'Ứng dụng ưu tiên lưu dữ liệu trên thiết bị. Khi có mạng, các thay đổi sẽ được đồng bộ an toàn với tài khoản của bạn.',
          ),
        ],
      ),
    );
  }

  Widget _buildSignedIn(BuildContext context, User user) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: Icons.cloud_done_outlined,
          title: 'Đã kết nối Supabase',
          message: user.email ?? 'Tài khoản ${user.id}',
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildIdentitySection(context),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: true,
            child: _StatusCard(
              icon: _messageIsError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              title: _messageIsError ? 'Có lỗi xảy ra' : 'Hoàn tất',
              message: _message!,
              isError: _messageIsError,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _SectionHeading(
          icon: Icons.cloud_sync_outlined,
          title: 'Dữ liệu và đồng bộ',
          message:
              'Đẩy thay đổi đang chờ lên cloud hoặc tải thay đổi mới về máy.',
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _syncNow,
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.sync),
          label: const Text('Đồng bộ ngay'),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _SectionHeading(
          icon: Icons.shield_outlined,
          title: 'Bảo mật tài khoản',
          message: 'Quản lý mật khẩu, phiên đăng nhập và dữ liệu cloud.',
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _busy ? null : _changePassword,
          icon: const Icon(Icons.lock_reset_outlined),
          label: const Text('Đổi mật khẩu'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _deleteAccount,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error),
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Xóa tài khoản'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Đăng xuất không xóa dữ liệu đang lưu trên thiết bị. Xóa tài khoản sẽ xóa dữ liệu cloud và dữ liệu local liên quan.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildIdentitySection(BuildContext context) {
    final identitiesAsync = ref.watch(authIdentitiesProvider);
    return identitiesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.link_off_outlined),
          title: const Text('Không tải được phương thức đăng nhập'),
          subtitle: Text(friendlyMessage(error)),
          trailing: IconButton(
            tooltip: 'Tải lại',
            onPressed: _busy
                ? null
                : () => ref.invalidate(authIdentitiesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (identities) {
        final hasGoogle = identities.any(
          (identity) => identity.provider == OAuthProvider.google.name,
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Phương thức đăng nhập',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final identity in identities)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_identityIcon(identity.provider)),
                    title: Text(_identityLabel(identity.provider)),
                    subtitle: Text(
                      identity.provider == 'email'
                          ? 'Đăng nhập bằng email và mật khẩu'
                          : 'Đã liên kết với tài khoản này',
                    ),
                    trailing:
                        identity.provider == 'email' || identities.length < 2
                        ? null
                        : IconButton(
                            tooltip: 'Gỡ liên kết',
                            onPressed: _busy
                                ? null
                                : () => _unlinkIdentity(identity),
                            icon: const Icon(Icons.link_off_outlined),
                          ),
                  ),
                if (!hasGoogle) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _linkGoogle,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Liên kết Google'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _identityIcon(String provider) {
    return provider == OAuthProvider.google.name
        ? Icons.account_circle_outlined
        : Icons.email_outlined;
  }

  String _identityLabel(String provider) {
    return switch (provider) {
      'email' => 'Email',
      'google' => 'Google',
      _ => provider,
    };
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    final email = _emailController.text.trim();
    setState(() {
      _busy = true;
      _message = null;
      _verificationEmail = null;
    });
    try {
      if (_registering) {
        final response = await auth.signUp(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) return;
        setState(() {
          _messageIsError = false;
          _verificationEmail = response.session == null ? email : null;
          _message = response.session == null
              ? 'Hãy kiểm tra email để xác nhận tài khoản, sau đó quay lại đăng nhập.'
              : 'Tài khoản đã được tạo và đăng nhập.';
        });
        if (response.session != null) await _runSync();
      } else {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        await _runSync();
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Không thể kết nối Supabase: ${friendlyMessage(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final launched = await auth.signInWithGoogle();
      if (!launched) {
        throw const AuthException('Không thể mở trang đăng nhập Google.');
      }
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã mở Google. Hoàn tất đăng nhập để quay lại ứng dụng.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkGoogle() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final launched = await auth.linkGoogleIdentity();
      if (!launched) {
        throw const AuthException('Không thể mở trang liên kết Google.');
      }
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã mở Google. Hoàn tất liên kết để quay lại ứng dụng.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkIdentity(UserIdentity identity) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Gỡ liên kết ${_identityLabel(identity.provider)}?',
      message:
          'Bạn vẫn giữ được phương thức đăng nhập còn lại. Có thể liên kết lại sau.',
      confirmLabel: 'Gỡ liên kết',
      icon: Icons.link_off_outlined,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.unlinkIdentity(identity);
      ref.invalidate(authIdentitiesProvider);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã gỡ liên kết ${_identityLabel(identity.provider)}.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _runSync();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (AuthValidators.email(email) != null) {
      setState(() {
        _messageIsError = true;
        _message = 'Hãy nhập email hợp lệ trước khi khôi phục mật khẩu.';
      });
      return;
    }
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã gửi email khôi phục mật khẩu. Hãy kiểm tra hộp thư.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendSignupConfirmation() async {
    final email = (_verificationEmail ?? _emailController.text).trim();
    if (AuthValidators.email(email) != null) {
      setState(() {
        _messageIsError = true;
        _message = 'Hãy nhập lại email hợp lệ để gửi email xác nhận.';
      });
      return;
    }
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.resendSignupConfirmation(email);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _verificationEmail = email;
        _message = 'Đã gửi lại email xác nhận. Hãy kiểm tra cả thư mục spam.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (password == null || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.updatePassword(password);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã đổi mật khẩu thành công.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync() async {
    await ref.read(syncOutboxStoreProvider).retryFailed();
    final result = await ref.read(syncCoordinatorProvider).runOnce();
    if (!mounted) return;
    setState(() {
      _messageIsError = result.upload.failed > 0 || result.conflicts > 0;
      _message = result.conflicts > 0
          ? 'Đã gửi ${result.upload.pushed}, tải về ${result.applied}; có ${result.conflicts} xung đột cần kiểm tra.'
          : result.upload.failed > 0
          ? 'Đã gửi ${result.upload.pushed} thay đổi, ${result.upload.failed} thay đổi bị lỗi.'
          : 'Đã gửi ${result.upload.pushed}, tải về ${result.applied} thay đổi từ Supabase.';
    });
  }

  Future<void> _signOut() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() => _busy = true);
    try {
      await auth.signOut();
      await _clearBudgetNotifications();
      if (!mounted) return;
      setState(() {
        _message = null;
        _passwordController.clear();
        _confirmationController.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Không thể đăng xuất: ${friendlyMessage(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final canDelete =
              confirmationController.text.trim().toUpperCase() == 'XÓA';
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: const Text('Xóa tài khoản?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tài khoản, dữ liệu đồng bộ và tệp backup cloud sẽ bị xóa vĩnh viễn. Dữ liệu local liên quan cũng sẽ bị xóa. Thao tác này không thể hoàn tác.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmationController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nhập XÓA để xác nhận',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: canDelete
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: const Text('Xóa vĩnh viễn'),
              ),
            ],
          );
        },
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    var deletedRemotely = false;
    var signedOut = false;
    final deletedUserId = auth.currentUser?.id;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.deleteAccount();
      deletedRemotely = true;
      await _clearLocalAccountData(deletedUserId);
      await auth.signOut();
      signedOut = true;
    } on Object catch (error) {
      if (deletedRemotely) {
        var localCleaned = false;
        try {
          await _clearLocalAccountData(deletedUserId);
          localCleaned = true;
        } on Object {
          localCleaned = false;
        }
        try {
          await auth.signOut();
          signedOut = true;
        } on Object catch (signOutError) {
          if (mounted) {
            setState(() {
              _messageIsError = true;
              _message =
                  'Tài khoản đã xóa trên máy chủ. Hãy khởi động lại ứng dụng để hoàn tất đăng xuất: ${friendlyMessage(signOutError)}';
            });
          }
        }
        if (localCleaned && signedOut) {
          if (mounted) {
            setState(() {
              _messageIsError = false;
              _message = 'Tài khoản và dữ liệu đã được xóa.';
            });
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = deletedRemotely
            ? 'Tài khoản đã bị xóa trên máy chủ nhưng chưa dọn hết dữ liệu local. Hãy khởi động lại ứng dụng.'
            : friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLocalAccountData(String? userId) async {
    final scopedUserId = userId?.trim().toLowerCase();
    if (!LocalDatabaseScope.isValidUserId(scopedUserId)) {
      throw StateError('Không xác định được dữ liệu local của tài khoản.');
    }
    final includeLegacy = await LocalDatabaseScope.ownsLegacyDatabase(
      scopedUserId,
    );
    final database = AppDatabase(
      null,
      LocalDatabaseScope.databaseName(
        userId: scopedUserId,
        cloudConfigured: true,
      ),
    );
    final repository = DriftInvoiceRepository(database);
    final importJobs = DriftImportJobStore(database);
    Object? firstError;
    final cleanups = <Future<void> Function()>[
      repository.deleteAllUserData,
      importJobs.clear,
      () => PendingImportStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => ChatHistoryStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => AnomalyFeedbackStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => BackupCatalogStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => BudgetAlertPreferences(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      _clearBudgetNotifications,
    ];
    try {
      for (final cleanup in cleanups) {
        try {
          await cleanup();
        } on Object catch (error) {
          firstError ??= error;
        }
      }
    } finally {
      try {
        await database.close();
      } on Object catch (error) {
        firstError ??= error;
      }
      try {
        await LocalDatabaseScope.releaseLegacyDatabase(scopedUserId);
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  Future<void> _clearBudgetNotifications() async {
    try {
      await BudgetNotificationService.instance.cancelBudgetNotifications();
    } on Object {
      return;
    }
  }
}

class _ConfigurationMissingCard extends StatelessWidget {
  const _ConfigurationMissingCard();

  @override
  Widget build(BuildContext context) {
    // Không phải LỖI: đây là một build hợp lệ, chỉ là không có cloud. App vẫn
    // chạy đủ chức năng local, nên giọng điệu và lối ra phải phản ánh điều đó.
    return AppCallout(
      icon: Icons.cloud_off_outlined,
      tone: CalloutTone.info,
      title: 'Bản build này không có đồng bộ cloud',
      message:
          'Nhập hóa đơn, OCR, ngân sách và toàn bộ thống kê vẫn hoạt động và '
          'dữ liệu được lưu trên máy. Tài khoản và đồng bộ cần cấu hình '
          'Supabase khi build.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Tiếp tục dùng offline'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đổi mật khẩu'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mật khẩu mới',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? 'Mật khẩu cần ít nhất 8 ký tự.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmationController,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu'),
              validator: (value) => value != _passwordController.text
                  ? 'Hai mật khẩu chưa khớp.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              Navigator.pop(context, _passwordController.text);
            }
          },
          child: const Text('Lưu mật khẩu'),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final foreground = isError
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;
    return AppCallout(
      icon: icon,
      title: title,
      message: message,
      tone: isError ? CalloutTone.danger : CalloutTone.info,
      actions: onAction == null
          ? const []
          : [
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(actionLabel!),
              ),
            ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            container: true,
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
