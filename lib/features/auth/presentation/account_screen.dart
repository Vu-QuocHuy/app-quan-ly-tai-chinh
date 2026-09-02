import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/app_providers.dart';

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
              padding: const EdgeInsets.all(16),
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
                      message: '$error',
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
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _registering ? 'Tạo tài khoản' : 'Đăng nhập Supabase',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'OCR và dữ liệu local vẫn hoạt động khi mất mạng. Tài khoản dùng để sao lưu và đồng bộ hóa đơn.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
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
                      _message = null;
                    });
                  },
          ),
          const SizedBox(height: 20),
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
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _emailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'ban@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Hãy nhập email.';
              if (!email.contains('@') || !email.contains('.')) {
                return 'Email chưa đúng định dạng.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            enabled: !_busy,
            obscureText: _obscurePassword,
            textInputAction: _registering
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: [
              _registering ? AutofillHints.newPassword : AutofillHints.password,
            ],
            onFieldSubmitted: _registering || _busy ? null : (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              helperText: _registering ? 'Dùng ít nhất 8 ký tự.' : null,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                onPressed: _busy
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Hãy nhập mật khẩu.';
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmationController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: _busy ? null : (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Nhập lại mật khẩu',
                prefixIcon: Icon(Icons.lock_reset_outlined),
              ),
              validator: (value) => value != _passwordController.text
                  ? 'Hai mật khẩu chưa khớp.'
                  : null,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _registering
                        ? Icons.person_add_alt_1_outlined
                        : Icons.login,
                  ),
            label: Text(_registering ? 'Tạo tài khoản' : 'Đăng nhập'),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedIn(BuildContext context, User user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: Icons.cloud_done_outlined,
          title: 'Đã kết nối Supabase',
          message: user.email ?? 'Tài khoản ${user.id}',
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
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
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _syncNow,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('Đồng bộ ngay'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _changePassword,
          icon: const Icon(Icons.lock_reset_outlined),
          label: const Text('Đổi mật khẩu'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
        const SizedBox(height: 16),
        Text(
          'Đăng xuất không xóa dữ liệu đang lưu trên thiết bị.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
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
          _message = response.session == null
              ? 'Hãy kiểm tra email để xác nhận tài khoản, sau đó đăng nhập.'
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
        _message = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Không thể kết nối Supabase: $error';
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
    if (!email.contains('@') || !email.contains('.')) {
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
        _message = error.message;
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
        _message = error.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync() async {
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
        _message = 'Không thể đăng xuất: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ConfigurationMissingCard extends StatelessWidget {
  const _ConfigurationMissingCard();

  @override
  Widget build(BuildContext context) {
    return const _StatusCard(
      icon: Icons.settings_ethernet_outlined,
      title: 'Supabase chưa được cấu hình khi build',
      message:
          'Chạy app với --dart-define-from-file=config/supabase.local.json để bật tài khoản và đồng bộ.',
      isError: true,
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
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;
    return Card(
      color: isError ? colors.errorContainer : colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: TextStyle(color: foreground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
